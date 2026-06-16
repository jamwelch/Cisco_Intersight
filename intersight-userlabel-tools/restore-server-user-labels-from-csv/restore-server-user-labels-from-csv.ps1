#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Intersight.PowerShell'; ModuleVersion = '1.0.11' }

<#
.SYNOPSIS
    Restore Intersight server UserLabel values from a CSV backup.

.DESCRIPTION
    Reads a CSV (typically produced by the backup one-liner in the sync-server-user-labels-from-profile
    README, or any CSV with the right columns) and sets each listed server's UserLabel back to the
    value in the CSV.

    Rows are matched to servers by Moid (the only stable identifier).
    Servers whose current UserLabel already matches the CSV value are skipped (no API write).
    Empty UserLabel cells are treated as "clear the label" and will overwrite an existing label
    with an empty string - this is correct for restoring servers that had no label at backup time.

    Safe to re-run. Supports -WhatIf and -Confirm.

.PARAMETER ApiKeyId
    Intersight API Key ID. Required.

.PARAMETER ApiKeySecretPath
    Path to the PEM secret key paired with ApiKeyId. Required.

.PARAMETER ApiEndpoint
    Intersight base URL. Default: https://intersight.com
    For Intersight Appliance, pass the appliance FQDN.

.PARAMETER InputPath
    Path to the CSV file. Required.

    Required columns:
        Moid       - Intersight Moid of the server (primary key)
        UserLabel  - The label to restore. Empty cell = clear the label.

    Optional columns (used when present):
        ObjectType - 'compute.Blade' or 'compute.RackUnit'. Skips a discovery lookup.
        Name       - Server name (for display only).
        Serial     - Serial number (for display only).

    Extra columns are ignored.

.PARAMETER MaxLabelLength
    UserLabel truncation length. Default 64 (Intersight's current cap).

.PARAMETER AllowClear
    Required to actually overwrite a non-empty current label with an empty CSV value.
    Without this switch, rows with an empty UserLabel value are SKIPPED with a warning,
    even on a real run. Prevents accidental mass-clearing if the CSV is malformed.

.EXAMPLE
    # Always dry-run first.
    ./restore-server-user-labels-from-csv.ps1 `
        -ApiKeyId         '<your key id>' `
        -ApiKeySecretPath './intersight-secret.pem' `
        -InputPath        ./userlabel-backup.csv `
        -WhatIf

.EXAMPLE
    # Real restore. -AllowClear lets empty CSV values clear existing labels.
    ./restore-server-user-labels-from-csv.ps1 `
        -ApiKeyId         '<your key id>' `
        -ApiKeySecretPath './intersight-secret.pem' `
        -InputPath        ./userlabel-backup.csv `
        -AllowClear

.NOTES
    Companion to sync-server-user-labels-from-profile.ps1 in the sibling directory.
    Requires the Intersight.PowerShell SDK. Recommended install (PowerShell 7.x):
        Install-PSResource Intersight.PowerShell -Scope CurrentUser -TrustRepository
    See README.md for fallbacks if Install-PSResource is not available.
    See README.md alongside this script for full requirements, role needs, and troubleshooting.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [string]$ApiKeyId,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ApiKeySecretPath,

    [string]$ApiEndpoint = 'https://intersight.com',

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputPath,

    [ValidateRange(1, 64)]
    [int]$MaxLabelLength = 64,

    [switch]$AllowClear
)

# ---------------------------------------------------------------------------
# WhatIf / Confirm propagation guard
#
# The Intersight.PowerShell module declares SupportsShouldProcess on every
# cmdlet, including read-only Get-* ones. Without these defaults, passing
# -WhatIf to this script also suppresses the Get-* calls and we would see
# "Found 0 server(s)" with no real query happening. Force read-only
# Intersight cmdlets to always execute regardless of -WhatIf / -Confirm.
# The mutating Set-Intersight* calls stay gated by ShouldProcess below.
# ---------------------------------------------------------------------------

$PSDefaultParameterValues['Get-Intersight*:WhatIf']     = $false
$PSDefaultParameterValues['Get-Intersight*:Confirm']    = $false
$PSDefaultParameterValues['Find-Intersight*:WhatIf']    = $false
$PSDefaultParameterValues['Find-Intersight*:Confirm']   = $false
$PSDefaultParameterValues['Search-Intersight*:WhatIf']  = $false
$PSDefaultParameterValues['Search-Intersight*:Confirm'] = $false

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

$script:Counters = [ordered]@{
    Restored        = 0
    SkippedInSync   = 0
    SkippedEmpty    = 0    # empty CSV value + -AllowClear not set
    SkippedWhatIf   = 0
    Failed          = 0
}

function Write-Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Restored','SkippedInSync','SkippedEmpty','SkippedWhatIf','Failed')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$Item,

        [string]$Moid,
        [string]$Message
    )

    $script:Counters[$Action]++
    $ts   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ssZ')
    $tail = ''
    if ($Moid)    { $tail += " moid=$Moid" }
    if ($Message) { $tail += " msg=$Message" }

    $label  = $Action.ToUpper().PadRight(15)
    $color  = switch ($Action) {
        'Restored'      { 'Green' }
        'SkippedInSync' { 'DarkGray' }
        'SkippedEmpty'  { 'DarkYellow' }
        'SkippedWhatIf' { 'DarkYellow' }
        'Failed'        { 'Red' }
    }
    Write-Host "[$ts] $label $Item$tail" -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# Load and validate CSV
# ---------------------------------------------------------------------------

$rows = Import-Csv -LiteralPath $InputPath
if (-not $rows -or @($rows).Count -eq 0) {
    Write-Warning "Input file '$InputPath' produced no rows. Nothing to do."
    return
}

$firstRow = $rows | Select-Object -First 1
$cols     = $firstRow.PSObject.Properties.Name

foreach ($required in 'Moid','UserLabel') {
    if ($cols -notcontains $required) {
        throw "CSV is missing required column '$required'. Columns present: $($cols -join ', ')"
    }
}

$hasObjectType = $cols -contains 'ObjectType'
Write-Host "Loaded $(@($rows).Count) row(s) from $InputPath" -ForegroundColor Cyan
Write-Host ("ObjectType column: {0}" -f $(if ($hasObjectType) {'present (fast path)'} else {'absent (will index servers for lookup)'})) -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Connect to Intersight
# ---------------------------------------------------------------------------

try {
    $resolvedSecret = (Resolve-Path -LiteralPath $ApiKeySecretPath).Path

    Set-IntersightConfiguration `
        -BasePath          $ApiEndpoint `
        -ApiKeyId          $ApiKeyId `
        -ApiKeyFilePath    $resolvedSecret `
        -HttpSigningHeader @('(request-target)', 'Host', 'Date', 'Digest')

    Write-Verbose "Configured Intersight endpoint $ApiEndpoint"
}
catch {
    throw "Failed to initialize Intersight client: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Build server index (only if needed for ObjectType discovery or current-label compare).
# ---------------------------------------------------------------------------

Write-Host 'Fetching servers...' -ForegroundColor Cyan

$serverIndex = @{}  # key = Moid, value = pscustomobject

try {
    $blades = Get-IntersightComputeBlade
    $racks  = Get-IntersightComputeRackUnit
}
catch {
    throw "Failed to enumerate servers: $($_.Exception.Message)"
}

foreach ($s in @($blades) + @($racks)) {
    if ($null -eq $s) { continue }
    $serverIndex[$s.Moid] = [pscustomobject]@{
        Moid       = $s.Moid
        ObjectType = $s.ObjectType
        Name       = $s.Name
        UserLabel  = $s.UserLabel
        Serial     = $s.Serial
    }
}

Write-Host "Indexed $($serverIndex.Count) server(s) in the account." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

foreach ($row in $rows) {

    $rowMoid = ($row.Moid | ForEach-Object { $_.ToString().Trim() })
    if (-not $rowMoid) {
        Write-Result -Action Failed -Item '<row with empty Moid>' -Message 'Skipping row without Moid'
        continue
    }

    $desiredLabel = if ($null -eq $row.UserLabel) { '' } else { [string]$row.UserLabel }

    # Truncate if needed.
    if ($desiredLabel.Length -gt $MaxLabelLength) {
        $original     = $desiredLabel
        $desiredLabel = $desiredLabel.Substring(0, $MaxLabelLength)
        Write-Warning "Row Moid=$rowMoid : CSV UserLabel '$original' exceeds $MaxLabelLength chars; truncating to '$desiredLabel'."
    }

    $serverObj = $serverIndex[$rowMoid]
    if (-not $serverObj) {
        Write-Result -Action Failed -Item "Moid $rowMoid" -Moid $rowMoid `
                     -Message 'Server not found in current account (decommissioned, wrong account, or permission gap)'
        continue
    }

    # Decide ObjectType to dispatch on (CSV column wins if present and non-empty, else live data).
    $objectType =
        if ($hasObjectType -and $row.ObjectType) { [string]$row.ObjectType }
        else                                     { $serverObj.ObjectType }

    $serverDisplay = if ($serverObj.Name) { $serverObj.Name } else { "$objectType $rowMoid" }
    $itemTag       = "server '$serverDisplay' (serial=$($serverObj.Serial))"

    $currentLabel = if ($null -eq $serverObj.UserLabel) { '' } else { [string]$serverObj.UserLabel }

    # Already in sync.
    if ($currentLabel -ceq $desiredLabel) {
        Write-Result -Action SkippedInSync -Item $itemTag -Moid $rowMoid -Message "UserLabel already '$desiredLabel'"
        continue
    }

    # Empty desired label + safety not enabled = skip with warning.
    if ([string]::IsNullOrEmpty($desiredLabel) -and -not $AllowClear) {
        Write-Result -Action SkippedEmpty -Item $itemTag -Moid $rowMoid `
                     -Message "CSV UserLabel is empty; pass -AllowClear to overwrite current label '$currentLabel'"
        continue
    }

    $action = "Restore UserLabel = '$desiredLabel' (was '$currentLabel')"

    if (-not $PSCmdlet.ShouldProcess($itemTag, $action)) {
        Write-Result -Action SkippedWhatIf -Item $itemTag -Moid $rowMoid -Message $action
        continue
    }

    try {
        switch ($objectType) {
            'compute.Blade'    { Set-IntersightComputeBlade    -Moid $rowMoid -UserLabel $desiredLabel | Out-Null }
            'compute.RackUnit' { Set-IntersightComputeRackUnit -Moid $rowMoid -UserLabel $desiredLabel | Out-Null }
            default {
                throw "Unsupported ObjectType '$objectType' for Moid $rowMoid"
            }
        }
        Write-Result -Action Restored -Item $itemTag -Moid $rowMoid -Message $action
    }
    catch {
        Write-Result -Action Failed -Item $itemTag -Moid $rowMoid -Message $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '----- Summary -----' -ForegroundColor Cyan
$script:Counters.GetEnumerator() | ForEach-Object {
    Write-Host ("  {0,-15} {1}" -f $_.Key, $_.Value)
}
Write-Host '-------------------' -ForegroundColor Cyan

if ($script:Counters.Failed -gt 0) { exit 1 } else { exit 0 }

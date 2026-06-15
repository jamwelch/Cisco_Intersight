#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Intersight.PowerShell'; ModuleVersion = '1.0.11' }

<#
.SYNOPSIS
    Sync each Intersight server's UserLabel to match the name of its assigned Server Profile.

.DESCRIPTION
    Walks every Server Profile in scope. For each profile that has an AssignedServer,
    compares the server's current UserLabel to the profile's Name and, if they differ,
    updates the server (Compute.Blade or Compute.RackUnit) so UserLabel == ProfileName.

    Servers with no assigned profile are skipped and logged. Servers whose label
    already matches are logged as Skipped (no API write). UserLabel has a 64-character
    cap in Intersight; longer profile names are truncated with a warning.

    Safe to re-run. Supports -WhatIf and -Confirm.

.PARAMETER ApiKeyId
    Intersight API Key ID. Required.

.PARAMETER ApiKeySecretPath
    Path to the PEM secret key paired with ApiKeyId. Required.
    Store this file outside source control with restrictive file permissions
    (read-only to your user account, no group/world access).

.PARAMETER ApiEndpoint
    Intersight base URL. Default: https://intersight.com
    For Intersight Appliance, pass the appliance FQDN.

.PARAMETER Organization
    Restrict to one organization by name. Omit to process every org the API key can see.

.PARAMETER MaxLabelLength
    UserLabel truncation length. Default 64 (current Intersight limit). Lower if your
    site policy requires a shorter cap.

.EXAMPLE
    # Dry-run first - shows planned changes, makes none.
    ./sync-server-user-labels-from-profile.ps1 `
        -ApiKeyId         '<your key id>' `
        -ApiKeySecretPath './intersight-secret.pem' `
        -WhatIf

.EXAMPLE
    # Real run, all orgs.
    ./sync-server-user-labels-from-profile.ps1 `
        -ApiKeyId         '<your key id>' `
        -ApiKeySecretPath './intersight-secret.pem'

.EXAMPLE
    # Real run scoped to one org.
    ./sync-server-user-labels-from-profile.ps1 `
        -ApiKeyId         '<your key id>' `
        -ApiKeySecretPath './intersight-secret.pem' `
        -Organization     'engineering'

.NOTES
    Requires the Intersight.PowerShell SDK (Install-Module Intersight.PowerShell -Scope CurrentUser).
    See README.md alongside this script for full requirements, role needs, and troubleshooting.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$ApiKeyId,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ApiKeySecretPath,

    [string]$ApiEndpoint = 'https://intersight.com',

    [string]$Organization,

    [ValidateRange(1, 64)]
    [int]$MaxLabelLength = 64
)

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

$script:Counters = [ordered]@{
    Updated         = 0
    SkippedInSync   = 0
    SkippedNoProfile= 0
    SkippedWhatIf   = 0
    Failed          = 0
}

function Write-Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Updated','SkippedInSync','SkippedNoProfile','SkippedWhatIf','Failed')]
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

    $label  = $Action.ToUpper().PadRight(18)
    $color  = switch ($Action) {
        'Updated'          { 'Green' }
        'SkippedInSync'    { 'DarkGray' }
        'SkippedNoProfile' { 'DarkGray' }
        'SkippedWhatIf'    { 'DarkYellow' }
        'Failed'           { 'Red' }
    }
    Write-Host "[$ts] $label $Item$tail" -ForegroundColor $color
}

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
# Resolve optional organization filter
# ---------------------------------------------------------------------------

$orgFilter = $null
if ($Organization) {
    $org = Get-IntersightOrganizationOrganization -Name $Organization -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if (-not $org) {
        throw "Organization '$Organization' not found. Check spelling (case sensitive) and that the API key has access."
    }
    $orgFilter = $org.Moid
    Write-Host "Scoping to organization '$Organization' (Moid $orgFilter)" -ForegroundColor Cyan
}
else {
    Write-Host 'No -Organization specified; processing all orgs the API key can see.' -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Pre-fetch all servers into a Moid-keyed lookup so we make one round trip
# per server type instead of one per profile.
# ---------------------------------------------------------------------------

Write-Host 'Fetching servers...' -ForegroundColor Cyan

$serverIndex = @{}  # key = Moid, value = pscustomobject with .ObjectType + .UserLabel + .Name

try {
    $blades = if ($orgFilter) {
        Get-IntersightComputeBlade -Filter "Organization.Moid eq '$orgFilter'"
    } else {
        Get-IntersightComputeBlade
    }

    $racks  = if ($orgFilter) {
        Get-IntersightComputeRackUnit -Filter "Organization.Moid eq '$orgFilter'"
    } else {
        Get-IntersightComputeRackUnit
    }
}
catch {
    throw "Failed to enumerate servers: $($_.Exception.Message)"
}

foreach ($s in @($blades) + @($racks)) {
    if ($null -eq $s) { continue }
    $serverIndex[$s.Moid] = [pscustomobject]@{
        Moid       = $s.Moid
        ObjectType = $s.ObjectType    # 'compute.Blade' or 'compute.RackUnit'
        Name       = $s.Name
        UserLabel  = $s.UserLabel
        Serial     = $s.Serial
    }
}

Write-Host "Found $($serverIndex.Count) server(s)." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Fetch server profiles in scope.
# ---------------------------------------------------------------------------

Write-Host 'Fetching server profiles...' -ForegroundColor Cyan

try {
    $profiles = if ($orgFilter) {
        Get-IntersightServerProfile -Filter "Organization.Moid eq '$orgFilter'"
    } else {
        Get-IntersightServerProfile
    }
}
catch {
    throw "Failed to enumerate server profiles: $($_.Exception.Message)"
}

Write-Host "Found $(@($profiles).Count) server profile(s)." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Reconcile: walk profiles, update assigned server's UserLabel if needed.
# Track which servers got covered so we can report leftovers.
# ---------------------------------------------------------------------------

$coveredServerMoids = [System.Collections.Generic.HashSet[string]]::new()

foreach ($profile in @($profiles)) {

    $profileName = $profile.Name
    $assigned    = $profile.AssignedServer

    if (-not $assigned -or -not $assigned.Moid) {
        Write-Verbose "Profile '$profileName' has no AssignedServer; nothing to label."
        continue
    }

    $serverMoid = $assigned.Moid
    $serverObj  = $serverIndex[$serverMoid]

    if (-not $serverObj) {
        Write-Result -Action Failed `
                     -Item   "profile '$profileName'" `
                     -Moid   $serverMoid `
                     -Message "AssignedServer Moid not in fetched server list (different org or permission?)"
        continue
    }

    [void]$coveredServerMoids.Add($serverMoid)

    # Determine desired label (truncate if needed).
    $desiredLabel = $profileName
    if ($desiredLabel.Length -gt $MaxLabelLength) {
        $original    = $desiredLabel
        $desiredLabel = $desiredLabel.Substring(0, $MaxLabelLength)
        Write-Warning "Profile name '$original' exceeds $MaxLabelLength chars; truncating UserLabel to '$desiredLabel'."
    }

    $currentLabel = if ($null -eq $serverObj.UserLabel) { '' } else { [string]$serverObj.UserLabel }

    $serverDisplay = if ($serverObj.Name) { $serverObj.Name } else { "$($serverObj.ObjectType) $serverMoid" }
    $itemTag       = "server '$serverDisplay' (serial=$($serverObj.Serial))"

    if ($currentLabel -ceq $desiredLabel) {
        Write-Result -Action SkippedInSync -Item $itemTag -Moid $serverMoid -Message "UserLabel already '$desiredLabel'"
        continue
    }

    $action = "Set UserLabel = '$desiredLabel' (was '$currentLabel')"

    if (-not $PSCmdlet.ShouldProcess($itemTag, $action)) {
        Write-Result -Action SkippedWhatIf -Item $itemTag -Moid $serverMoid -Message $action
        continue
    }

    try {
        switch ($serverObj.ObjectType) {
            'compute.Blade'    { Set-IntersightComputeBlade    -Moid $serverMoid -UserLabel $desiredLabel | Out-Null }
            'compute.RackUnit' { Set-IntersightComputeRackUnit -Moid $serverMoid -UserLabel $desiredLabel | Out-Null }
            default {
                throw "Unsupported server ObjectType '$($serverObj.ObjectType)' for Moid $serverMoid"
            }
        }
        Write-Result -Action Updated -Item $itemTag -Moid $serverMoid -Message $action
    }
    catch {
        Write-Result -Action Failed -Item $itemTag -Moid $serverMoid -Message $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Servers with no associated profile: log once each.
# ---------------------------------------------------------------------------

foreach ($s in $serverIndex.Values) {
    if (-not $coveredServerMoids.Contains($s.Moid)) {
        $tag = if ($s.Name) { "server '$($s.Name)'" } else { "$($s.ObjectType) $($s.Moid)" }
        Write-Result -Action SkippedNoProfile -Item "$tag (serial=$($s.Serial))" -Moid $s.Moid -Message 'no Server Profile assigned'
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '----- Summary -----' -ForegroundColor Cyan
$script:Counters.GetEnumerator() | ForEach-Object {
    Write-Host ("  {0,-18} {1}" -f $_.Key, $_.Value)
}
Write-Host '-------------------' -ForegroundColor Cyan

if ($script:Counters.Failed -gt 0) { exit 1 } else { exit 0 }

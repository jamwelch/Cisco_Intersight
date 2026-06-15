# restore-server-user-labels-from-csv

Restore Intersight server **UserLabel** values from a CSV backup. Companion to **`sync-server-user-labels-from-profile`** (sibling directory) — use this script to undo a sync run, or to apply any other previously-captured set of labels.

## Requirements

| Requirement | Version / Detail | Notes |
|---|---|---|
| PowerShell | 7.2 or later | `Intersight.PowerShell` targets .NET Standard 2.1 / .NET 6+. Windows PowerShell 5.1 has Newtonsoft.Json conflicts and is not supported. Install pwsh with `winget install --id Microsoft.PowerShell --source winget`. |
| Module | `Intersight.PowerShell` `>= 1.0.11` | Install: `Install-Module Intersight.PowerShell -Scope CurrentUser`. Latest at time of writing: `1.0.11.2026042921`. Confirm current with `Find-Module Intersight.PowerShell`. |
| Intersight account | Active Intersight SaaS account, or Intersight Appliance | Must contain the servers referenced by Moid in the CSV. |
| API key | API Key ID + private key (PEM) | Generate in **Settings -> API Keys -> Generate API Key**. Choose **ECDSA P-256 + SHA256**. Save the secret file (cannot be re-downloaded). |
| Account role | **Server Administrator** (or higher) on the target org(s), or any role with **Update** on `compute.Blade` and `compute.RackUnit`. Read Only roles will return 403 on update calls. | Per-server 403s are logged as Failed; the rest of the batch continues. |
| Network | Outbound HTTPS 443 to `intersight.com` (or your appliance FQDN) | Cisco VPN may be required if corporate egress restricts external destinations. |
| Optional | `PSScriptAnalyzer` | For local linting: `Install-Module PSScriptAnalyzer -Scope CurrentUser`. |

## Setup

See the sync script's [`README.md`](../sync-server-user-labels-from-profile/README.md) — the install + API key + connectivity-verification steps are identical.

## Usage

> **Always run with `-WhatIf` first.** It shows every label change the script would make, without making any change.

```powershell
# 1. Dry run - shows planned restores
./restore-server-user-labels-from-csv.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>' `
    -InputPath        './userlabel-backup.csv' `
    -WhatIf
```

```powershell
# 2. Real restore. Empty CSV values are SKIPPED unless -AllowClear is set.
./restore-server-user-labels-from-csv.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>' `
    -InputPath        './userlabel-backup.csv'
```

```powershell
# 3. Real restore that also clears labels back to empty for any row whose UserLabel is blank.
./restore-server-user-labels-from-csv.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>' `
    -InputPath        './userlabel-backup.csv' `
    -AllowClear
```

```powershell
# 4. Intersight Appliance
./restore-server-user-labels-from-csv.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>' `
    -ApiEndpoint      'https://intersight.example.com' `
    -InputPath        './userlabel-backup.csv'
```

## CSV format

The script accepts the CSV produced by the backup one-liner in the sync README, and any CSV with the same minimum columns.

### Required columns

| Column | Purpose |
|---|---|
| `Moid` | Intersight Moid of the server. Primary key. |
| `UserLabel` | The label to restore. Empty cell = "clear the label" (only applied if `-AllowClear` is passed). |

### Optional columns

| Column | Purpose |
|---|---|
| `ObjectType` | `compute.Blade` or `compute.RackUnit`. When present, skips a discovery lookup per row. The backup one-liner always includes this. |
| `Name` | Server name. Used in log output for human readability. |
| `Serial` | Serial number. Used in log output. |

Extra columns are ignored.

### Producing a backup CSV

Run this any time (it's read-only) to get a CSV in the exact format the restore script expects:

```powershell
Import-Module Intersight.PowerShell
Set-IntersightConfiguration `
    -BasePath        'https://intersight.com' `
    -ApiKeyId        '<your key id>' `
    -ApiKeyFilePath  '<path-to-secret.pem>'

(Get-IntersightComputeBlade) + (Get-IntersightComputeRackUnit) |
    Select-Object Moid, ObjectType, Name, Serial, UserLabel |
    Export-Csv ./userlabel-backup.csv -NoTypeInformation
```

Tip: save a backup **immediately before** running the sync script so you have a clean restore point.

## What this script changes

- **MO types touched:** `compute.Blade` and `compute.RackUnit`.
- **Field it sets:** `UserLabel` only.
- **Direction:** one-way, CSV -> server. The script never reads from or modifies Server Profiles.

## Behavior, in order

1. Validate the CSV (must have `Moid` and `UserLabel` columns) and load rows.
2. Connect to Intersight.
3. Build a one-time in-memory index of all servers (`compute.Blade` + `compute.RackUnit`) keyed by Moid.
4. For each CSV row:
   - Look up the server by `Moid` in the index.
     - If not found -> `FAILED` (server was decommissioned, lives in an org this key can't see, or wrong account).
   - Decide the dispatch type: CSV `ObjectType` if present and non-empty, otherwise live `ObjectType` from the index.
   - Truncate the desired label if it exceeds `-MaxLabelLength` (default 64), with a warning.
   - If current label already matches CSV value -> `SKIPPEDINSYNC`, no API write.
   - If CSV value is empty and `-AllowClear` was not passed -> `SKIPPEDEMPTY`, no API write.
   - Otherwise call the right `Set-IntersightCompute*` cmdlet to set `UserLabel`.
5. Print a counts summary. Exit `0` if all OK, `1` if any row logged `FAILED`.

## Safety: why `-AllowClear` is opt-in

A common foot-gun: someone produces a CSV that, due to an export bug or column shift, ends up with empty `UserLabel` values everywhere. Without a guard, restoring that CSV would silently blank every label in the environment.

By default, this script **skips** rows whose CSV `UserLabel` is empty, logs `SKIPPEDEMPTY`, and tells you in the message that `-AllowClear` would do the actual clear. Pass `-AllowClear` only when you have verified the CSV genuinely represents "no label" for those servers (e.g. it was produced by the backup one-liner and those servers really were unlabeled).

## Idempotency / re-run

Re-running is safe and cheap:

- Servers already in the desired state are detected via in-memory comparison; no API write is issued.
- Servers no longer present in Intersight are logged as `FAILED` (informational); they're skipped on every subsequent run.

## Edge cases and notes

- **Empty CSV cell:** `Import-Csv` represents empty cells as empty strings (not `$null`). The script normalizes both to `''`.
- **Whitespace-only labels:** preserved as-is. If you didn't intend that, sanitize the CSV first.
- **Profile name > 64 characters in a CSV captured from the sync script:** the backup one-liner only stores what's already on the server, so this is rare. If it happens, the restore script truncates and warns, identical to the sync script.
- **Servers spanning multiple orgs:** the script fetches all blades and rack units the API key can see, across every org. Make sure the key used for restore can see at least the same orgs as the key used for the backup.
- **Mixed CSV provenance:** rows from different backups can be merged into one CSV; the script doesn't care, it just processes Moids.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `CSV is missing required column 'Moid'` (or `'UserLabel'`) | CSV was edited or exported with the wrong columns | Re-export with the backup one-liner above, or add the missing column. |
| Many rows logged as `FAILED ... Server not found in current account` | Wrong API key (different account / tenant), or servers truly decommissioned | Confirm with `Get-IntersightComputeBlade | Where-Object Moid -eq '<moid>'` whether the Moid exists. |
| All rows logged as `SKIPPEDEMPTY` | Your CSV has empty `UserLabel` values (probably intentional for an "unlabel everything" pass) | Re-run with `-AllowClear` once you have confirmed that's the intent. |
| `401 Unauthorized` / `Signature verification failed` | Wrong `ApiKeyId`, wrong PEM, or key revoked | Re-check Key ID in UI; regenerate the key pair if needed. |
| `403 Forbidden` on specific servers | API key's role lacks **Update** on `compute.Blade` / `compute.RackUnit` in the affected org | Use **Server Administrator** or higher for the affected org and rerun; the script is idempotent. |
| `The term 'Set-IntersightConfiguration' is not recognized` | Module not installed, or running in Windows PowerShell 5.1 | `Install-Module Intersight.PowerShell -Scope CurrentUser` in **`pwsh` 7.x**. |
| Long hang, then network error | Corporate proxy / VPN required | Connect Cisco VPN; verify `Test-NetConnection intersight.com -Port 443`. |

## See also

- [`sync-server-user-labels-from-profile`](../sync-server-user-labels-from-profile/README.md) — the forward direction. Use this restore script to undo a sync run.

## Sample output

```
Loaded 42 row(s) from ./userlabel-backup.csv
ObjectType column: present (fast path)
Fetching servers...
Indexed 42 server(s) in the account.
[2026-06-15 14:02:11Z] SKIPPEDINSYNC   server 'rack-12-srv-03' (serial=FCH2345...) moid=64b... msg=UserLabel already 'web-prod-03'
[2026-06-15 14:02:11Z] RESTORED        server 'rack-12-srv-04' (serial=FCH2347...) moid=64c... msg=Restore UserLabel = 'web-prod-old' (was 'web-prod-04')
[2026-06-15 14:02:12Z] SKIPPEDEMPTY    server 'rack-99-spare-01' (serial=FCH9911...) moid=64d... msg=CSV UserLabel is empty; pass -AllowClear to overwrite current label 'temp-label'
[2026-06-15 14:02:12Z] FAILED          Moid 64e... moid=64e... msg=Server not found in current account (decommissioned, wrong account, or permission gap)
...
----- Summary -----
  Restored        17
  SkippedInSync   23
  SkippedEmpty    1
  SkippedWhatIf   0
  Failed          1
-------------------
```

## Change log

- `2026-06-15` - initial version.

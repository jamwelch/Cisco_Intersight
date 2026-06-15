# Intersight User Label Tools

A small pair of PowerShell scripts for keeping Cisco Intersight server **UserLabel** values aligned with their assigned Server Profiles, and for rolling that change back from a CSV backup.

Both scripts are built on Cisco's officially published [`Intersight.PowerShell`](https://www.powershellgallery.com/packages/Intersight.PowerShell) module and are intended to replace repetitive manual UI work. Safe to re-run, support `-WhatIf`, log per-server results, and never abort the batch on a single bad row.

## What's in this package

| Folder | Purpose |
|---|---|
| [`sync-server-user-labels-from-profile/`](./sync-server-user-labels-from-profile/) | Sets every server's `UserLabel` to match the **Name** of its assigned Server Profile. |
| [`restore-server-user-labels-from-csv/`](./restore-server-user-labels-from-csv/) | Restores `UserLabel` values from a CSV backup. Companion to the sync script. |

Each folder contains its own `.ps1` and a detailed `README.md`. Read those before running anything.

## Quick start

1. **Install prerequisites** (one-time, per machine):

   ```powershell
   # PowerShell 7.2+ required. On Windows:
   winget install --id Microsoft.PowerShell --source winget

   # Install the Intersight SDK
   Install-Module Intersight.PowerShell -Scope CurrentUser
   ```

2. **Generate an Intersight API key** in the Intersight UI:
   - **Settings -> API Keys -> Generate API Key**
   - Choose **ECDSA P-256 + SHA256** (recommended)
   - Download the secret PEM file (it cannot be re-downloaded later) and store it somewhere outside source control

3. **Take a UserLabel backup before any change**, so you always have a clean rollback point:

   ```powershell
   Import-Module Intersight.PowerShell
   Set-IntersightConfiguration `
       -BasePath        'https://intersight.com' `
       -ApiKeyId        '<your API key ID>' `
       -ApiKeyFilePath  '<path to your secret PEM>'
   (Get-IntersightComputeBlade) + (Get-IntersightComputeRackUnit) |
       Select-Object Moid, ObjectType, Name, Serial, UserLabel |
       Export-Csv ./userlabel-backup.csv -NoTypeInformation
   ```

4. **Dry-run the sync** to see what would change without changing anything:

   ```powershell
   cd ./sync-server-user-labels-from-profile
   ./sync-server-user-labels-from-profile.ps1 `
       -ApiKeyId         '<your API key ID>' `
       -ApiKeySecretPath '<path to your secret PEM>' `
       -WhatIf
   ```

5. **Apply** by re-running without `-WhatIf` when you're happy with the plan.

6. **Rollback** any time from your backup CSV — see `restore-server-user-labels-from-csv/README.md`.

## Requirements summary

| Requirement | Detail |
|---|---|
| PowerShell | 7.2 or later. Windows PowerShell 5.1 is not supported (Newtonsoft.Json conflicts in the Intersight SDK). |
| Intersight SDK | `Intersight.PowerShell` >= 1.0.11 from PowerShell Gallery. |
| Intersight account | SaaS (intersight.com) or Intersight Appliance. |
| API key | API Key ID + ECDSA P-256 secret key (PEM). |
| Account role | At minimum **Server Administrator** on the target organization(s) — needed for `Update` on `compute.Blade` and `compute.RackUnit`. Read-only roles will return 403 on writes. |
| Network | Outbound HTTPS 443 to `intersight.com` or your appliance FQDN. |

Each script's README has the full per-script requirements and troubleshooting tables.

## Safety model

- **Both scripts support `-WhatIf`.** Always dry-run first.
- **Both scripts are idempotent.** Re-running is safe; servers already in the desired state are skipped (no API write).
- **Per-row error isolation.** A failure on one server does not abort the rest of the batch. Exit code is `1` only if at least one row failed.
- **No destructive operations.** Neither script deletes, decommissions, or unbinds anything; both only set the `UserLabel` field on existing server objects.
- **Sensitive inputs are file-based.** The API key Secret is read from a file path you control; the scripts never embed or echo it.

## Cross-platform notes

PowerShell 7 runs on **Windows, macOS, and Linux**. The scripts use forward-slash and backslash-tolerant paths and have no platform-specific calls. Examples in the docs are written with `./` for portability; substitute `.\` if you prefer Windows-style.

## Licensing and support

See [`LICENSE`](./LICENSE) for the licensing terms (BSD-2-Clause, permissive).

See [`NOTICE.md`](./NOTICE.md) for the support model — **important read before running in production**.

## File layout

```
intersight-userlabel-tools/
├── README.md                                       # this file
├── LICENSE                                         # BSD-2-Clause
├── NOTICE.md                                       # support model & no-warranty disclaimer
├── sync-server-user-labels-from-profile/
│   ├── sync-server-user-labels-from-profile.ps1
│   └── README.md
└── restore-server-user-labels-from-csv/
    ├── restore-server-user-labels-from-csv.ps1
    └── README.md
```

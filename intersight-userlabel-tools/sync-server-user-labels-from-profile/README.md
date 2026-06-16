# sync-server-user-labels-from-profile

Set every Intersight server's **UserLabel** to match the **Name of its assigned Server Profile**, so the label shown in inventory always reflects the profile (and therefore the workload) currently running on that hardware.

> Read the top-level [`README.md`](../README.md) and [`NOTICE.md`](../NOTICE.md) before running in production.

## Requirements

| Requirement | Version / Detail | Notes |
|---|---|---|
| PowerShell | 7.2 or later | The Intersight SDK targets .NET Standard 2.1 / .NET 6+. Windows PowerShell 5.1 has Newtonsoft.Json conflicts and is not supported. On Windows: `winget install --id Microsoft.PowerShell --source winget`. |
| Module | `Intersight.PowerShell` `>= 1.0.11` | Install with `Install-PSResource Intersight.PowerShell -Scope CurrentUser -TrustRepository` (see **Setup** for fallbacks). Confirm with `Find-PSResource Intersight.PowerShell`. |
| Intersight account | Active Intersight SaaS account, or Intersight Appliance | Must contain the target Organization(s) and the servers you want to relabel. |
| API key | API Key ID + private key (PEM) | Generate in **Settings -> API Keys -> Generate API Key**. Choose **ECDSA P-256 + SHA256**. Save the secret file securely — it cannot be re-downloaded. |
| Account role | At minimum **Server Administrator** for the target org(s), or any role with **Update** on `compute.Blade` and `compute.RackUnit` plus **Read** on `server.Profile` and `organization.Organization`. **Read Only** roles will return 403 on the update calls. | A 403 mid-run on a specific server is logged as Failed; the rest of the batch continues. |
| Network | Outbound HTTPS 443 to `intersight.com` (or your appliance FQDN) | Verify with `Test-NetConnection intersight.com -Port 443`. |
| Optional | `PSScriptAnalyzer` | For local linting: `Install-PSResource PSScriptAnalyzer -Scope CurrentUser -TrustRepository`. |

## Setup

1. **Install the SDK** (once per machine) using the modern Microsoft PSResourceGet installer:

   ```powershell
   Install-PSResource Intersight.PowerShell -Scope CurrentUser -TrustRepository
   ```

   `Install-PSResource` avoids the legacy Authenticode certificate-revocation check that fails on many corporate-locked machines (proxy, EDR, blocked CRL endpoints).

   **If `Install-PSResource` is not recognized** (PowerShell 7 builds older than 7.4 do not ship PSResourceGet), install it first and retry:

   ```powershell
   Install-Module Microsoft.PowerShell.PSResourceGet -Scope CurrentUser -Force -AllowClobber
   Install-PSResource Intersight.PowerShell -Scope CurrentUser -TrustRepository
   ```

   **Classic alternative** (only if PSResourceGet cannot be installed): `Install-Module Intersight.PowerShell -Scope CurrentUser`. Often fails with `InvalidAuthenticodeSignature` on corporate-locked machines — see the troubleshooting table below.

2. **Generate an Intersight API key** in the UI (**Settings -> API Keys -> Generate API Key**, ECDSA P-256 + SHA256). Save the secret PEM somewhere safe:
   - Store outside source control (the file is a credential).
   - On Windows, restrict ACLs to your user account only.
   - On macOS / Linux, set `chmod 600` on the PEM.

3. **Verify connectivity** (no changes made):

   ```powershell
   Import-Module Intersight.PowerShell
   Set-IntersightConfiguration `
       -BasePath        'https://intersight.com' `
       -ApiKeyId        '<paste-your-key-id>' `
       -ApiKeyFilePath  '<path-to-secret.pem>'
   Get-IntersightOrganizationOrganization | Select-Object Name, Moid
   ```

## Usage

> **Always run with `-WhatIf` first.** It shows exactly which servers would be updated and what their new UserLabel would be, without making any change.

```powershell
# 1. Dry run - all orgs - planned changes only
./sync-server-user-labels-from-profile.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>' `
    -WhatIf
```

```powershell
# 2. Real run - all orgs
./sync-server-user-labels-from-profile.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>'
```

```powershell
# 3. Real run scoped to one organization
./sync-server-user-labels-from-profile.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>' `
    -Organization     'engineering'
```

```powershell
# 4. Intersight Appliance
./sync-server-user-labels-from-profile.ps1 `
    -ApiKeyId         '<your key id>' `
    -ApiKeySecretPath '<path-to-secret.pem>' `
    -ApiEndpoint      'https://intersight.example.com'
```

## What this script changes

- **MO types touched:** `compute.Blade` and `compute.RackUnit` (one or the other per server depending on form factor).
- **Field it sets:** `UserLabel` only. Nothing else on the server, profile, or any policy is modified.
- **Direction:** one-way, profile -> server. The script never modifies the Server Profile.

## Behavior, in order

1. Connect to Intersight with the supplied API key.
2. If `-Organization` was passed, look it up and filter all subsequent queries to that org. Otherwise process every org the API key can see.
3. Fetch every `compute.Blade` and `compute.RackUnit` in scope into an in-memory index keyed by Moid (one round trip per type, regardless of profile count).
4. Fetch every `server.Profile` in scope.
5. For each profile that has an `AssignedServer`:
   - Look up the server in the in-memory index.
   - Compare the server's current `UserLabel` to the profile's `Name`.
   - If they match exactly (case-sensitive), log `SKIPPEDINSYNC` and move on.
   - If they differ, set the server's `UserLabel` to the profile's `Name` (subject to the 64-char `-MaxLabelLength` cap; longer names are truncated with a warning).
6. Any server that was not the AssignedServer of any profile is logged once as `SKIPPEDNOPROFILE` and left untouched.
7. Print a counts summary and exit `0` if all OK, `1` if any item logged as `FAILED`.

## Idempotency / re-run

Re-running is safe and cheap:

- Servers already in sync are detected via in-memory comparison; no API write is issued.
- Servers without a profile are left alone forever.
- A profile rename later just gets caught on the next run.

You can also run it on a schedule (Task Scheduler, cron, an automation runner) — it's read-mostly until something drifts.

## Rollback

There is no automatic rollback — the script doesn't keep a backup of pre-change `UserLabel` values. Options before the first real run:

- Run with `-WhatIf` and **save the output** as a text record of every change that would occur:

  ```powershell
  ./sync-server-user-labels-from-profile.ps1 -ApiKeyId '<id>' -ApiKeySecretPath '<pem>' -WhatIf *>&1 |
      Tee-Object ./pre-change-plan.txt
  ```

- Export the current UserLabel state for a quick backup you can restore from:

  ```powershell
  (Get-IntersightComputeBlade) + (Get-IntersightComputeRackUnit) |
      Select-Object Moid, ObjectType, Name, Serial, UserLabel |
      Export-Csv ./userlabel-backup.csv -NoTypeInformation
  ```

  To restore, use the companion [`restore-server-user-labels-from-csv`](../restore-server-user-labels-from-csv/README.md) script.

## Edge cases and notes

- **Profile name > 64 characters:** UserLabel is capped (default 64). The script truncates and prints a `Write-Warning`. Lower the cap via `-MaxLabelLength` if your site enforces a tighter convention.
- **Servers without a profile:** logged once as `SKIPPEDNOPROFILE`. The script does NOT clear or modify their labels.
- **Multiple profiles claiming the same server:** Intersight permits only one assigned server per profile and one profile per server at a time, so this is not expected; if it occurs, last profile processed wins, and the prior update is overwritten silently.
- **Mixed form factors:** handled. Blades and rack units are dispatched to the appropriate setter cmdlet by `ObjectType`.
- **HX / UCSX / standalone:** any server that surfaces as `compute.Blade` or `compute.RackUnit` is in scope. Other compute types (e.g. `compute.PhysicalSummary` virtual rows) are not directly settable and are not enumerated.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Install-Module` fails with `InvalidAuthenticodeSignature` for `Intersight.PowerShell.psd1` | Legacy PowerShellGet (used by `Install-Module`) tries to verify the signing certificate's revocation status against an external Microsoft CRL/OCSP endpoint. On corporate-locked Windows this lookup is commonly blocked by proxy / EDR / TLS interception. The certificate itself is valid; the validator simply can't confirm it. | Use the modern installer instead: `Install-PSResource Intersight.PowerShell -Scope CurrentUser -TrustRepository`. If `Install-PSResource` is not recognized, install it first: `Install-Module Microsoft.PowerShell.PSResourceGet -Scope CurrentUser -Force -AllowClobber`, then re-run the `Install-PSResource` line. |
| `401 Unauthorized` / `Signature verification failed` | Wrong `ApiKeyId`, wrong PEM, or key revoked | Re-check Key ID in UI; regenerate the key pair if needed and rerun. |
| `403 Forbidden` on a specific server update (logged as FAILED, others succeed) | API key's role lacks Update on `compute.Blade` / `compute.RackUnit` in that org | Use **Server Administrator** or higher for the affected org and rerun; the script is idempotent. |
| `404 Not Found` for the organization | `-Organization` name typo, or key belongs to a different account | `Get-IntersightOrganizationOrganization | Select-Object Name` and copy the exact name. |
| `The term 'Set-IntersightConfiguration' is not recognized` | Module not installed, or running in Windows PowerShell 5.1 | Open **`pwsh` 7.x** (not the blue Windows PowerShell 5.1 window) and run `Install-PSResource Intersight.PowerShell -Scope CurrentUser -TrustRepository`. |
| Long hang, then network error | Corporate proxy / VPN required | Verify outbound HTTPS 443 reachability with `Test-NetConnection intersight.com -Port 443`. |
| Profile shows `AssignedServer Moid not in fetched server list (different org or permission?)` | The profile is assigned to a server in an org your key cannot see (cross-org scenario, rare) | Run unscoped (omit `-Organization`) with a key that has visibility across the relevant orgs. |
| All servers logged as SKIPPEDNOPROFILE | Either there really are no Server Profiles in scope, or the wrong org is selected | Check the profile count line near the top of the output; widen scope or pick the right org. |

## Sample output

```
Scoping to organization 'engineering' (Moid 60a...)
Fetching servers...
Found 42 server(s).
Fetching server profiles...
Found 35 server profile(s).
[2026-06-12 16:01:11Z] SKIPPEDINSYNC      server 'rack-12-srv-03' (serial=FCH2345...) moid=64b... msg=UserLabel already 'web-prod-03'
[2026-06-12 16:01:11Z] UPDATED            server 'rack-12-srv-04' (serial=FCH2347...) moid=64c... msg=Set UserLabel = 'web-prod-04' (was '')
[2026-06-12 16:01:12Z] SKIPPEDNOPROFILE   server 'rack-99-spare-01' (serial=FCH9911...) moid=64d... msg=no Server Profile assigned
...
----- Summary -----
  Updated            17
  SkippedInSync      18
  SkippedNoProfile   7
  SkippedWhatIf      0
  Failed             0
-------------------
```

## See also

- [`restore-server-user-labels-from-csv`](../restore-server-user-labels-from-csv/README.md) — the reverse direction. Capture a backup with the one-liner in the **Rollback** section above, then use that script to roll back any label change made here.

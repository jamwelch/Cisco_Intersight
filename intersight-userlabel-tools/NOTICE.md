# Notice — read before running in production

## Support model

This package is provided **as-is, with no warranty and no formal support contract**. In particular:

- **It is not a Cisco product** and is not supported by Cisco TAC. You cannot open a Cisco Service Request against these scripts.
- It is built on top of the public, officially Cisco-supported [`Intersight.PowerShell`](https://www.powershellgallery.com/packages/Intersight.PowerShell) SDK — but the scripts wrapping that SDK are this package's responsibility, not Cisco's.
- Issues with the SDK itself (e.g. cmdlet behavior, schema changes) can be filed via Cisco DevNet channels for the Intersight SDK. Issues with these wrapper scripts should be directed to the party who provided this package to you.
- See [`LICENSE`](./LICENSE) for the full no-warranty / liability disclaimer (BSD-2-Clause).

## What the scripts will and will not change

These scripts only set the `UserLabel` field on `compute.Blade` and `compute.RackUnit` objects in your Intersight account. They do **not**:

- Delete, decommission, unbind, or reassign any server, profile, or policy.
- Modify any Server Profile, Server Profile Template, or any policy.
- Read or transmit credentials, customer data, or telemetry anywhere outside your own Intersight account.
- Make any change without your explicit invocation (no scheduled runs are installed by the package).

## Recommended pre-flight

Before running anything in this package against a production Intersight account:

1. **Read both per-script READMEs** end to end. The "What this script changes", "Idempotency", and "Edge cases" sections are short and important.
2. **Take a UserLabel backup** using the one-liner in the top-level [`README.md`](./README.md#quick-start). The companion `restore-server-user-labels-from-csv` script can replay this CSV to roll back at any time.
3. **Always dry-run first** with `-WhatIf`. Both scripts print exactly what they would change without making any change.
4. **Use an API key with appropriate scope.** A key with **Server Administrator** on a single target organization is the principle-of-least-privilege choice for these scripts. Avoid using an Account Administrator key just to run a label sync.
5. **Test in a non-production org first** if your environment has one.

## Privacy and data handling

- The scripts authenticate using HTTP signature auth (Cisco's standard Intersight auth scheme) and talk **only** to the Intersight endpoint you pass via `-ApiEndpoint` (default `https://intersight.com`).
- No analytics, telemetry, or "phone home" calls are made.
- Your API key secret PEM file is read locally and passed to the SDK only. It is never logged or written elsewhere by these scripts. **You** are responsible for storing the PEM securely (outside source control, with restrictive file permissions).
- Server names, serial numbers, and Moids may appear in console output and any log file you choose to capture. Treat console captures and any CSV backup as containing inventory information about your environment.

## Modifying the scripts

The BSD-2-Clause license permits modification and redistribution. If you fork or adapt the scripts, please:

- Keep the `LICENSE` file with the original copyright line (add your own line below it).
- Update this `NOTICE.md` and the per-script `README.md` files to reflect your changes if you redistribute.
- Be especially careful when adding any code that **deletes** or **replaces** Intersight objects — the existing scripts are deliberately limited to a single field update for safety.

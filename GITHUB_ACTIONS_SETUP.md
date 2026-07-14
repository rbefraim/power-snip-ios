# Ship to TestFlight without owning a Mac

GitHub gives you a real macOS machine for free (GitHub-hosted `macos-14` runner).
The workflow in `.github/workflows/ios-testflight.yml` builds, signs and uploads
Power Snip! to TestFlight on that machine. You never touch Xcode.

## What Ronen must do (once)

1. Create a GitHub account (if needed) and a repo, e.g. `power-snip`.
   Push the contents of this `power-snip-app` folder to it.

2. In the repo: **Settings → Secrets and variables → Actions → New repository secret.**
   Add these FOUR secrets:

   | Secret name         | Value                                                              |
   |---------------------|--------------------------------------------------------------------|
   | `ASC_KEY_ID`        | `4G45T6S6Z3`                                                       |
   | `ASC_ISSUER_ID`     | `f1e6baad-c3e7-43c8-9ab3-aaf7dae1ad54`                             |
   | `ASC_KEY_P8_BASE64` | the base64 of `AuthKey_4G45T6S6Z3.p8` (see below)                  |
   | `APPLE_TEAM_ID`     | your 10-char Team ID from developer.apple.com → Membership          |

   To get `ASC_KEY_P8_BASE64`, run this in PowerShell and paste the output:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Downloads\AuthKey_4G45T6S6Z3.p8"))
   ```
   (Base64 so the key survives as a single-line secret. GitHub encrypts secrets and
   masks them in logs. Never commit the .p8 file itself.)

3. **Actions** tab → **iOS → TestFlight** → **Run workflow**.

That's it. ~15 minutes later the build appears in App Store Connect → TestFlight.

## The one thing GitHub cannot give you
An **active Apple Developer Program membership ($99/yr)**. Apple will reject the
upload without it. That is a payment only Ronen can make: https://developer.apple.com/programs/

## Notes
- Signing is fully automatic (`-allowProvisioningUpdates` + the API key): Xcode creates
  the distribution certificate and provisioning profile on the runner. No cert export.
- The `.ipa` is also saved as a downloadable build artifact even if the upload step fails,
  so a failed Apple membership check doesn't lose the build.
- Free minutes: unlimited on public repos; private repos get a monthly allowance
  (macOS minutes bill at a higher multiplier — a public repo is simplest).

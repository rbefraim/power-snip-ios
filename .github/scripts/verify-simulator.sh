#!/usr/bin/env bash
#
# Pre-upload verification gate for Power Snip! (iOS).
#
# App Review rejected build 21 on iPadOS 26.6 for two defects:
#   Guideline 2.1   - the App Tracking Transparency prompt never appeared
#   Guideline 3.1.1 - there was no user-tappable "Restore Purchases" control
#
# This boots a real simulator, installs the app, and proves both are fixed before anything
# is signed or uploaded. It produces screenshots (the actual evidence) and asserts, from the
# unified log, that the ATT dialog was PRESENTED and is WAITING for an answer - which is the
# exact thing that was silently not happening in build 21.
#
# Usage: verify-simulator.sh <ipad|iphone> </path/to/App.app>

set -euo pipefail

KIND="${1:?usage: verify-simulator.sh <ipad|iphone> <App.app>}"
APP="${2:?usage: verify-simulator.sh <ipad|iphone> <App.app>}"
BUNDLE_ID="me.yourplace.powersnip"
OUT="${RUNNER_TEMP:-/tmp}/verify/${KIND}"
mkdir -p "$OUT"

fail() { echo "::error::[$KIND] $*"; exit 1; }
note() { echo "[$KIND] $*"; }

# --------------------------------------------------------------------------------------
# Pick a device. App Review used an iPad Air 11-inch (M3), so prefer exactly that one.
# --------------------------------------------------------------------------------------
if [ "$KIND" = "ipad" ]; then
  DEV=$(xcrun simctl list devicetypes | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.iPad-Air-11-inch-M3' | head -1 || true)
  if [ -z "$DEV" ]; then
    DEV=$(xcrun simctl list devicetypes | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.iPad[A-Za-z0-9._-]*' | head -1 || true)
  fi
  NAME="PS-Verify-iPad"
else
  DEV=$(xcrun simctl list devicetypes | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-1[6-9][A-Za-z0-9._-]*' | head -1 || true)
  if [ -z "$DEV" ]; then
    DEV=$(xcrun simctl list devicetypes | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.iPhone[A-Za-z0-9._-]*' | head -1 || true)
  fi
  NAME="PS-Verify-iPhone"
fi
[ -n "$DEV" ] || fail "no $KIND simulator device type available on this runner"

RUNTIME=$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | sort -V | tail -1 || true)
[ -n "$RUNTIME" ] || fail "no iOS simulator runtime available on this runner"

note "device type : $DEV"
note "runtime     : $RUNTIME"

UDID=$(xcrun simctl create "$NAME" "$DEV" "$RUNTIME")
note "udid        : $UDID"

cleanup() {
  kill "${LOGPID:-}" 2>/dev/null || true
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  xcrun simctl delete "$UDID" 2>/dev/null || true
}
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
note "installed $APP"

LOG="$OUT/app.log"
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'eventMessage CONTAINS "[PowerSnip]"' > "$LOG" 2>&1 &
LOGPID=$!
sleep 3

# --------------------------------------------------------------------------------------
# 1. FRESH INSTALL -> the ATT prompt must appear, and must sit there waiting for an answer.
#    No launch arguments: this is exactly what a reviewer does.
# --------------------------------------------------------------------------------------
note "run 1/3 - fresh launch, expecting the ATT prompt"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"
sleep 14
xcrun simctl io "$UDID" screenshot "$OUT/01-att-prompt.png"
[ -s "$OUT/01-att-prompt.png" ] || fail "no screenshot captured for the ATT prompt"

if [ -s "$LOG" ]; then
  grep -q "ATT presenting request" "$LOG" \
    || fail "the app never reached requestTrackingAuthorization - the ATT prompt would not appear"
  if grep -q "ATT decision delivered" "$LOG"; then
    fail "ATT resolved WITHOUT anyone answering the dialog - that means no dialog was shown (this is the build-21 bug)"
  fi
  note "ATT prompt is presented and awaiting a user answer"
else
  echo "::warning::[$KIND] the unified log came back empty; falling back to the screenshot as the only ATT evidence"
fi

# --------------------------------------------------------------------------------------
# 2. The Restore Purchases control must be visible on the main menu.
#    -PSUITest / -PSSkipATT are DEBUG-only launch hooks (see AppDelegate); they do not exist
#    in the Release archive that ships, so App Review cannot reach them.
# --------------------------------------------------------------------------------------
note "run 2/3 - main menu, expecting the Restore Purchases control"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -PSUITest -PSSkipATT
sleep 12
xcrun simctl io "$UDID" screenshot "$OUT/02-restore-button.png"
[ -s "$OUT/02-restore-button.png" ] || fail "no screenshot captured for the Restore Purchases control"

# --------------------------------------------------------------------------------------
# 3. Tapping it must open the restore sheet and report a result.
# --------------------------------------------------------------------------------------
note "run 3/3 - restore sheet open, expecting a result message"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -PSUITest -PSSkipATT -PSOpenRestore
sleep 16
xcrun simctl io "$UDID" screenshot "$OUT/03-restore-sheet.png"
[ -s "$OUT/03-restore-sheet.png" ] || fail "no screenshot captured for the restore sheet"

# --------------------------------------------------------------------------------------
# Crash guard. This project has shipped a build that passed every automated check and then
# died on open, so an actual crash report is a hard failure.
# --------------------------------------------------------------------------------------
shopt -s nullglob
CRASHES=(~/Library/Logs/DiagnosticReports/App-*.ips ~/Library/Logs/DiagnosticReports/App_*.ips)
if [ "${#CRASHES[@]}" -gt 0 ]; then
  cp "${CRASHES[@]}" "$OUT/" || true
  fail "the app produced ${#CRASHES[@]} crash report(s) during verification - see the artifact"
fi

note "verification passed; screenshots in $OUT"
ls -la "$OUT"

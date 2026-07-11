#!/usr/bin/env bash
# Install NOOP (iPhone + embedded Apple Watch app) to a paired device over USB.
# Requires: Xcode, xcodegen, local signing via Tools/apply-local-signing.sh, iPhone unlocked.
#
# Usage:
#   ./Tools/apply-local-signing.sh && ./Tools/install-noop-ios-watch.sh
#   IPHONE_UDID=... WATCH_UDID=... BUNDLE_ID=... ./Tools/install-noop-ios-watch.sh
#
# Device UDIDs / bundle id: set in signing.local.env (gitignored) or export in the shell.
# Never hard-code personal Team / UDID / bundle ids in this script.
#
# Watch install notes:
# - Direct Mac→Watch install needs Developer Mode ON the watch
#   (Watch: Settings → Privacy & Security → Developer Mode → On, then reboot).
# - Without Developer Mode, install from the iPhone Watch app: Watch → NOOP → Install.
# - Or Xcode → scheme NOOPiOS → Run (⌘R) with the iPhone selected (companion rides along).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Optional local env (gitignored).
if [[ -f "$ROOT/signing.local.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/signing.local.env"
fi

IPHONE_UDID="${IPHONE_UDID:?set IPHONE_UDID in the environment or signing.local.env}"
WATCH_UDID="${WATCH_UDID:?set WATCH_UDID in the environment or signing.local.env}"
if [[ -n "${BUNDLE_PREFIX:-}" ]]; then
  BUNDLE_ID="${BUNDLE_ID:-${BUNDLE_PREFIX}.noop}"
else
  BUNDLE_ID="${BUNDLE_ID:?set BUNDLE_ID or BUNDLE_PREFIX in signing.local.env}"
fi

echo "→ xcodegen generate"
xcodegen generate

echo "→ xcodebuild NOOPiOS (Debug, device ${IPHONE_UDID})"
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS \
  -destination "id=${IPHONE_UDID}" \
  -allowProvisioningUpdates \
  -configuration Debug \
  build

APP="$(find ~/Library/Developer/Xcode/DerivedData/Strand-*/Build/Products/Debug-iphoneos -maxdepth 1 -name 'NOOP*.app' | head -1)"
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "ERROR: built .app not found under DerivedData/Strand-*" >&2
  exit 1
fi

echo "→ install iPhone app: ${APP}"
xcrun devicectl device install app --device "${IPHONE_UDID}" "${APP}"

WATCH_APP="${APP}/Watch/NOOPWatch.app"
if [[ -d "${WATCH_APP}" ]]; then
  echo "→ embedded watch app found: ${WATCH_APP}"
  if xcrun devicectl device install app --device "${WATCH_UDID}" "${WATCH_APP}" 2>/dev/null; then
    echo "✓ Watch app installed directly."
  else
    echo "⚠ Direct watch install failed (pair the watch in Xcode Devices window, then Run once)."
    echo "  Fallback: iPhone → Watch app → NOOP → Install"
  fi
else
  echo "ERROR: no Watch/NOOPWatch.app inside the iPhone bundle." >&2
  exit 1
fi

echo "→ launch ${BUNDLE_ID} on iPhone (triggers watch sync)"
xcrun devicectl device process launch --device "${IPHONE_UDID}" "${BUNDLE_ID}" || true

echo ""
echo "Done. Open NOOP on the iPhone, then check the NOOP icon on the Apple Watch."
echo "Charge complication: long-press face → Edit → add NOOP."

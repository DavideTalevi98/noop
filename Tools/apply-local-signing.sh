#!/usr/bin/env bash
# Apply personal Apple signing from signing.local.env (gitignored) into project.yml.
# Does NOT commit anything. Re-run after git checkout / pull that resets project.yml.
#
# Usage:
#   cp Tools/signing.local.env.example signing.local.env   # once
#   ./Tools/apply-local-signing.sh
#   xcodegen generate
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${SIGNING_ENV:-$ROOT/signing.local.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  echo "Copy Tools/signing.local.env.example → signing.local.env and fill in your Team / bundle ids." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM in signing.local.env}"
: "${BUNDLE_PREFIX:?set BUNDLE_PREFIX in signing.local.env}"
: "${APP_GROUP_ID:?set APP_GROUP_ID in signing.local.env}"

BUNDLE_ID="${BUNDLE_PREFIX}.noop"
YML="$ROOT/project.yml"

# Always start from the public placeholders so re-runs are idempotent.
git checkout -- project.yml NOOPWatch/Info.plist StrandiOS/Resources/Info.plist 2>/dev/null || true

# Patch project.yml (public defaults → local).
perl -i -pe "
  s/^(\\s*DEVELOPMENT_TEAM:\\s*)\"\"/\$1\"${DEVELOPMENT_TEAM}\"/;
  s/^(\\s*APP_GROUP_ID:\\s*)group\\.com\\.noopapp\\.noop\\.staging/\$1${APP_GROUP_ID}/;
  s/^(\\s*PRODUCT_BUNDLE_IDENTIFIER:\\s*)com\\.noopapp\\.noop\\.widgets/\$1${BUNDLE_ID}.widgets/;
  s/^(\\s*PRODUCT_BUNDLE_IDENTIFIER:\\s*)com\\.noopapp\\.noop\\.watch\\.complications/\$1${BUNDLE_ID}.watch.complications/;
  s/^(\\s*PRODUCT_BUNDLE_IDENTIFIER:\\s*)com\\.noopapp\\.noop\\.watch/\$1${BUNDLE_ID}.watch/;
  s/^(\\s*PRODUCT_BUNDLE_IDENTIFIER:\\s*)com\\.noopapp\\.noop\$/\$1${BUNDLE_ID}/;
  s/^(\\s*WKCompanionAppBundleIdentifier:\\s*)com\\.noopapp\\.noop/\$1${BUNDLE_ID}/;
  s/^(\\s*-\\s*)com\\.noopapp\\.noop\\.debugexport/\$1${BUNDLE_ID}.debugexport/;
" "$YML"

# Info.plist companions (source files that mirror the public defaults).
perl -i -0pe "s/(WKCompanionAppBundleIdentifier<\\/key>\\s*<string>)com\\.noopapp\\.noop/\$1${BUNDLE_ID}/" \
  "$ROOT/NOOPWatch/Info.plist"
perl -i -0pe "s/(BGTaskSchedulerPermittedIdentifiers<\\/key>\\s*<array>\\s*<string>)com\\.noopapp\\.noop\\.debugexport/\$1${BUNDLE_ID}.debugexport/" \
  "$ROOT/StrandiOS/Resources/Info.plist"

echo "✓ Applied local signing → project.yml (+ Info.plist companions)"
echo "  TEAM=${DEVELOPMENT_TEAM}  BUNDLE=${BUNDLE_ID}  GROUP=${APP_GROUP_ID}"
echo "  Next: xcodegen generate"
echo "  Before commit: git checkout -- project.yml NOOPWatch/Info.plist StrandiOS/Resources/Info.plist"

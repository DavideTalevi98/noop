#!/usr/bin/env bash
# Local pre-PR gate: Swift packages, Android unit tests, macOS app compile.
# iOS (NOOPiOS) needs the iOS 26 SDK — run app-build.yml on macos-26 or xcodebuild locally.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Swift packages =="
for pkg in WhoopProtocol OuraProtocol WhoopStore StrandAnalytics StrandImport StrandDesign NoopLocalAccess; do
  echo "-- $pkg --"
  (cd "Packages/$pkg" && swift test)
done

echo "== Android unit tests =="
(cd android && ./gradlew testFullDebugUnitTest)

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodebuild >/dev/null; then
  echo "== macOS app (compile-only) =="
  if command -v xcodegen >/dev/null; then
    xcodegen generate
  else
    echo "xcodegen not found — skipping (install with: brew install xcodegen)" >&2
    exit 1
  fi
  xcodebuild -project Strand.xcodeproj -scheme Strand \
    -destination 'platform=macOS' \
    ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    build
else
  echo "== macOS app: skipped (needs macOS + Xcode) =="
fi

echo "All local checks passed."

#!/usr/bin/env bash
# Capture the README / website screenshots from the real app, running the
# offline sample mailbox (PUM_DEMO=1, see PowerUserMail/Services/DemoMailService.swift).
#
# usage: scripts/screenshots.sh [out-dir]        (default: docs/screenshots)
#
# Needs Xcode and cwebp (`brew install webp`). It never clicks, types or records the
# screen: PUM_DEMO_* variables pick the view and the app draws its own window into a
# PNG (PUM_DEMO_CAPTURE), so it works on a busy or even locked Mac.
# The capture build is com.isaaclins.PowerUserMail.screenshots without the sandbox
# (so it can write the PNG where you ask); it keeps all mail, accounts and settings in
# memory and never touches your real accounts, keychain or mail cache.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs/screenshots}"
BUILD=build/screenshots
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

echo "[screenshots] building"
xcodebuild -project PowerUserMail.xcodeproj -scheme PowerUserMail -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$BUILD" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO \
    PRODUCT_BUNDLE_IDENTIFIER=com.isaaclins.PowerUserMail.screenshots \
    build -quiet
APP="$BUILD/Build/Products/Debug/PowerUserMail.app/Contents/MacOS/PowerUserMail"

# shot <name> <dark|light> [VAR=value ...]: open the app in that state and let it draw itself
shot() {
    local name=$1 theme=$2 pid
    shift 2
    rm -f "$OUT/$name.png"
    env PUM_DEMO=1 PUM_DEMO_THEME="$theme" PUM_DEMO_CAPTURE="$OUT/$name.png" \
        SWIFT_DETERMINISTIC_HASHING=1 "$@" "$APP" >/dev/null 2>&1 &
    pid=$!
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill "$pid" 2>/dev/null || true
    [ -f "$OUT/$name.png" ] || { echo "could not capture $name" >&2; exit 1; }
    cwebp -quiet -q 88 "$OUT/$name.png" -o "$OUT/$name.webp"
    echo "[screenshots] $OUT/$name.webp"
}

for THEME in dark light; do
    shot "inbox-$THEME" "$THEME" PUM_DEMO_FILTER=all PUM_DEMO_OPEN=Lena
    shot "palette-$THEME" "$THEME" PUM_DEMO_FILTER=all PUM_DEMO_OPEN=Lena PUM_DEMO_PALETTE=1
done

#!/bin/zsh
# Builds build.noindex/WizBar.app (".noindex" keeps Spotlight from listing a second copy).
#   ./build.sh              native architecture
#   ./build.sh --universal  Apple Silicon + Intel
#   ./build.sh --install    also copy to /Applications and relaunch
# Signs with $SIGN_IDENTITY, else the first code-signing identity in the keychain,
# else ad-hoc (macOS may then re-ask for Local Network access after each rebuild).
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    --install) INSTALL=true ;;
  esac
done

swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR=$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)

APP=build.noindex/WizBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/WizBar" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# Compile the Icon Composer icon (Liquid Glass Assets.car + AppIcon.icns fallback).
mkdir -p "$APP/Contents/Resources"
xcrun actool Icon/AppIcon.icon --compile "$APP/Contents/Resources" \
  --platform macosx --target-device mac --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist "$(mktemp -d)/icon.plist" \
  --errors --warnings --output-format human-readable-text >/dev/null

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1 {print $2}')}
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/WizBar"), signed: ${IDENTITY:-ad-hoc})"

if $INSTALL; then
  pkill -x WizBar 2>/dev/null || true
  rm -rf /Applications/WizBar.app
  cp -R "$APP" /Applications/
  open /Applications/WizBar.app
  echo "Installed to /Applications/WizBar.app"
fi

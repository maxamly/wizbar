#!/bin/zsh
# Builds WizBar.app.
#   ./build.sh              native architecture
#   ./build.sh --universal  Apple Silicon + Intel
# Signs with $SIGN_IDENTITY, else the first code-signing identity in the keychain,
# else ad-hoc (macOS may then re-ask for Local Network access after each rebuild).
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
[[ "${1:-}" == "--universal" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR=$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)

APP=WizBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/WizBar" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1 {print $2}')}
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/WizBar"), signed: ${IDENTITY:-ad-hoc})"

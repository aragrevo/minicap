#!/bin/zsh
# Compila MiniCap y arma MiniCap.app (firma ad-hoc).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/MiniCap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MiniCap "$APP/Contents/MacOS/MiniCap"
cp Info.plist "$APP/Contents/Info.plist"
strip -x "$APP/Contents/MacOS/MiniCap"
codesign --force --sign - "$APP"
echo "Listo: $APP"

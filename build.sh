#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Floating Notes"
BIN_NAME="FloatingNotes"
APP_DIR="build/${APP_NAME}.app"

npm --prefix "editor-web" ci --silent
npm --prefix "editor-web" run build
swift build -c release

rm -rf "build"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "Info.plist" "${APP_DIR}/Contents/Info.plist"
cp ".build/release/${BIN_NAME}" "${APP_DIR}/Contents/MacOS/${BIN_NAME}"
cp -R "Sources/FloatingNotes/Resources/Editor" "${APP_DIR}/Contents/Resources/Editor"

codesign --force --deep --sign - "${APP_DIR}"

echo "Built ${APP_DIR}"

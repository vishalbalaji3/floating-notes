#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Floating Notes"
BIN_NAME="FloatingNotes"
APP_DIR="build/${APP_NAME}.app"
APP_VERSION="${APP_VERSION:-$(plutil -extract CFBundleShortVersionString raw Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-${APP_VERSION}}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

npm --prefix "editor-web" ci --silent
npm --prefix "editor-web" run build
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "build"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Frameworks"
cp "Info.plist" "${APP_DIR}/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${APP_VERSION}" "${APP_DIR}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${APP_DIR}/Contents/Info.plist"
cp "${BIN_DIR}/${BIN_NAME}" "${APP_DIR}/Contents/MacOS/${BIN_NAME}"
cp -R "Sources/FloatingNotes/Resources/Editor" "${APP_DIR}/Contents/Resources/Editor"
ditto "${BIN_DIR}/Sparkle.framework" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"

if [[ "${CODE_SIGN_IDENTITY}" == "-" ]]; then
    codesign --force --deep --sign - "${APP_DIR}"
else
    codesign --force --deep --options runtime --timestamp --sign "${CODE_SIGN_IDENTITY}" "${APP_DIR}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Built ${APP_DIR} (version ${APP_VERSION}, build ${BUILD_NUMBER})"

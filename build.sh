#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Floating Notes"
BIN_NAME="FloatingNotes"
APP_DIR="build/${APP_NAME}.app"
APP_VERSION="${APP_VERSION:-$(plutil -extract CFBundleShortVersionString raw Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-${APP_VERSION}}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ICON_SOURCE_DIR="Assets/AppIcons"
ICON_BUILD_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${ICON_BUILD_DIR}"
}
trap cleanup EXIT

make_icns() {
    local source="$1"
    local destination="$2"
    local icon_name
    icon_name="$(basename "${destination}" .icns)"
    local iconset="${ICON_BUILD_DIR}/${icon_name}.iconset"
    mkdir -p "${iconset}"

    while read -r filename pixels; do
        sips -z "${pixels}" "${pixels}" "${source}" --out "${iconset}/${filename}" >/dev/null
    done <<EOF
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
EOF

    iconutil --convert icns "${iconset}" --output "${destination}"
}

npm --prefix "editor-web" ci --silent
npm --prefix "editor-web" run build
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "build"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Frameworks"
make_icns "${ICON_SOURCE_DIR}/Monogram.png" "${APP_DIR}/Contents/Resources/AppIcon.icns"
make_icns "${ICON_SOURCE_DIR}/Notes.png" "${APP_DIR}/Contents/Resources/AppIconNotes.icns"
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

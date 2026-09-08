#!/bin/bash

# 用法: .github/scripts/build-dmg.sh <版本號>

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="${PROJECT_DIR}/.github/scripts"
PROJECT_FILE="${PROJECT_DIR}/XIV on Mac in TC.xcodeproj"
SCHEME="XIV on Mac"
APP_NAME="XIV on Mac in TC.app"
OUTPUT_DIR="${PROJECT_DIR}/Release"
BUILD_DIR="${OUTPUT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/build/DerivedData}"
VERSION="${1:?用法: $0 <版本號>}"
DMG_PATH="${OUTPUT_DIR}/XIV-on-Mac-in-TC-${VERSION}.dmg"

die() { echo "錯誤: $1" >&2; exit 1; }

for command in xcodebuild create-dmg codesign /usr/libexec/PlistBuddy; do
    command -v "$command" >/dev/null 2>&1 || die "找不到 ${command}"
done

rm -rf "$BUILD_DIR"
rm -f "$DMG_PATH"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

build_args=(
    archive
    -project "$PROJECT_FILE"
    -scheme "$SCHEME"
    -configuration Release
    -archivePath "$ARCHIVE_PATH"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -destination generic/platform=macOS
    -packageAuthorizationProvider netrc
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=Developer ID Application"
)
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    build_args+=("DEVELOPMENT_TEAM=${APPLE_TEAM_ID}")
fi
DOTNET_PATH="${DOTNET_PATH:-$(command -v dotnet || true)}"
[[ -n "$DOTNET_PATH" ]] || die "找不到 dotnet；請設定 DOTNET_PATH"
export DOTNET_PATH
xcodebuild "${build_args[@]}"

export_options="${BUILD_DIR}/ExportOptions.plist"
cat >"$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <key>destination</key><string>export</string>
EOF
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    cat >>"$export_options" <<EOF
    <key>teamID</key><string>${APPLE_TEAM_ID}</string>
EOF
fi
cat >>"$export_options" <<EOF
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" -exportOptionsPlist "$export_options"
[[ -d "$APP_PATH" ]] || die "App 匯出失敗"
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")
[[ "$app_version" == "$VERSION" ]] || die "App 版本 ${app_version} 與指定版本 ${VERSION} 不一致"

"${SCRIPT_DIR}/notarize.sh" "$APP_PATH"

icon_path="${PROJECT_DIR}/XIV on Mac/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
dmg_args=(
    --skip-jenkins
    --volname "XIV on Mac in TC"
    --window-pos 200 120
    --window-size 600 400
    --icon-size 100
    --icon "$APP_NAME" 150 190
    --hide-extension "$APP_NAME"
    --app-drop-link 450 190
)
[[ -f "$icon_path" ]] && dmg_args+=(--volicon "$icon_path")
create-dmg "${dmg_args[@]}" "$DMG_PATH" "$EXPORT_PATH"
codesign --force --timestamp --sign "Developer ID Application" "$DMG_PATH"
codesign --verify --verbose "$DMG_PATH"
"${SCRIPT_DIR}/notarize.sh" "$DMG_PATH"

echo "DMG: ${DMG_PATH}"
echo "App: ${APP_PATH}"

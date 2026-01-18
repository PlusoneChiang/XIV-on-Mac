#!/bin/bash

# XIV on Mac in TC - DMG Build Script
# 用法: ./scripts/build-dmg.sh [版本號]
# 範例: ./scripts/build-dmg.sh 1.0.0

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 專案設定
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="XIV on Mac in TC"
PROJECT_FILE="${PROJECT_DIR}/XIV on Mac in TC.xcodeproj"
SCHEME="XIV on Mac"
APP_NAME="XIV on Mac in TC.app"
CONFIGURATION="Release"

# 輸出目錄
OUTPUT_DIR="${PROJECT_DIR}/Release"
BUILD_DIR="${OUTPUT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"

# 版本號（從參數或 Info.plist 讀取）
if [ -n "$1" ]; then
    VERSION="$1"
else
    VERSION=$(defaults read "${PROJECT_DIR}/XIV on Mac/XIV-on-Mac-Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
fi

DMG_NAME="XIV-on-Mac-in-TC-${VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

# 函式：列印訊息
print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}警告:${NC} $1"
}

print_error() {
    echo -e "${RED}錯誤:${NC} $1"
}

# 函式：檢查必要工具
check_dependencies() {
    print_step "檢查必要工具..."

    if ! command -v xcodebuild &> /dev/null; then
        print_error "找不到 xcodebuild，請安裝 Xcode Command Line Tools"
        exit 1
    fi

    if ! command -v create-dmg &> /dev/null; then
        print_warning "找不到 create-dmg，嘗試安裝..."
        if command -v brew &> /dev/null; then
            brew install create-dmg
        else
            print_error "找不到 Homebrew，請先安裝 create-dmg: brew install create-dmg"
            exit 1
        fi
    fi

    echo "  ✓ xcodebuild 已安裝"
    echo "  ✓ create-dmg 已安裝"
}

# 函式：清理舊的建置
clean_build() {
    print_step "清理舊的建置..."

    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi

    if [ -f "$DMG_PATH" ]; then
        rm -f "$DMG_PATH"
    fi

    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$BUILD_DIR"

    echo "  ✓ 清理完成"
}

# 函式：建立 Archive
build_archive() {
    print_step "建立 Archive..."
    echo "  專案: ${PROJECT_FILE}"
    echo "  Scheme: ${SCHEME}"
    echo "  Configuration: ${CONFIGURATION}"

    xcodebuild archive \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        | grep -E "^(Archive|Signing|Compiling|Linking|Processing|warning:|error:)" || true

    if [ ! -d "$ARCHIVE_PATH" ]; then
        print_error "Archive 建立失敗"
        exit 1
    fi

    echo "  ✓ Archive 建立完成: ${ARCHIVE_PATH}"
}

# 函式：匯出 App
export_app() {
    print_step "匯出 App..."

    # 建立 ExportOptions.plist
    EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
    cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

    # 嘗試使用 xcodebuild 匯出
    if xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        2>/dev/null; then
        echo "  ✓ 使用 xcodebuild 匯出成功"
    else
        # 備援：直接從 Archive 複製
        print_warning "xcodebuild 匯出失敗，使用備援方式..."
        mkdir -p "$EXPORT_PATH"
        cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}" "$EXPORT_PATH/"
        echo "  ✓ 使用備援方式匯出成功"
    fi

    if [ ! -d "${EXPORT_PATH}/${APP_NAME}" ]; then
        print_error "App 匯出失敗"
        exit 1
    fi

    # 移除隔離屬性（避免 Gatekeeper 阻擋）
    xattr -cr "${EXPORT_PATH}/${APP_NAME}" 2>/dev/null || true

    echo "  ✓ App 匯出完成: ${EXPORT_PATH}/${APP_NAME}"
}

# 函式：建立 DMG
create_dmg_file() {
    print_step "建立 DMG..."
    echo "  版本: ${VERSION}"
    echo "  輸出: ${DMG_PATH}"

    # 尋找 App Icon
    ICON_PATH=""
    if [ -f "${PROJECT_DIR}/XIV on Mac/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" ]; then
        ICON_PATH="${PROJECT_DIR}/XIV on Mac/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
    fi

    # 建立 DMG
    DMG_ARGS=(
        --volname "XIV on Mac in TC"
        --window-pos 200 120
        --window-size 600 400
        --icon-size 100
        --icon "${APP_NAME}" 150 190
        --hide-extension "${APP_NAME}"
        --app-drop-link 450 190
    )

    if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
        DMG_ARGS+=(--volicon "$ICON_PATH")
    fi

    # 移除舊的 DMG（如果存在）
    if [ -f "$DMG_PATH" ]; then
        rm -f "$DMG_PATH"
    fi

    create-dmg "${DMG_ARGS[@]}" "$DMG_PATH" "$EXPORT_PATH"

    if [ ! -f "$DMG_PATH" ]; then
        print_error "DMG 建立失敗"
        exit 1
    fi

    echo "  ✓ DMG 建立完成: ${DMG_PATH}"
}

# 函式：Sparkle 簽名（可選）
sign_with_sparkle() {
    print_step "Sparkle 簽名..."

    # 尋找 sign_update 工具
    SIGN_UPDATE=""
    POSSIBLE_PATHS=(
        "${PROJECT_DIR}/Sparkle/bin/sign_update"
        "${HOME}/Downloads/Sparkle-2.6.0/bin/sign_update"
        "${HOME}/Sparkle/bin/sign_update"
        "/usr/local/bin/sign_update"
    )

    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -x "$path" ]; then
            SIGN_UPDATE="$path"
            break
        fi
    done

    if [ -z "$SIGN_UPDATE" ]; then
        print_warning "找不到 Sparkle sign_update 工具"
        echo "  請下載 Sparkle 並將 bin/sign_update 放到以下位置之一："
        echo "    - ${PROJECT_DIR}/Sparkle/bin/sign_update"
        echo "    - /usr/local/bin/sign_update"
        echo ""
        echo "  或手動執行: sign_update \"${DMG_PATH}\""
        return
    fi

    echo "  使用: ${SIGN_UPDATE}"

    SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH")

    echo ""
    echo "  ✓ Sparkle 簽名資訊:"
    echo "    ${SIGNATURE}"
    echo ""
    echo "  請將以上資訊加入 appcast.xml 的 <enclosure> 標籤"
}

# 函式：顯示摘要
show_summary() {
    print_step "建置完成!"
    echo ""
    echo "  輸出檔案:"
    echo "    DMG: ${DMG_PATH}"
    echo "    App: ${EXPORT_PATH}/${APP_NAME}"
    echo ""
    echo "  檔案大小:"
    if [ -f "$DMG_PATH" ]; then
        DMG_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
        echo "    DMG: ${DMG_SIZE}"
    fi
    echo ""
    echo "  下一步:"
    echo "    1. 測試 DMG 安裝"
    echo "    2. 使用 Sparkle sign_update 簽名"
    echo "    3. 上傳到 GitHub Releases"
    echo "    4. 更新 appcast.xml"
}

# 主程式
main() {
    echo ""
    echo "================================================"
    echo "  XIV on Mac in TC - DMG 建置腳本"
    echo "  版本: ${VERSION}"
    echo "================================================"
    echo ""

    check_dependencies
    clean_build
    build_archive
    export_app
    create_dmg_file
    sign_with_sparkle
    show_summary
}

# 執行主程式
main

#!/bin/bash

# XIV on Mac in TC - Sparkle 簽發與 appcast.xml 更新腳本
# 用法: ./scripts/sparkle-sign.sh [DMG路徑] [Release Notes]
# 範例: ./scripts/sparkle-sign.sh Release/XIV-on-Mac-in-TC-0.8.5.dmg "修復登入問題"
#
# 此腳本會：
#   1. 使用 Sparkle sign_update 對 DMG 進行 EdDSA 簽名
#   2. 自動更新 appcast.xml（加入新版本項目）

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 專案設定
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="${HOME}/Sparkle/bin"
SIGN_UPDATE="${SPARKLE_BIN}/sign_update"
APPCAST_FILE="${PROJECT_DIR}/appcast.xml"
GITHUB_REPO="plusonechiang/XIV-on-Mac-in-TC"
MIN_SYSTEM_VERSION="14.0"

# 函式：列印訊息
print_step() { echo -e "${GREEN}==>${NC} $1"; }
print_info() { echo -e "${CYAN}   $1${NC}"; }
print_warning() { echo -e "${YELLOW}警告:${NC} $1"; }
print_error() { echo -e "${RED}錯誤:${NC} $1"; }

# 函式：顯示使用說明
usage() {
    echo "用法: $0 [DMG路徑] [Release Notes]"
    echo ""
    echo "參數:"
    echo "  DMG路徑        DMG 檔案路徑（預設: Release/ 目錄下最新的 DMG）"
    echo "  Release Notes  更新說明（可選，互動式輸入）"
    echo ""
    echo "範例:"
    echo "  $0"
    echo "  $0 Release/XIV-on-Mac-in-TC-0.8.5.dmg"
    echo "  $0 Release/XIV-on-Mac-in-TC-0.8.5.dmg \"修復登入問題\""
    exit 1
}

# 函式：檢查前置條件
check_prerequisites() {
    print_step "檢查前置條件..."

    if [ ! -x "$SIGN_UPDATE" ]; then
        print_error "找不到 Sparkle sign_update 工具: ${SIGN_UPDATE}"
        echo "  請確認 ~/Sparkle/bin/sign_update 存在"
        exit 1
    fi
    echo "  ✓ sign_update 已找到"

    if [ ! -f "$APPCAST_FILE" ]; then
        print_error "找不到 appcast.xml: ${APPCAST_FILE}"
        exit 1
    fi
    echo "  ✓ appcast.xml 已找到"
}

# 函式：找到 DMG 檔案
resolve_dmg() {
    if [ -n "$1" ]; then
        DMG_PATH="$1"
    else
        # 自動尋找 Release/ 目錄下最新的 DMG
        DMG_PATH=$(find "${PROJECT_DIR}/Release" -maxdepth 1 -name "*.dmg" -type f -print0 2>/dev/null \
            | xargs -0 ls -t 2>/dev/null | head -1)
    fi

    if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
        print_error "找不到 DMG 檔案: ${DMG_PATH:-'Release/ 目錄下無 DMG 檔案'}"
        echo "  請先執行 ./scripts/build-dmg.sh 建置 DMG"
        exit 1
    fi

    # 轉為絕對路徑
    DMG_PATH="$(cd "$(dirname "$DMG_PATH")" && pwd)/$(basename "$DMG_PATH")"
    DMG_FILENAME="$(basename "$DMG_PATH")"
}

# 函式：從 DMG 檔名或專案設定讀取版本號
resolve_version() {
    # 嘗試從檔名解析版本號（格式: XIV-on-Mac-in-TC-X.Y.Z.dmg）
    VERSION=$(echo "$DMG_FILENAME" | sed -n 's/.*-\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\.dmg/\1/p')

    if [ -z "$VERSION" ]; then
        # 備援：從 xcodeproj 讀取
        VERSION=$(grep 'MARKETING_VERSION' "${PROJECT_DIR}/XIV on Mac in TC.xcodeproj/project.pbxproj" \
            | head -1 | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')
    fi

    if [ -z "$VERSION" ]; then
        print_error "無法判斷版本號"
        echo "  請確認 DMG 檔名格式為: XIV-on-Mac-in-TC-X.Y.Z.dmg"
        exit 1
    fi

    # 讀取 build number (CURRENT_PROJECT_VERSION)
    BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION' "${PROJECT_DIR}/XIV on Mac in TC.xcodeproj/project.pbxproj" \
        | head -1 | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')
    BUILD_NUMBER="${BUILD_NUMBER:-1}"
}

# 函式：EdDSA 簽名
sign_dmg() {
    print_step "對 DMG 進行 EdDSA 簽名..."
    print_info "檔案: ${DMG_PATH}"

    # 取得簽名（-p 只輸出簽名值）
    ED_SIGNATURE=$("$SIGN_UPDATE" -p "$DMG_PATH")

    if [ -z "$ED_SIGNATURE" ]; then
        print_error "簽名失敗"
        exit 1
    fi

    # 取得檔案大小（位元組）
    FILE_SIZE=$(stat -f%z "$DMG_PATH")

    echo "  ✓ 簽名完成"
    echo ""
    print_info "EdDSA 簽名: ${ED_SIGNATURE}"
    print_info "檔案大小:   ${FILE_SIZE} bytes"
}

# 函式：輸入 Release Notes
get_release_notes() {
    if [ -n "$1" ]; then
        RELEASE_NOTES="$1"
    else
        echo ""
        print_step "輸入 Release Notes（每行一項，輸入空行結束）:"
        RELEASE_NOTES=""
        while IFS= read -r line; do
            [ -z "$line" ] && break
            if [ -n "$RELEASE_NOTES" ]; then
                RELEASE_NOTES="${RELEASE_NOTES}\n${line}"
            else
                RELEASE_NOTES="$line"
            fi
        done
    fi

    if [ -z "$RELEASE_NOTES" ]; then
        RELEASE_NOTES="版本 ${VERSION} 更新"
    fi
}

# 函式：產生 Release Notes HTML
generate_notes_html() {
    NOTES_HTML="<h2>XIV on Mac in TC v${VERSION}</h2>"
    NOTES_HTML="${NOTES_HTML}\n                <ul>"

    # 將 release notes 轉為 HTML 列表
    echo -e "$RELEASE_NOTES" | while IFS= read -r note; do
        echo "                    <li>${note}</li>"
    done > /tmp/xomit_notes.tmp

    NOTES_LIST=$(cat /tmp/xomit_notes.tmp)
    rm -f /tmp/xomit_notes.tmp

    NOTES_HTML="${NOTES_HTML}\n${NOTES_LIST}"
    NOTES_HTML="${NOTES_HTML}\n                </ul>"
}

# 函式：產生 pubDate
generate_pub_date() {
    PUB_DATE=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')
}

# 函式：更新 appcast.xml
update_appcast() {
    print_step "更新 appcast.xml..."

    generate_notes_html
    generate_pub_date

    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${DMG_FILENAME}"

    # 建立新的 <item> 區塊
    NEW_ITEM=$(cat <<EOF
        <!-- 最新版本 -->
        <item>
            <title>XIV on Mac in TC v${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
            <description><![CDATA[
                ${NOTES_HTML}
            ]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${FILE_SIZE}"
            />
        </item>
EOF
)

    # 備份原始 appcast.xml
    cp "$APPCAST_FILE" "${APPCAST_FILE}.bak"

    # 移除舊的「最新版本」註解標記，插入新 item 到 <channel> 內第一個 <item> 之前
    # 使用 Python 處理 XML 插入（避免 sed 處理多行的問題）
    python3 << PYEOF
import re

with open("${APPCAST_FILE}", "r", encoding="utf-8") as f:
    content = f.read()

new_item = """${NEW_ITEM}

"""

# 移除舊的「最新版本」註解
content = re.sub(r'\s*<!-- 最新版本 -->\n', '\n', content)

# 在第一個 <item> 之前插入新 item
if '<item>' in content:
    content = content.replace('<item>', new_item + '        <item>', 1)
else:
    # 沒有現有 item，在 </channel> 之前插入
    content = content.replace('</channel>', new_item + '\n    </channel>')

with open("${APPCAST_FILE}", "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

    echo "  ✓ appcast.xml 已更新"
    echo "  ✓ 備份已儲存: ${APPCAST_FILE}.bak"
}

# 函式：驗證簽名
verify_signature() {
    print_step "驗證簽名..."

    if "$SIGN_UPDATE" --verify "$DMG_PATH" "$ED_SIGNATURE" 2>&1; then
        echo "  ✓ 簽名驗證通過"
    else
        print_warning "簽名驗證未通過，請手動確認"
    fi
}

# 函式：顯示摘要
show_summary() {
    echo ""
    echo "================================================"
    echo -e "  ${GREEN}Sparkle 簽發完成${NC}"
    echo "================================================"
    echo ""
    echo "  版本:       v${VERSION} (build ${BUILD_NUMBER})"
    echo "  DMG:        ${DMG_FILENAME}"
    echo "  檔案大小:   ${FILE_SIZE} bytes"
    echo "  EdDSA 簽名: ${ED_SIGNATURE}"
    echo ""
    echo "  下一步:"
    echo "    1. 確認 appcast.xml 內容正確"
    echo "    2. 上傳 DMG 到 GitHub Releases (tag: v${VERSION})"
    echo "    3. 推送 appcast.xml 到 GitHub Pages"
    echo ""
    echo "  快速指令:"
    echo "    git add appcast.xml"
    echo "    git commit -m \"Release v${VERSION}\""
    echo "    git tag v${VERSION}"
    echo "    git push origin main --tags"
    echo ""
}

# 主程式
main() {
    echo ""
    echo "================================================"
    echo "  XIV on Mac in TC - Sparkle 簽發腳本"
    echo "================================================"
    echo ""

    check_prerequisites
    resolve_dmg "$1"
    resolve_version

    echo ""
    print_info "DMG:     ${DMG_FILENAME}"
    print_info "版本:    ${VERSION} (build ${BUILD_NUMBER})"
    echo ""

    sign_dmg
    get_release_notes "$2"
    update_appcast
    verify_signature
    show_summary
}

# 處理參數
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

main "$1" "$2"

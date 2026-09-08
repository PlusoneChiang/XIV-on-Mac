#!/bin/bash

# 用法: .github/scripts/notarize.sh <.app 或 .dmg>

set -euo pipefail

TARGET_PATH="${1:?用法: $0 <.app 或 .dmg>}"
[[ -e "$TARGET_PATH" ]] || { echo "錯誤: 找不到 ${TARGET_PATH}" >&2; exit 1; }
for variable in NOTARY_KEY_P8_BASE64 NOTARY_KEY_ID NOTARY_ISSUER_ID APPLE_TEAM_ID; do
    [[ -n "${!variable:-}" ]] || { echo "錯誤: 必須設定 ${variable}" >&2; exit 1; }
done
for command in base64 ditto xcrun /usr/bin/plutil; do
    command -v "$command" >/dev/null 2>&1 || { echo "錯誤: 找不到 ${command}" >&2; exit 1; }
done

KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/notary-key.XXXXXX.p8")"
TEMP_ARCHIVE=""
trap 'rm -f "$KEY_PATH" "$TEMP_ARCHIVE"' EXIT
chmod 600 "$KEY_PATH"
printf '%s' "$NOTARY_KEY_P8_BASE64" | base64 -D >"$KEY_PATH"

case "$TARGET_PATH" in
    *.app)
        TEMP_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/notary-app.XXXXXX.zip")"
        rm -f "$TEMP_ARCHIVE"
        ditto -c -k --keepParent "$TARGET_PATH" "$TEMP_ARCHIVE"
        SUBMISSION_PATH="$TEMP_ARCHIVE"
        ;;
    *.dmg) SUBMISSION_PATH="$TARGET_PATH" ;;
    *) echo "錯誤: 只支援 .app 或 .dmg" >&2; exit 1 ;;
esac

print_log() {
    [[ -n "${NOTARY_ID:-}" ]] || return
    echo "公證失敗紀錄：" >&2
    xcrun notarytool log "$NOTARY_ID" --key "$KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --team-id "$APPLE_TEAM_ID" || echo "無法取得公證紀錄" >&2
}

if ! NOTARY_RESULT=$(xcrun notarytool submit "$SUBMISSION_PATH" --key "$KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --team-id "$APPLE_TEAM_ID" --wait --output-format json); then
    NOTARY_ID=$(printf '%s' "$NOTARY_RESULT" | /usr/bin/plutil -extract id raw - 2>/dev/null || true)
    print_log
    exit 1
fi
NOTARY_ID=$(printf '%s' "$NOTARY_RESULT" | /usr/bin/plutil -extract id raw -)
NOTARY_STATUS=$(printf '%s' "$NOTARY_RESULT" | /usr/bin/plutil -extract status raw -)
printf '%s\n' "$NOTARY_RESULT"
if [[ "$NOTARY_STATUS" != Accepted ]]; then
    print_log
    exit 1
fi

xcrun stapler staple "$TARGET_PATH"
xcrun stapler validate "$TARGET_PATH"

# XIV on Mac in TC 發布指南

本文件說明如何建置、簽名和發布新版本的 XIV on Mac in TC。

## 目錄

- [前置準備](#前置準備)
- [建置流程](#建置流程)
- [發布流程](#發布流程)
- [更新 appcast.xml](#更新-appcastxml)
- [驗證發布](#驗證發布)
- [常見問題](#常見問題)

---

## 前置準備

### 必要工具

1. **Xcode** - 用於建置專案
2. **create-dmg** - 用於建立 DMG 安裝檔
   ```bash
   brew install create-dmg
   ```
3. **Sparkle 工具** - 用於簽名更新檔
   - 下載位置: https://github.com/sparkle-project/Sparkle/releases
   - 建議放置於: `~/Sparkle/`

### Sparkle 金鑰設定（首次設定）

如果尚未產生簽名金鑰：

```bash
# 產生 EdDSA 金鑰對
~/Sparkle/bin/generate_keys
```

這會：
- 將私鑰儲存到 macOS Keychain（名稱：`Sparkle Private Key`）
- 輸出公鑰，需加入 `XIV-on-Mac-Info.plist` 的 `SUPublicEDKey`

> ⚠️ **重要**: 私鑰儲存在 Keychain 中，請確保備份。遺失私鑰將無法簽名更新檔。

---

## 建置流程

### 步驟 1：更新版本號

在 Xcode 中更新版本號：
1. 選擇專案 > Target: `XIV on Mac in TC`
2. General > Identity > Version 和 Build

或編輯 `XIV-on-Mac-Info.plist`：
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

### 步驟 2：執行建置腳本

```bash
# 進入專案目錄
cd /path/to/XIV-on-Mac

# 執行建置腳本（自動讀取版本號）
./scripts/build-dmg.sh

# 或指定版本號
./scripts/build-dmg.sh 1.0.0
```

建置完成後，輸出檔案位於：
```
Release/
├── XIV-on-Mac-TC-1.0.0.dmg    # DMG 安裝檔
└── build/
    └── export/
        └── XIV on Mac in TC.app
```

### 步驟 3：簽名 DMG

```bash
~/Sparkle/bin/sign_update "Release/XIV-on-Mac-TC-1.0.0.dmg"
```

輸出範例：
```
sparkle:edSignature="xxxxx..." length="171338590"
```

**請記錄此輸出**，稍後需要加入 `appcast.xml`。

---

## 發布流程

### 步驟 1：建立 GitHub Release

1. 前往 GitHub Repository > Releases > Draft a new release
2. 填寫資訊：
   - **Tag**: `v1.0.0`（符合版本號）
   - **Title**: `XIV on Mac in TC v1.0.0`
   - **Description**: 更新內容說明
3. 上傳檔案：
   - `Release/XIV-on-Mac-TC-1.0.0.dmg`
4. 發布 Release

### 步驟 2：更新 appcast.xml

編輯 `docs/appcast.xml`，在 `<channel>` 內新增（或更新）`<item>`：

```xml
<item>
    <title>版本 1.0.0</title>
    <pubDate>Sat, 18 Jan 2025 12:00:00 +0800</pubDate>
    <sparkle:version>1.0.0</sparkle:version>
    <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <description><![CDATA[
        <h2>更新內容</h2>
        <ul>
            <li>新功能說明</li>
            <li>修復問題說明</li>
        </ul>
    ]]></description>
    <enclosure
        url="https://github.com/plusonechiang/XIV-on-Mac-in-TC/releases/download/v1.0.0/XIV-on-Mac-TC-1.0.0.dmg"
        type="application/octet-stream"
        sparkle:edSignature="這裡填入簽名值"
        length="這裡填入檔案大小"
    />
</item>
```

### 步驟 3：部署 appcast.xml

將更新後的 `appcast.xml` 推送到 GitHub Pages：

```bash
# 如果 appcast.xml 在同一個 repo
git add docs/appcast.xml
git commit -m "Update appcast.xml for v1.0.0"
git push

# 如果 appcast.xml 在獨立的 GitHub Pages repo
cp docs/appcast.xml /path/to/XIV-on-Mac-in-TC/
cd /path/to/XIV-on-Mac-in-TC/
git add appcast.xml
git commit -m "Update appcast.xml for v1.0.0"
git push
```

---

## 更新 appcast.xml

### 欄位說明

| 欄位 | 說明 | 範例 |
|------|------|------|
| `<title>` | 版本標題 | `版本 1.0.0` |
| `<pubDate>` | 發布日期（RFC 2822 格式） | `Sat, 18 Jan 2025 12:00:00 +0800` |
| `sparkle:version` | 內部版本號（用於比較） | `1.0.0` |
| `sparkle:shortVersionString` | 顯示版本號 | `1.0.0` |
| `sparkle:minimumSystemVersion` | 最低系統需求 | `14.0` |
| `url` | DMG 下載連結 | GitHub Releases URL |
| `sparkle:edSignature` | EdDSA 簽名 | sign_update 輸出值 |
| `length` | 檔案大小（bytes） | sign_update 輸出值 |

### 日期格式產生

```bash
# 產生 RFC 2822 格式日期
date -R
# 或指定時區
TZ='Asia/Taipei' date '+%a, %d %b %Y %H:%M:%S %z'
```

### 多版本記錄

新版本的 `<item>` 放在最前面，舊版本保留在後面：

```xml
<channel>
    <!-- 最新版本 -->
    <item>
        <sparkle:version>1.1.0</sparkle:version>
        ...
    </item>

    <!-- 舊版本 -->
    <item>
        <sparkle:version>1.0.0</sparkle:version>
        ...
    </item>
</channel>
```

---

## 驗證發布

### 1. 測試 DMG 安裝

```bash
# 掛載 DMG
open Release/XIV-on-Mac-TC-1.0.0.dmg

# 將 App 拖曳到 Applications 測試安裝
```

### 2. 驗證 appcast.xml

```bash
# 檢查 appcast.xml 是否可存取
curl -I https://plusonechiang.github.io/XIV-on-Mac-in-TC/appcast.xml

# 下載並檢視內容
curl https://plusonechiang.github.io/XIV-on-Mac-in-TC/appcast.xml
```

### 3. 測試自動更新

1. 安裝舊版本 App
2. 啟動 App
3. 選擇 `XIV on Mac in TC` > `Check for Updates...`
4. 確認能偵測到新版本並下載更新

---

## 常見問題

### Q: 簽名時出現 Keychain 授權提示

這是正常的。Sparkle 需要存取 Keychain 中的私鑰來簽名。點擊「允許」或「永遠允許」。

### Q: 更新檢查失敗

1. 確認 `appcast.xml` URL 正確且可存取
2. 確認 `SUFeedURL` 設定正確
3. 確認 `SUPublicEDKey` 與簽名金鑰配對

### Q: 簽名驗證失敗

1. 確認使用相同的私鑰簽名
2. 確認 `sparkle:edSignature` 和 `length` 正確
3. 重新執行 `sign_update` 並更新 appcast.xml

### Q: 遺失私鑰

如果遺失私鑰，需要：
1. 產生新的金鑰對：`~/Sparkle/bin/generate_keys`
2. 更新 `Info.plist` 中的 `SUPublicEDKey`
3. 發布新版本（使用新金鑰簽名）

> ⚠️ 使用舊私鑰簽名的版本將無法升級到使用新金鑰的版本。使用者需手動下載安裝。

---

## 快速參考

```bash
# 完整發布流程
./scripts/build-dmg.sh 1.0.0
~/Sparkle/bin/sign_update "Release/XIV-on-Mac-TC-1.0.0.dmg"
# 更新 docs/appcast.xml
# 上傳 DMG 到 GitHub Releases
# 推送 appcast.xml 到 GitHub Pages
```

---

## 相關連結

- [Sparkle 官方文件](https://sparkle-project.org/documentation/)
- [GitHub Releases 說明](https://docs.github.com/en/repositories/releasing-projects-on-github)
- [GitHub Pages 說明](https://docs.github.com/en/pages)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

XIV on Mac 是一個 macOS 原生應用程式，作為 Final Fantasy XIV 的替代啟動器和 Wine 包裝器。本專案是針對台灣地區（TC Region）的分支版本，專門支援台灣版 FFXIV 的登入流程和伺服器。

**目標平台**: 僅支援 Apple Silicon Mac（M1/M2/M3/M4），不支援 Intel Mac。

## Build Commands

### Xcode Build
```bash
# 使用 Xcode 開啟專案
open "XIV on Mac in TC.xcodeproj"

# 命令列建置（需先安裝 xcodebuild）
xcodebuild -project "XIV on Mac in TC.xcodeproj" -scheme "XIV on Mac" -configuration Release build
```

### Wine Build (需要 Nix)
```bash
cd "XIV on Mac/wine-builder"
./nix-build.sh           # 建置 Wine
./package-runtime.sh     # 打包 Wine runtime 到 app bundle
```

### XIVLauncher.NativeAOT Submodule
XIVLauncher.NativeAOT 是一個預編譯的原生函式庫（`.dylib`），提供登入、修補和遊戲啟動功能。通常不需要重新建置，除非需要修改核心登入邏輯。

## Architecture Overview

### Core Components

**AppDelegate.swift** - 應用程式進入點
- 初始化 XIVLauncher 原生函式庫（`initXL()`）
- 設定 Wine 環境（`Wine.setup()`, `Wine.boot()`）
- 管理主要視窗和設定視窗
- 處理 Rosetta 2 和 GPU 相容性檢查

**LaunchController.swift** - 主要啟動控制器
- 管理 WebView 登入介面（`LoginPageManager`）
- 執行登入流程（`executeLogin()`）
- 處理遊戲修補（`startPatch()`）
- 呼叫 XIVLauncher 原生函式庫啟動遊戲

**Wine.swift** - Wine 環境管理
- 設定環境變數（DXVK、DXMT、GStreamer 等）
- 管理 Wine prefix（`~/Library/Application Support/XIV on Mac in TC/wineprefix`）
- Wine 註冊表操作
- 字體安裝和區域設定（繁體中文-台灣）

**Settings.swift** - 設定管理
- 透過 `UserDefaults` 持久化設定
- 同步設定到 XIVLauncher 原生函式庫（`syncToXL()`）
- 圖形後端選擇（DXVK/DXMT）

### Graphics Subsystem

**GraphicsUtils/** 目錄管理圖形後端：
- `Dxvk.swift` - DXVK 安裝和 state cache 管理
- `Dxmt.swift` - DXMT 安裝（macOS 14+ Metal 3.1 專用）
- `GraphicsInstaller.swift` - DLL 安裝到 Wine prefix

DXMT 是預設後端（macOS 14+），提供更好的 Metal 整合。DXVK 作為備援。

### Login Flow (TC Region)

1. `LaunchController.setupLoginPageContainer()` 建立 WebView 登入介面
2. `LoginPageManager` 處理 JavaScript 橋接和帳號管理
3. 登入資訊透過 `LoginCredentials` 存入 Keychain
4. `LoginResult` 呼叫 XIVLauncher 原生函式執行 SE 登入
5. 修補檢查和安裝（`PatchController`）
6. `LoginResult.startGame()` 透過 Wine 啟動遊戲

### External Dependencies

**Submodules:**
- `XIV on Mac/XIVLauncher.NativeAOT/source` - FFXIVQuickLauncher 的 .NET NativeAOT 編譯版本
- `XIV on Mac/wine-builder/source` - 自訂 Wine 建置（基於 marzent/winecx）

**主要 Swift 套件:**
- Sparkle - 自動更新
- KeychainAccess - 安全憑證儲存
- SeeURL - HTTP 用戶端
- OrderedCollections - 有序字典

## Key File Locations

- Wine prefix: `~/Library/Application Support/XIV on Mac in TC/wineprefix`
- 遊戲檔案: `~/Library/Application Support/XIV on Mac in TC/ffxiv`
- 遊戲設定: `~/Library/Application Support/XIV on Mac in TC/ffxivConfig`
- 修補檔案快取: `~/Library/Application Support/XIV on Mac in TC/patch`

## Localization

支援的語言: en, de, fr, ja, zh-tw

本地化字串位於 `*.lproj/` 目錄：
- `Localizable.strings` - 程式碼中使用的字串
- `Main.strings` - Storyboard UI 字串

## TC Region Specific Notes

- 登入使用 WebView 嵌入台灣版登入頁面，整合 reCAPTCHA
- 維護檢查預設停用（`Frontier.loginMaintenance` / `Frontier.gameMaintenance`）
- Dalamud 插件系統目前停用
- 自動登入功能停用
- Wine 區域設定為 zh-TW（0404）

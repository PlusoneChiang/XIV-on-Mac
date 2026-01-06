//
//  Wine.swift
//  XIV on Mac
//
//  Created by Marc-Aurel Zent on 01.02.22.
//

import CompatibilityTools
import Foundation

enum Wine {
    static let wineBinURL = Bundle.main.url(
        forResource: "bin", withExtension: nil, subdirectory: "wine")!
    static let wineDllURL = Bundle.main.url(
        forResource: "lib/wine", withExtension: nil, subdirectory: "wine")!
    static let prefix = Util.applicationSupport.appendingPathComponent(
        "wineprefix")

    @MainActor static func setup() {
        addEnvironmentVariable(
            "WINEDLLPATH",
            FileManager.default.fileSystemRepresentation(
                withPath: wineDllURL.path))
        addEnvironmentVariable("WINEMSYNC", msync ? "1" : "0")
        addEnvironmentVariable(
            "DXMT_CONFIG",
            "d3d11.metalSpatialUpscaleFactor=\(Settings.metalFxSpatialFactor);d3d11.preferredMaxFrameRate=\(Settings.maxFramerate);"
        )
        addEnvironmentVariable(
            "DXMT_METALFX_SPATIAL_SWAPCHAIN",
            Settings.metalFxSpatialEnabled ? "1" : "0")
        addEnvironmentVariable("XL_DXMT_ENABLED", Settings.dxmtEnabled ? "1" : "0")
        addEnvironmentVariable("LANG", "en_US")
        addEnvironmentVariable("MVK_ALLOW_METAL_FENCES", "1")  // XXX Required by DXVK for Apple/NVidia GPUs (better FPS than CPU Emulation)
        addEnvironmentVariable("MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE", "1")  // XXX Required by DXVK for Intel/NVidia GPUs
        addEnvironmentVariable("MVK_CONFIG_RESUME_LOST_DEVICE", "1")  // XXX Required by WINE (doesn't handle VK_ERROR_DEVICE_LOST correctly)
        addEnvironmentVariable("MVK_CONFIG_LOG_LEVEL", "mvk_error")
        // DXMT requires Metal Argument Buffers (Metal 3.1+)
        if Settings.dxmtEnabled {
            addEnvironmentVariable("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1")
        }
        // DXVK settings (also used by DXMT for compatibility)
        addEnvironmentVariable("DXVK_HUD", Dxvk.options.getHud())
        addEnvironmentVariable("DXVK_ASYNC", Dxvk.options.getAsync())
        addEnvironmentVariable("DXVK_FRAME_RATE", String(Settings.maxFramerate))
        addEnvironmentVariable("DXVK_CONFIG_FILE", "C:\\dxvk.conf")
        addEnvironmentVariable("DXVK_STATE_CACHE_PATH", "C:\\")
        addEnvironmentVariable("DXVK_LOG_PATH", "C:\\")
        addEnvironmentVariable("DOTNET_EnableWriteXorExecute", "0")  // XXX Required for Apple Silicon and .NET 7+
        addEnvironmentVariable(
            "MTL_HUD_ENABLED", Settings.metal3PerformanceOverlay ? "1" : "0")
        // Set GStreamer plugin path to bundled plugins
        let gstPluginPath = wineDllURL.deletingLastPathComponent().appendingPathComponent("gstreamer-1.0").path
        addEnvironmentVariable(
            "GST_PLUGIN_PATH",
            FileManager.default.fileSystemRepresentation(withPath: gstPluginPath))
        addEnvironmentVariable("GST_PLUGIN_SYSTEM_PATH_1_0", "")  // Disable system plugin paths
        addEnvironmentVariable("GST_PLUGIN_SCANNER_1_0", "")  // Disable plugin scanner
        addEnvironmentVariable("GST_REGISTRY_FORK", "no")  // Disable registry forking
        // Enable GStreamer debug logging
        addEnvironmentVariable("GST_DEBUG", "3")
        addEnvironmentVariable("GST_DEBUG_FILE", "/tmp/gstreamer-debug.log")
        addEnvironmentVariable("WINEDEBUG", "+mf,+mfplat,+winegstreamer")
        createCompatToolsInstance(
            FileManager.default.fileSystemRepresentation(
                withPath: wineBinURL.path), debug, esync)
    }

    static func boot() {
        DispatchQueue.global(qos: .utility).async {
            ensurePrefix()
            installFontIfNeeded()
            setLocaleToZhTW()
            configureMediaFoundation()
        }
    }
    
    /// 安裝 Sarasa Mono TC 字體到 Wine（如果尚未安裝）
    static func installFontIfNeeded() {
        let fontName = "SarasaMonoTC-Regular.ttf"
        let fontsPath = prefix.appendingPathComponent("drive_c/windows/Fonts")
        let targetFontPath = fontsPath.appendingPathComponent(fontName)
        
        // 檢查字體文件是否實際存在於 wine prefix 中
        if FileManager.default.fileExists(atPath: targetFontPath.path) {
            return
        }
        
        // 從 Bundle 獲取字體 - 先嘗試多種路徑
        var fontURL: URL?
        
        // 嘗試1: Resources 子目錄
        fontURL = Bundle.main.url(
            forResource: "SarasaMonoTC-Regular",
            withExtension: "ttf"
        )
        
        guard let fontURL = fontURL else {
            Log.error("[Wine] Font file '\(fontName)' not found in bundle")
            return
        }
        
        guard FileManager.default.fileExists(atPath: fontURL.path) else {
            Log.error("[Wine] Font source file does not exist")
            return
        }
        
        do {
            // 確保目錄存在
            if !FileManager.default.fileExists(atPath: fontsPath.path) {
                try FileManager.default.createDirectory(
                    at: fontsPath,
                    withIntermediateDirectories: true
                )
            }
            
            // 複製字體
            try FileManager.default.copyItem(at: fontURL, to: targetFontPath)
            
            // 設定字體文件權限為 644 (rw-r--r--)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: targetFontPath.path
            )
            
            // 在 Wine 註冊表中註冊字體
            addReg(
                key: "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts",
                value: "Sarasa Mono TC (TrueType)",
                data: fontName
            )
            
            Log.information("[Wine] Font installed: \(fontName)")
            
            // 設定字體替換和連結
            configureFontSubstitutionAndLinking()
        } catch {
            Log.error("[Wine] Failed to install font: \(error.localizedDescription)")
        }
    }
    
    /// 配置字體替換和字體連結，讓 Wine 應用程式能正確顯示中文
    static func configureFontSubstitutionAndLinking() {
        let fontName = "Sarasa Mono TC"
        
        // 1. Wine 字體替換 (Font Replacements)
        let wineReplacementKey = "HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements"
        addReg(key: wineReplacementKey, value: "MS Shell Dlg", data: fontName)
        addReg(key: wineReplacementKey, value: "MS Shell Dlg 2", data: fontName)
        addReg(key: wineReplacementKey, value: "MS Sans Serif", data: fontName)
        addReg(key: wineReplacementKey, value: "Microsoft Sans Serif", data: fontName)
        addReg(key: wineReplacementKey, value: "Tahoma", data: fontName)
        addReg(key: wineReplacementKey, value: "Segoe UI", data: fontName)
        addReg(key: wineReplacementKey, value: "Arial", data: fontName)
        addReg(key: wineReplacementKey, value: "Courier New", data: fontName)
        
        // 2. 字體連結 (Font Linking)
        let linkKey = "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink"
        let fallbackValue = "SarasaMonoTC-Regular.ttf,Sarasa Mono TC"
        addReg(key: linkKey, value: "Tahoma", data: fallbackValue)
        addReg(key: linkKey, value: "Microsoft Sans Serif", data: fallbackValue)
        addReg(key: linkKey, value: "MS Sans Serif", data: fallbackValue)
        addReg(key: linkKey, value: "Lucida Sans Unicode", data: fallbackValue)
        addReg(key: linkKey, value: "Arial", data: fallbackValue)
        
        // 3. 設定系統級別區域
        addReg(
            key: "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Nls\\Language",
            value: "InstallLanguage",
            data: "0404"
        )
        addReg(
            key: "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Nls\\Language",
            value: "Default",
            data: "0404"
        )
    }
    
    /// 設定 Wine 區域為繁體中文-台灣
    static func setLocaleToZhTW() {
        // 設定區域為繁體中文-台灣 (0404 = zh-TW)
        addReg(
            key: "HKEY_CURRENT_USER\\Control Panel\\International",
            value: "Locale",
            data: "00000404"
        )
        addReg(
            key: "HKEY_CURRENT_USER\\Control Panel\\International",
            value: "LocaleName",
            data: "zh-TW"
        )
        addReg(
            key: "HKEY_CURRENT_USER\\Control Panel\\International",
            value: "sLanguage",
            data: "CHT"
        )
        addReg(
            key: "HKEY_CURRENT_USER\\Control Panel\\International",
            value: "sCountry",
            data: "Taiwan"
        )
    }

    /// 配置 Wine MediaFoundation 以支援影片播放
    static func configureMediaFoundation() {
        // 啟用 winegstreamer.dll 作為 MediaFoundation 後端
        override(dll: "winegstreamer.dll", type: "native,builtin")
        override(dll: "mfplat.dll", type: "native,builtin")
        override(dll: "mf.dll", type: "native,builtin")
        override(dll: "mfreadwrite.dll", type: "native,builtin")

        // 確保 GStreamer 不會被禁用
        // 注意：不設定 DisableGstByteStreamHandler，或明確設為 0
        addReg(
            key: "HKEY_CURRENT_USER\\Software\\Wine\\MediaFoundation",
            value: "DisableGstByteStreamHandler",
            data: "0"
        )

        Log.information("[Wine] MediaFoundation configured with GStreamer support")
    }

    static func launch(
        command: String, blocking: Bool = false, wineD3D: Bool = false
    ) {
        runInPrefix(command, blocking, wineD3D)
    }

    static func pidOf(processName: String) -> Int {
        pidsOf(processName: processName).first ?? 0
    }

    static func pidsOf(processName: String) -> [Int] {
        Array(
            String(cString: getProcessIds(processName)).split(separator: " ")
                .compactMap { Int($0) })
    }

    static func convertToUnixPidFrom(winePid: Int) -> pid_t {
        getUnixProcessId(Int32(winePid))
    }

    static func running(processName: String) -> Bool {
        pidsOf(processName: processName).count > 0
    }

    static func taskKill(pid: Int) {
        launch(command: "taskkill /f /pid \(pid)", blocking: true)
    }

    static func taskKill(processName: String) {
        launch(command: "taskkill /f /im \(processName)", blocking: true)
    }

    static func touchDocuments() {
        launch(command: "cmd /c dir \"%userprofile%/My Documents\" > nul")
    }

    private static let esyncSettingKey = "EsyncSetting"
    static var esync: Bool {
        get {
            Util.getSetting(settingKey: esyncSettingKey, defaultValue: true)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: esyncSettingKey)
            createCompatToolsInstance(
                FileManager.default.fileSystemRepresentation(
                    withPath: wineBinURL.path), debug, esync)
        }
    }

    private static let msyncSettingKey = "MsyncSetting"
    static var msync: Bool {
        get {
            Util.getSetting(settingKey: msyncSettingKey, defaultValue: true)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: msyncSettingKey)
            addEnvironmentVariable("WINEMSYNC", msync ? "1" : "0")
        }
    }

    private static let wineDebugSettingKey = "WineDebugSetting"
    static var debug: String {
        get {
            Util.getSetting(
                settingKey: wineDebugSettingKey, defaultValue: "-all")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: wineDebugSettingKey)
            createCompatToolsInstance(
                FileManager.default.fileSystemRepresentation(
                    withPath: wineBinURL.path), debug, esync)
        }
    }

    static func kill() {
        killWine()
    }

    static func addReg(key: String, value: String, data: String) {
        addRegistryKey(key, value, data)
    }

    static func override(dll: String, type: String) {
        addReg(
            key: "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides", value: dll,
            data: type)
    }

    static func set(version: String) {
        launch(command: "winecfg -v \(version)", blocking: true)
    }

    private static let retinaSettingKey = "RetinaMode"
    static var retina: Bool {
        get {
            Util.getSetting(settingKey: retinaSettingKey, defaultValue: false)
        }
        set(_retina) {
            addReg(
                key: "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver",
                value: "RetinaMode", data: _retina ? "y" : "n")
            UserDefaults.standard.set(_retina, forKey: retinaSettingKey)
        }
    }

    private static let leftOptionIsAltSettingKey = "LeftOptionIsAlt"
    static var leftOptionIsAlt: Bool {
        get {
            Util.getSetting(
                settingKey: leftOptionIsAltSettingKey, defaultValue: true)
        }
        set(_leftOpenIsAlt) {
            addReg(
                key: "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver",
                value: "LeftOptionIsAlt", data: _leftOpenIsAlt ? "y" : "n")
            UserDefaults.standard.set(
                _leftOpenIsAlt, forKey: leftOptionIsAltSettingKey)
        }
    }

    private static let rightOptionIsAltSettingKey = "RightOptionIsAlt"
    static var rightOptionIsAlt: Bool {
        get {
            Util.getSetting(
                settingKey: rightOptionIsAltSettingKey, defaultValue: true)
        }
        set(_rightOpenIsAlt) {
            addReg(
                key: "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver",
                value: "RightOptionIsAlt", data: _rightOpenIsAlt ? "y" : "n")
            UserDefaults.standard.set(
                _rightOpenIsAlt, forKey: rightOptionIsAltSettingKey)
        }
    }

    private static let leftCommandIsCtrlSettingKey = "LeftCommandIsCtrl"
    static var leftCommandIsCtrl: Bool {
        get {
            Util.getSetting(
                settingKey: leftCommandIsCtrlSettingKey, defaultValue: true)
        }
        set(_leftCommandIsCtrl) {
            addReg(
                key: "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver",
                value: "LeftCommandIsCtrl", data: _leftCommandIsCtrl ? "y" : "n"
            )
            UserDefaults.standard.set(
                _leftCommandIsCtrl, forKey: leftCommandIsCtrlSettingKey)
        }
    }

    private static let rightCommandIsCtrlSettingKey = "RightCommandIsCtrl"
    static var rightCommandIsCtrl: Bool {
        get {
            Util.getSetting(
                settingKey: rightCommandIsCtrlSettingKey, defaultValue: true)
        }
        set(_rightCommandIsCtrl) {
            addReg(
                key: "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver",
                value: "RightCommandIsCtrl",
                data: _rightCommandIsCtrl ? "y" : "n")
            UserDefaults.standard.set(
                _rightCommandIsCtrl, forKey: rightCommandIsCtrlSettingKey)
        }
    }
}

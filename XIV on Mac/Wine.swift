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
        addEnvironmentVariable("XL_DXMT_ENABLED", "1")
        addEnvironmentVariable("DXMT_ENABLE_NVEXT", "1")
        addEnvironmentVariable("LANG", "en_US")
        addEnvironmentVariable("MVK_ALLOW_METAL_FENCES", "1")  // XXX Required by DXVK for Apple/NVidia GPUs (better FPS than CPU Emulation)
        addEnvironmentVariable("MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE", "1")  // XXX Required by DXVK for Intel/NVidia GPUs
        addEnvironmentVariable("MVK_CONFIG_RESUME_LOST_DEVICE", "1")  // XXX Required by WINE (doesn't handle VK_ERROR_DEVICE_LOST correctly)
        addEnvironmentVariable("MVK_CONFIG_LOG_LEVEL", "mvk_error")
        addEnvironmentVariable("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1")
        // Dalamud dotnet runtime 路徑設定（如果啟用 Dalamud，預先設定以避免 inject 時讀取不到）
        if Settings.dalamudEnabled {
            let runtimePath = Util.applicationSupport.appendingPathComponent("runtime").path
            addEnvironmentVariable("DALAMUD_RUNTIME", runtimePath)
            addEnvironmentVariable("DOTNET_ROOT", runtimePath)
        }
        addEnvironmentVariable(
            "MTL_HUD_ENABLED", Settings.metal3PerformanceOverlay ? "1" : "0")
        // GStreamer 配置：使用 bundle 真實路徑，registry 存放在 wineprefix
        let gstLibPath = wineDllURL.deletingLastPathComponent().path
        let gstPluginPath = "\(gstLibPath)/gstreamer-1.0"
        let gstRegistryPath = prefix.appendingPathComponent("gstreamer-registry.bin").path
        
        addEnvironmentVariable("GST_PLUGIN_PATH", gstPluginPath)
        addEnvironmentVariable("GST_REGISTRY", gstRegistryPath)
        // DYLD_FALLBACK_LIBRARY_PATH 作為最後備援
        addEnvironmentVariable(
            "DYLD_FALLBACK_LIBRARY_PATH",
            FileManager.default.fileSystemRepresentation(withPath: gstLibPath))
        addEnvironmentVariable("GST_PLUGIN_SYSTEM_PATH_1_0", "")  // Disable system plugin paths
        addEnvironmentVariable("GST_PLUGIN_SCANNER_1_0", "")  // Disable plugin scanner
        addEnvironmentVariable("GST_REGISTRY_FORK", "no")  // Disable registry forking
        
        // Enable GStreamer debug logging
        // addEnvironmentVariable("GST_DEBUG", "3")
        // addEnvironmentVariable("GST_DEBUG_FILE", "/tmp/xomit-gstreamer-support/gstreamer-debug.log")
        // addEnvironmentVariable("WINEDEBUG", "+mf,+mfplat,+winegstreamer")
        createCompatToolsInstance(
            FileManager.default.fileSystemRepresentation(
                withPath: wineBinURL.path), debug, false)
    }

    private static let initializationQueue = DispatchQueue(label: "Wine.initialization", qos: .utility)
    private static let initializationKey = DispatchSpecificKey<Bool>()
    private static let initializationGroup: DispatchGroup = {
        let group = DispatchGroup()
        group.enter()
        return group
    }()
    private static var initializationResult: Result<Void, Error>?

    static var isReady: Bool {
        guard initializationGroup.wait(timeout: .now()) == .success else { return false }
        if case .success? = initializationResult { return true }
        return false
    }

    /// 僅供背景登入流程等待；主執行緒使用 isReady，避免卡住畫面。
    static func waitUntilReady() throws {
        initializationGroup.wait()
        try initializationResult!.get()
    }

    @MainActor static func boot(completion: @escaping (Result<Void, Error>) -> Void) {
        initializationQueue.setSpecific(key: initializationKey, value: true)
        initializationQueue.async {
            let result = Result {
                _ = PrefixMigrator.migratePrefixIfNeeded()
                try preparePrefix()
            }
            initializationResult = result
            initializationGroup.leave()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private struct RuntimeVersion: Codable, Equatable {
        let repository: String
        let commit: String
        let tag: String
        let asset: String
        let sha256: String
    }

    private static func prefixError(_ message: String) -> NSError {
        NSError(domain: "WinePrefix", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// 在背景完成版本檢查，成功前不允許其他 Wine 操作。
    private static func preparePrefix() throws {
        let fm = FileManager.default
        let receiptName = ".winecx-runtime.json"
        let runtimeReceipt = wineBinURL.deletingLastPathComponent()
            .appendingPathComponent(receiptName)
        let receiptData = try Data(contentsOf: runtimeReceipt)
        let version = try JSONDecoder().decode(RuntimeVersion.self, from: receiptData)
        guard version.commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              version.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              !version.repository.isEmpty, !version.tag.isEmpty, !version.asset.isEmpty else {
            throw prefixError("App 內附的 Wine 版本資訊無效，請重新下載 App。")
        }
        let prefixReceipt = prefix.appendingPathComponent(receiptName)
        let previousVersion = (try? Data(contentsOf: prefixReceipt)).flatMap {
            try? JSONDecoder().decode(RuntimeVersion.self, from: $0)
        }
        let needsRebuild = previousVersion != version
            || !fm.fileExists(atPath: prefix.appendingPathComponent("system.reg").path)
            || !fm.fileExists(atPath: prefix.appendingPathComponent("user.reg").path)

        var prefixBackup: URL?
        if needsRebuild {
            // 自訂遊戲目錄若位於 prefix 內，不能在搬走 prefix 後繼續使用原路徑。
            let prefixPath = prefix.resolvingSymlinksInPath().standardizedFileURL.path
            for location in [Settings.gamePath, Settings.gameConfigPath] {
                let path = location.resolvingSymlinksInPath().standardizedFileURL.path
                guard path != prefixPath, !path.hasPrefix(prefixPath + "/") else {
                    throw prefixError("需要重建 Wine prefix，請先將遊戲與設定目錄移至 wineprefix 以外的位置：\(location.path)")
                }
            }
            // 等待現有 Wine 結束；逾時只停止等待，不終止使用者的遊戲。
            let server = Process()
            server.executableURL = wineBinURL.appendingPathComponent("wineserver")
            server.arguments = ["-w"]
            var environment = ProcessInfo.processInfo.environment
            environment["WINEPREFIX"] = prefix.path
            server.environment = environment
            let exited = DispatchSemaphore(value: 0)
            server.terminationHandler = { _ in exited.signal() }
            try server.run()
            guard exited.wait(timeout: .now() + 5) == .success else {
                server.terminate()
                throw prefixError("Wine 仍在執行中，請關閉遊戲與其他 Wine 程式後重新開啟 App。")
            }
            guard server.terminationStatus == 0 else {
                throw prefixError("無法確認 Wine 已結束，暫停重建 prefix。")
            }
            if fm.fileExists(atPath: prefix.path) {
                let backup = prefix.deletingLastPathComponent()
                    .appendingPathComponent("wineprefix-backup-\(UUID().uuidString)")
                try fm.moveItem(at: prefix, to: backup)
                prefixBackup = backup
                Log.information("[Wine] Prefix version changed or missing; backup: \(backup.path)")
            }
            try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        }

        // 原生層必須回報 wineboot 的執行結果，不能把初始化失敗標記為完成。
        guard ensurePrefix(needsRebuild) == 0 else {
            throw prefixError("Wine prefix 初始化失敗，請查看 wine.log；舊 prefix 已保留於備份目錄。")
        }
        try ensureD3DCompiler()
        try installFontIfNeeded()
        setLocaleToZhTW()
        configureMediaFoundation()
        Wine.leftOptionIsAlt = Wine.leftOptionIsAlt
        Wine.rightOptionIsAlt = Wine.rightOptionIsAlt
        Wine.retina = Wine.retina
        Settings.platform = Settings.platform
        try receiptData.write(to: prefixReceipt, options: .atomic)
        if let prefixBackup {
            try fm.removeItem(at: prefixBackup)
        }
        Log.information("[Wine] Prefix ready: \(version.tag) (\(version.commit))")
    }

    /// 缺少編譯器時使用 Wine runtime 的 DLL，不覆蓋 prefix 既有檔案。
    static func ensureD3DCompiler() throws {
        let fm = FileManager.default
        let target = prefix.appendingPathComponent("drive_c/windows/system32/d3dcompiler_47.dll")
        let source = wineDllURL.appendingPathComponent("x86_64-windows/d3dcompiler_47.dll")
        guard !fm.fileExists(atPath: target.path) else { return }
        guard fm.fileExists(atPath: source.path) else {
            throw prefixError("Wine runtime 缺少 d3dcompiler_47.dll。")
        }
        if (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil {
            try fm.removeItem(at: target)
        }
        try fm.createSymbolicLink(at: target, withDestinationURL: source)
    }

    /// 安裝 Sarasa Mono TC 字體到 Wine（如果尚未安裝）
    static func installFontIfNeeded() throws {
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
            throw prefixError("App 內缺少字體：\(fontName)")
        }
        
        guard FileManager.default.fileExists(atPath: fontURL.path) else {
            throw prefixError("App 內的字體檔案不存在。")
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
            throw error
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
        guard isReady else {
            Log.error("[Wine] Prefix is not ready; launch was blocked")
            return
        }
        runInPrefix(command, blocking, wineD3D)
    }

    static func pidOf(processName: String) -> Int {
        pidsOf(processName: processName).first ?? 0
    }

    static func pidsOf(processName: String) -> [Int] {
        guard isReady else { return [] }
        return Array(
            String(cString: getProcessIds(processName)).split(separator: " ")
                .compactMap { Int($0) })
    }

    static func convertToUnixPidFrom(winePid: Int) -> pid_t {
        guard isReady else { return 0 }
        return getUnixProcessId(Int32(winePid))
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
            initializationQueue.async {
                guard isReady else { return }
                createCompatToolsInstance(
                    FileManager.default.fileSystemRepresentation(
                        withPath: wineBinURL.path), debug, false)
            }
        }
    }

    static func kill() {
        guard isReady else { return }
        killWine()
    }

    static func addReg(key: String, value: String, data: String) {
        if DispatchQueue.getSpecific(key: initializationKey) == true || isReady {
            addRegistryKey(key, value, data)
        } else {
            initializationQueue.async {
                guard isReady else { return }
                addRegistryKey(key, value, data)
            }
        }
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

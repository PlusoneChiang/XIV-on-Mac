//
//  GameAudioRouter.swift
//  XIV on Mac
//
//  Created for audio routing feature
//

import CoreAudio
import Foundation

/// 遊戲音訊路由管理器
/// 監聽系統預設輸出裝置變更，動態更新 Wine Registry 讓遊戲切換音訊輸出
class GameAudioRouter {

    static let shared = GameAudioRouter()

    // MARK: - 常數

    /// Wine Registry 路徑
    private let wineDriverKey = #"HKEY_CURRENT_USER\Software\Wine\Drivers\winecoreaudio.drv"#

    // MARK: - 狀態

    /// 當前輸出裝置 UID
    private(set) var currentOutputDeviceUID: String = ""

    /// 當前輸出裝置的 Wine GUID
    private(set) var currentWineGUID: String = ""

    /// 是否正在運作
    private(set) var isRunning: Bool = false

    /// Wine 初始化是否已完成（包含音訊路由啟動或跳過）
    private(set) var bootCompleted: Bool = false

    /// 已知裝置的 GUID 快取 (CoreAudio UID -> Wine GUID)
    private var deviceGUIDCache: [String: String] = [:]

    /// 已知的裝置 UID 列表（用於偵測新裝置連接）
    private var knownDeviceUIDs: Set<String> = []

    private init() {}

    // MARK: - 公開方法

    /// 啟動音訊路由
    /// - Returns: 是否成功啟動
    @discardableResult
    func start() -> Bool {
        defer {
            // 不論成功或失敗，都標記為已完成
            bootCompleted = true
        }

        guard !isRunning else { return true }

        // 1. 取得當前系統預設裝置
        let defaultDevice = AudioDeviceManager.getDefaultOutputDevice()
        guard let uid = AudioDeviceManager.getDeviceUID(deviceID: defaultDevice) else {
            Log.error("[Audio] 無法取得預設輸出裝置")
            return false
        }
        currentOutputDeviceUID = uid

        // 2. 取得或建立此裝置的 Wine GUID
        let guid = getOrCreateWineGUID(for: uid)
        currentWineGUID = guid

        // 3. 設定 Wine 預設輸出裝置
        setWineDefaultOutput(guid: guid)

        // 4. 記錄當前已知的裝置列表
        knownDeviceUIDs = Set(AudioDeviceManager.getAllOutputDeviceUIDs())

        // 5. 註冊裝置變更監聽
        registerDeviceChangeListener()
        registerDeviceListChangeListener()

        isRunning = true
        let deviceName = AudioDeviceManager.getDeviceName(deviceID: defaultDevice) ?? "未知"
        Log.information("[Audio] 音訊路由已啟動，輸出: \(deviceName)")
        return true
    }

    /// 等待音訊路由初始化完成（使用輪詢）
    /// - Parameter timeout: 最大等待時間（秒）
    /// - Returns: 是否在超時前完成
    @discardableResult
    func waitForReady(timeout: TimeInterval = 10.0) -> Bool {
        // 如果已經完成，直接返回
        if bootCompleted {
            return isRunning
        }

        // 輪詢等待
        let startTime = Date()
        let pollInterval: TimeInterval = 0.1

        while Date().timeIntervalSince(startTime) < timeout {
            if bootCompleted {
                return isRunning
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }

        // 超時
        return bootCompleted && isRunning
    }

    /// 標記為已跳過初始化（當音訊路由未啟用時呼叫）
    func markAsSkipped() {
        bootCompleted = true
    }

    /// 停止音訊路由
    func stop() {
        guard isRunning else { return }

        AudioDeviceManager.removeDefaultOutputListener()
        AudioDeviceManager.removeDevicesListener()

        isRunning = false
        knownDeviceUIDs.removeAll()
        Log.information("[Audio] 音訊路由已停止")
    }

    /// 取得當前輸出裝置名稱
    func getCurrentOutputDeviceName() -> String? {
        let defaultDevice = AudioDeviceManager.getDefaultOutputDevice()
        return AudioDeviceManager.getDeviceName(deviceID: defaultDevice)
    }

    // MARK: - 私有方法

    /// 取得或建立裝置的 Wine GUID
    /// - Parameter coreAudioUID: CoreAudio 裝置 UID
    /// - Returns: Wine GUID
    private func getOrCreateWineGUID(for coreAudioUID: String) -> String {
        // 檢查快取
        if let cachedGUID = deviceGUIDCache[coreAudioUID] {
            return cachedGUID
        }

        // 嘗試從 Wine Registry 讀取已存在的 GUID
        if let existingGUID = readExistingWineGUID(for: coreAudioUID) {
            deviceGUIDCache[coreAudioUID] = existingGUID
            return existingGUID
        }

        // 沒有找到，生成新的 GUID
        let guid = UUID().uuidString.uppercased()
        deviceGUIDCache[coreAudioUID] = guid

        // 寫入 Wine Registry 建立對應關係
        let deviceKey = #"HKEY_CURRENT_USER\Software\Wine\Drivers\winecoreaudio.drv\devices\0,\#(coreAudioUID)"#
        let hexData = guidToHexString(guid)
        Wine.addRegBinary(key: deviceKey, value: "guid", hexData: hexData)

        return guid
    }

    /// 從 Wine Registry (user.reg) 讀取已存在的裝置 GUID
    /// - Parameter coreAudioUID: CoreAudio 裝置 UID
    /// - Returns: 已存在的 GUID，如果沒有則返回 nil
    private func readExistingWineGUID(for coreAudioUID: String) -> String? {
        let userRegPath = Util.applicationSupport
            .appendingPathComponent("wineprefix")
            .appendingPathComponent("user.reg")

        guard let content = try? String(contentsOf: userRegPath, encoding: .utf8) else {
            return nil
        }

        // Wine registry 中的路徑格式：[Software\\Wine\\Drivers\\winecoreaudio.drv\\devices\\0,<UID>]
        // 需要將 CoreAudio UID 中的特殊字符轉義
        let escapedUID = coreAudioUID.replacingOccurrences(of: "\\", with: "\\\\")
        let sectionPattern = #"\[Software\\\\Wine\\\\Drivers\\\\winecoreaudio\.drv\\\\devices\\\\0,\#(escapedUID)\]"#

        // 搜尋對應的 section
        guard let sectionRange = content.range(of: sectionPattern, options: .regularExpression) else {
            return nil
        }

        // 從 section 開始搜尋 guid 值
        let sectionStart = sectionRange.upperBound
        let remainingContent = String(content[sectionStart...])

        // 搜尋下一個 section 的位置（以 [ 開頭）
        let nextSectionRange = remainingContent.range(of: "\n[", options: [])
        let sectionContent: String
        if let nextRange = nextSectionRange {
            sectionContent = String(remainingContent[..<nextRange.lowerBound])
        } else {
            sectionContent = remainingContent
        }

        // 搜尋 "guid"=hex:XX,XX,XX,...
        let guidPattern = #""guid"=hex:([0-9a-fA-F,]+)"#
        guard let guidMatch = sectionContent.range(of: guidPattern, options: .regularExpression) else {
            return nil
        }

        // 提取 hex 資料
        let matchedString = String(sectionContent[guidMatch])
        guard let hexStart = matchedString.range(of: "hex:")?.upperBound else {
            return nil
        }
        let hexData = String(matchedString[hexStart...]).replacingOccurrences(of: ",", with: "")

        // 將 hex 資料轉換回 GUID 字串
        return hexStringToGUID(hexData)
    }

    /// 將 Wine REG_BINARY hex string 轉換回標準 GUID 字串
    /// - Parameter hexData: 十六進位字串（如 "D4C3B2A1F6E5..."）
    /// - Returns: 標準 GUID 字串（如 "A1B2C3D4-E5F6-..."）
    private func hexStringToGUID(_ hexData: String) -> String? {
        let clean = hexData.uppercased()
        guard clean.count == 32 else { return nil }

        // Data1 (8 chars) - reverse byte order back
        let data1Bytes = String(clean.prefix(8))
        let data1 = stride(from: 6, through: 0, by: -2).map {
            let start = data1Bytes.index(data1Bytes.startIndex, offsetBy: $0)
            let end = data1Bytes.index(start, offsetBy: 2)
            return String(data1Bytes[start..<end])
        }.joined()

        // Data2 (4 chars) - reverse byte order back
        let data2Start = clean.index(clean.startIndex, offsetBy: 8)
        let data2End = clean.index(data2Start, offsetBy: 4)
        let data2Bytes = String(clean[data2Start..<data2End])
        let data2 = String(data2Bytes.suffix(2)) + String(data2Bytes.prefix(2))

        // Data3 (4 chars) - reverse byte order back
        let data3Start = clean.index(clean.startIndex, offsetBy: 12)
        let data3End = clean.index(data3Start, offsetBy: 4)
        let data3Bytes = String(clean[data3Start..<data3End])
        let data3 = String(data3Bytes.suffix(2)) + String(data3Bytes.prefix(2))

        // Data4 (16 chars) - keep as-is, but split into two parts
        let data4Start = clean.index(clean.startIndex, offsetBy: 16)
        let data4Part1End = clean.index(data4Start, offsetBy: 4)
        let data4Part1 = String(clean[data4Start..<data4Part1End])
        let data4Part2 = String(clean[data4Part1End...])

        return "\(data1)-\(data2)-\(data3)-\(data4Part1)-\(data4Part2)"
    }

    /// 設定 Wine 預設輸出裝置
    /// - Parameter guid: Wine GUID
    private func setWineDefaultOutput(guid: String) {
        let deviceID = "{0.0.0.00000000}.{\(guid)}"
        Wine.addReg(key: wineDriverKey, value: "DefaultOutput", data: deviceID)
    }

    /// 註冊裝置變更監聽
    private func registerDeviceChangeListener() {
        AudioDeviceManager.registerDefaultOutputListener { [weak self] newDeviceID in
            self?.onDefaultOutputChanged(newDeviceID: newDeviceID)
        }
    }

    /// 註冊裝置列表變更監聽（用於偵測新裝置連接）
    private func registerDeviceListChangeListener() {
        AudioDeviceManager.registerDevicesListener { [weak self] currentUIDs in
            self?.onDeviceListChanged(currentUIDs: currentUIDs)
        }
    }

    /// 裝置列表變更時呼叫
    private func onDeviceListChanged(currentUIDs: [String]) {
        let currentSet = Set(currentUIDs)
        let newDevices = currentSet.subtracting(knownDeviceUIDs)

        if !newDevices.isEmpty {
            Wine.rescanAudioDevices()
        }

        knownDeviceUIDs = currentSet
    }

    /// 系統預設音訊變更時呼叫
    private func onDefaultOutputChanged(newDeviceID: AudioDeviceID) {
        guard let newUID = AudioDeviceManager.getDeviceUID(deviceID: newDeviceID) else { return }
        guard newUID != currentOutputDeviceUID else { return }

        let deviceName = AudioDeviceManager.getDeviceName(deviceID: newDeviceID) ?? "未知"
        Log.information("[Audio] 輸出裝置變更: \(deviceName)")

        currentOutputDeviceUID = newUID
        let guid = getOrCreateWineGUID(for: newUID)
        currentWineGUID = guid
        setWineDefaultOutput(guid: guid)
    }

    // MARK: - GUID 轉換

    /// 將標準 GUID 字串轉換為 Wine REG_BINARY 格式的 hex string
    private func guidToHexString(_ guid: String) -> String {
        let clean = guid.replacingOccurrences(of: "-", with: "").uppercased()

        // Data1 (8 chars) - reverse byte order
        let data1 = String(clean.prefix(8))
        let data1Reversed = stride(from: 6, through: 0, by: -2).map {
            let start = data1.index(data1.startIndex, offsetBy: $0)
            let end = data1.index(start, offsetBy: 2)
            return String(data1[start..<end])
        }.joined()

        // Data2 (4 chars) - reverse byte order
        let data2Start = clean.index(clean.startIndex, offsetBy: 8)
        let data2End = clean.index(data2Start, offsetBy: 4)
        let data2 = String(clean[data2Start..<data2End])
        let data2Reversed = String(data2.suffix(2)) + String(data2.prefix(2))

        // Data3 (4 chars) - reverse byte order
        let data3Start = clean.index(clean.startIndex, offsetBy: 12)
        let data3End = clean.index(data3Start, offsetBy: 4)
        let data3 = String(clean[data3Start..<data3End])
        let data3Reversed = String(data3.suffix(2)) + String(data3.prefix(2))

        // Data4 (16 chars) - keep as-is
        let data4 = String(clean.suffix(16))

        return data1Reversed + data2Reversed + data3Reversed + data4
    }
}

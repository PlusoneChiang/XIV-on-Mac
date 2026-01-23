//
//  AudioDeviceManager.swift
//  XIV on Mac
//
//  Created for audio routing feature
//

import AudioToolbox
import CoreAudio
import Foundation

/// CoreAudio 裝置管理封裝
enum AudioDeviceManager {

    // MARK: - 取得裝置資訊

    /// 取得當前系統預設輸出裝置
    static func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        _ = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return deviceID
    }

    /// 取得裝置 UID
    static func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &uid
        )

        if status != noErr { return nil }
        return uid as String?
    }

    /// 取得裝置名稱
    static func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )

        if status != noErr {
            return nil
        }

        return name as String?
    }

    /// 取得內建輸出裝置的 UID（作為 fallback）
    static func getBuiltInOutputDeviceUID() -> String? {
        // 列舉所有音訊裝置
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // 取得裝置數量
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )

        if status != noErr { return nil }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )

        if status != noErr { return nil }

        // 尋找內建輸出裝置
        for deviceID in deviceIDs {
            if isBuiltInOutputDevice(deviceID: deviceID) {
                return getDeviceUID(deviceID: deviceID)
            }
        }

        return nil
    }

    /// 檢查是否為內建輸出裝置
    private static func isBuiltInOutputDevice(deviceID: AudioDeviceID) -> Bool {
        // 檢查是否有輸出 stream
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        if status != noErr || size == 0 {
            return false  // 沒有輸出 stream
        }

        // 檢查 transport type 是否為內建
        var transportType: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        address.mScope = kAudioObjectPropertyScopeGlobal

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)
        if status != noErr {
            return false
        }

        return transportType == kAudioDeviceTransportTypeBuiltIn
    }

    // MARK: - Aggregate Device 管理

    /// 取得裝置的輸出 channel 數量
    static func getOutputChannelCount(deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        if status != noErr { return 2 }  // 預設 2 channels

        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPtr.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPtr)
        if status != noErr { return 2 }

        var totalChannels: UInt32 = 0
        let bufferList = bufferListPtr.pointee
        withUnsafePointer(to: bufferList.mBuffers) { ptr in
            for i in 0..<Int(bufferList.mNumberBuffers) {
                let buffer = ptr.advanced(by: i).pointee
                totalChannels += buffer.mNumberChannels
            }
        }

        return totalChannels > 0 ? totalChannels : 2
    }

    /// 根據 UID 取得 AudioDeviceID
    static func getDeviceIDByUID(_ uid: String) -> AudioDeviceID? {
        // 列舉所有裝置，找到匹配 UID 的裝置
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )

        if status != noErr { return nil }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )

        if status != noErr { return nil }

        // 找到匹配 UID 的裝置
        for deviceID in deviceIDs {
            if let deviceUID = getDeviceUID(deviceID: deviceID), deviceUID == uid {
                return deviceID
            }
        }

        return nil
    }

    /// 建立 Aggregate Device（支援 channel mapping）
    /// - Parameters:
    ///   - name: 裝置名稱
    ///   - uid: 裝置 UID
    ///   - subDeviceUIDs: 所有 sub-device 的 UID 列表
    ///   - masterDeviceUID: master device 的 UID（時鐘源，應為永遠在線的裝置如內建揚聲器）
    ///   - outputDeviceUID: 實際輸出音訊的裝置 UID（可能是藍芽等外部裝置）
    static func createAggregateDevice(
        name: String,
        uid: String,
        subDeviceUIDs: [String],
        masterDeviceUID: String,
        outputDeviceUID: String? = nil
    ) -> AudioDeviceID? {
        // 建立 sub-device 描述
        var subDevices: [[String: Any]] = []
        for subUID in subDeviceUIDs {
            subDevices.append([kAudioSubDeviceUIDKey: subUID])
        }

        // 決定實際輸出的裝置
        let actualOutputUID = outputDeviceUID ?? masterDeviceUID

        // 取得輸出裝置的 channel 數量
        var outputChannelCount: UInt32 = 2
        if let outputDeviceID = getDeviceIDByUID(actualOutputUID) {
            outputChannelCount = getOutputChannelCount(deviceID: outputDeviceID)
        }

        // 建立 channel map：將所有 channel 路由到輸出裝置
        // 格式：每個元素代表一個輸出 channel，值是 sub-device 的 channel 索引
        // 負數或大於總 channel 數的值表示靜音
        var channelMap: [Int] = []
        for i in 0..<Int(outputChannelCount) {
            channelMap.append(i)  // 直接映射
        }

        // 建立 Aggregate Device 描述
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMasterSubDeviceKey: masterDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: false
        ]


        var aggregateDeviceID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &aggregateDeviceID
        )

        if status != noErr { return nil }

        // 建立後嘗試設定 sub-device 音量
        if subDeviceUIDs.count > 1, let outputUID = outputDeviceUID, outputUID != masterDeviceUID {
            // 將非輸出裝置靜音
            for subUID in subDeviceUIDs where subUID != outputUID {
                muteSubDevice(subDeviceUID: subUID, mute: true)
            }
            // 確保輸出裝置不靜音
            muteSubDevice(subDeviceUID: outputUID, mute: false)
        }

        return aggregateDeviceID
    }

    /// 將 sub-device 靜音或取消靜音（不影響系統音量）
    static func muteSubDevice(subDeviceUID: String, mute: Bool) {
        guard let deviceID = getDeviceIDByUID(subDeviceUID) else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &address) {
            var muteValue: UInt32 = mute ? 1 : 0
            _ = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &muteValue
            )
        }
    }

    /// 更新 Aggregate Device 的 sub-device list
    /// - Parameters:
    ///   - aggregateID: Aggregate Device ID
    ///   - subDeviceUIDs: 所有 sub-device 的 UID 列表
    ///   - masterDeviceUID: master device 的 UID（時鐘源）
    ///   - outputDeviceUID: 實際輸出音訊的裝置 UID
    static func updateAggregateSubDevices(
        aggregateID: AudioDeviceID,
        subDeviceUIDs: [String],
        masterDeviceUID: String,
        outputDeviceUID: String? = nil
    ) -> Bool {
        // 建立新的 sub-device 描述
        var subDevices: [[String: Any]] = []
        for subUID in subDeviceUIDs {
            subDevices.append([kAudioSubDeviceUIDKey: subUID])
        }

        // 更新 sub-device list
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var cfSubDevices = subDevices as CFArray
        var size = UInt32(MemoryLayout<CFArray>.size)

        var status = AudioObjectSetPropertyData(
            aggregateID,
            &address,
            0,
            nil,
            size,
            &cfSubDevices
        )

        if status != noErr { return false }

        // 更新 master device (macOS 12+ 使用 MainSubDevice)
        address.mSelector = kAudioAggregateDevicePropertyMainSubDevice
        var masterUID = masterDeviceUID as CFString
        size = UInt32(MemoryLayout<CFString>.size)

        status = AudioObjectSetPropertyData(
            aggregateID,
            &address,
            0,
            nil,
            size,
            &masterUID
        )

        if status != noErr { return false }

        // 更新靜音狀態：只讓輸出裝置有聲音
        let actualOutputUID = outputDeviceUID ?? masterDeviceUID
        if subDeviceUIDs.count > 1 {
            for subUID in subDeviceUIDs {
                if subUID == actualOutputUID {
                    muteSubDevice(subDeviceUID: subUID, mute: false)
                } else {
                    muteSubDevice(subDeviceUID: subUID, mute: true)
                }
            }
        }

        return true
    }

    /// 銷毀 Aggregate Device
    static func destroyAggregateDevice(deviceID: AudioDeviceID) {
        _ = AudioHardwareDestroyAggregateDevice(deviceID)
    }

    // MARK: - 裝置變更監聽

    private static var defaultOutputListenerCallback: ((AudioDeviceID) -> Void)?
    private static var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?

    private static var devicesListenerCallback: (([String]) -> Void)?
    private static var devicesListenerBlock: AudioObjectPropertyListenerBlock?

    /// 註冊預設輸出裝置變更監聽
    static func registerDefaultOutputListener(callback: @escaping (AudioDeviceID) -> Void) {
        defaultOutputListenerCallback = callback

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        defaultOutputListenerBlock = { (_, _) in
            let newDeviceID = getDefaultOutputDevice()
            DispatchQueue.main.async {
                defaultOutputListenerCallback?(newDeviceID)
            }
        }

        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            defaultOutputListenerBlock!
        )

    }

    /// 移除預設輸出裝置變更監聽
    static func removeDefaultOutputListener() {
        guard let block = defaultOutputListenerBlock else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        defaultOutputListenerBlock = nil
        defaultOutputListenerCallback = nil
    }

    /// 取得所有音訊輸出裝置的 UID 列表
    static func getAllOutputDeviceUIDs() -> [String] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )

        if status != noErr { return [] }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )

        if status != noErr { return [] }

        // 只返回有輸出能力的裝置
        var outputUIDs: [String] = []
        for deviceID in deviceIDs {
            // 檢查是否有輸出 stream
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
            if streamStatus == noErr && streamSize > 0 {
                if let uid = getDeviceUID(deviceID: deviceID) {
                    outputUIDs.append(uid)
                }
            }
        }

        return outputUIDs
    }

    /// 註冊裝置列表變更監聽（用於偵測裝置斷線）
    static func registerDevicesListener(callback: @escaping ([String]) -> Void) {
        devicesListenerCallback = callback

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        devicesListenerBlock = { (_, _) in
            let currentUIDs = getAllOutputDeviceUIDs()
            // 使用高優先級佇列，盡快處理
            DispatchQueue.main.async {
                devicesListenerCallback?(currentUIDs)
            }
        }

        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            devicesListenerBlock!
        )

    }

    /// 移除裝置列表變更監聽
    static func removeDevicesListener() {
        guard let block = devicesListenerBlock else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        devicesListenerBlock = nil
        devicesListenerCallback = nil
    }

    /// 檢查特定 UID 的裝置是否存在
    static func deviceExists(uid: String) -> Bool {
        return getDeviceIDByUID(uid) != nil
    }
}

//
//  SettingsAudioTabView.swift
//  XIV on Mac
//
//  Created for audio routing feature
//

import SwiftUI

struct SettingsAudioTabView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 音訊路由開關
            Toggle(isOn: $viewModel.audioRoutingEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SETTINGS_AUDIO_ROUTING_ENABLED")
                    Text("SETTINGS_AUDIO_ROUTING_DESCRIPTION")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 注意事項
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("SETTINGS_AUDIO_NOTICE_HEADER")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        noticeItem("SETTINGS_AUDIO_NOTICE_APP_STAY")
                    }
                    .padding(.leading, 24)
                }
            }

            // 狀態資訊
            if viewModel.audioRoutingEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("SETTINGS_AUDIO_STATUS_HEADER")
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "speaker.wave.2")
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            statusRow(
                                label: "SETTINGS_AUDIO_STATUS_CURRENT_OUTPUT",
                                value: viewModel.currentOutputDevice
                            )
                            statusRow(
                                label: "SETTINGS_AUDIO_STATUS_STATE",
                                value: viewModel.routerStatus
                            )
                        }
                        .padding(.leading, 24)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.startStatusUpdates()
        }
        .onDisappear {
            viewModel.stopStatusUpdates()
        }
    }

    private func noticeItem(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(key)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    private func statusRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

extension SettingsAudioTabView {
    class ViewModel: ObservableObject {
        @Published var audioRoutingEnabled: Bool {
            didSet {
                Settings.audioRoutingEnabled = audioRoutingEnabled

                // 立即啟動或停止音訊路由
                if audioRoutingEnabled {
                    DispatchQueue.global(qos: .utility).async {
                        GameAudioRouter.shared.start()
                        DispatchQueue.main.async { [weak self] in
                            self?.updateStatus()
                        }
                    }
                } else {
                    GameAudioRouter.shared.stop()
                    updateStatus()
                }
            }
        }

        @Published var currentOutputDevice: String = "-"
        @Published var routerStatus: String = "-"

        private var statusTimer: Timer?

        init() {
            audioRoutingEnabled = Settings.audioRoutingEnabled
            updateStatus()
        }

        func startStatusUpdates() {
            updateStatus()
            // 每 2 秒更新一次狀態
            statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatus()
                }
            }
        }

        func stopStatusUpdates() {
            statusTimer?.invalidate()
            statusTimer = nil
        }

        func updateStatus() {
            let router = GameAudioRouter.shared

            if router.isRunning {
                currentOutputDevice = router.getCurrentOutputDeviceName() ?? "未知"
                routerStatus = "運作中"
            } else {
                currentOutputDevice = "-"
                routerStatus = audioRoutingEnabled ? "啟動中..." : "未啟用"
            }
        }
    }
}

#Preview {
    SettingsAudioTabView()
        .frame(width: 600, height: 400)
}

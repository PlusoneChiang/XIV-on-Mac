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
                        .font(.caption)
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
                        noticeItem("SETTINGS_AUDIO_NOTICE_RESTART")
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
            viewModel.updateStatus()
        }
    }

    private func noticeItem(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(key)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func statusRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}

extension SettingsAudioTabView {
    class ViewModel: ObservableObject {
        @Published var audioRoutingEnabled: Bool {
            didSet {
                Settings.audioRoutingEnabled = audioRoutingEnabled
            }
        }

        @Published var currentOutputDevice: String = "-"
        @Published var routerStatus: String = "-"

        init() {
            audioRoutingEnabled = Settings.audioRoutingEnabled
            updateStatus()
        }

        func updateStatus() {
            let router = GameAudioRouter.shared

            if router.isRunning {
                currentOutputDevice = router.getCurrentOutputDeviceName() ?? "未知"
                routerStatus = "運作中"
            } else {
                currentOutputDevice = "-"
                routerStatus = audioRoutingEnabled ? "等待重啟 App" : "未啟用"
            }
        }
    }
}

#Preview {
    SettingsAudioTabView()
        .frame(width: 600, height: 400)
}

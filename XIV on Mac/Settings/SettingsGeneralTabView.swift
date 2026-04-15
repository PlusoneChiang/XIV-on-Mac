//
//  SettingsGeneralTabView.swift
//  XIV on Mac
//
//  Created by Chris Backas on 1/14/23.
//

import SeeURL  // HTTPClient/Download speed limiter setting
import SwiftUI

struct SettingsGeneralTabView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack {
                // TC 版不需要憑證和免費試玩設定，隱藏此區塊
                /*
                VStack {
                    HStack {
                        Text("SETTINGS_GENERAL_TITLE_LICENSE")
                            .font(.headline)

                        Spacer()
                    }

                    Text("SETTINGS_GENERAL_LANGUAGE_AND_LICENSE_BLURB")
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)

                    HStack {
                        Picker(
                            selection: $viewModel.language,
                            label: Text("SETTINGS_LANGUAGE_PICKER")
                        ) {
                            Text("SETTINGS_LANGUAGE_JAPANESE").tag(
                                FFXIVLanguage.japanese)
                            Text("SETTINGS_LANGUAGE_ENGLISH").tag(
                                FFXIVLanguage.english)
                            Text("SETTINGS_LANGUAGE_FRENCH").tag(
                                FFXIVLanguage.french)
                            Text("SETTINGS_LANGUAGE_GERMAN").tag(
                                FFXIVLanguage.german)
                        }
                        .padding(.bottom)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(true)

                        Picker(
                            selection: $viewModel.platform,
                            label: Text("SETTINGS_PLATFORM_PICKER")
                        ) {
                            Text("SETTINGS_PLATFORM_MAC").tag(FFXIVPlatform.mac)
                            Text("SETTINGS_PLATFORM_WINDOWS").tag(
                                FFXIVPlatform.windows)
                            Text("SETTINGS_PLATFORM_STEAM").tag(
                                FFXIVPlatform.steam)
                        }
                        .padding(.bottom)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(true)

                        Spacer()
                    }

                    HStack {
                        Toggle(isOn: $viewModel.freeTrial) {
                            Text("SETTINGS_FREE_TRIAL")
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        Spacer()
                    }

                    Text("SETTINGS_GENERAL_FREE_TRIAL_BLURB")
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                }
                .padding([.leading, .trailing, .top])
                */

                VStack {
                    HStack {
                        Text("SETTINGS_GENERAL_TITLE_NETWORK")
                            .font(.headline)

                        Spacer()
                    }

                    HStack {
                        Toggle(isOn: $viewModel.limitDownloadEnabled) {
                            Text("SETTINGS_DOWNLOAD_LIMIT")
                        }

                        TextField(
                            "SETTINGS_DOWNLOAD_LIMIT_PLACEHOLDER",
                            text: $viewModel.limitDownloadSpeed
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(!viewModel.limitDownloadEnabled)

                        Text("SETTINGS_DOWNLOAD_LIMIT_UNITS")
                        Spacer()
                    }
                }
                .padding([.leading, .trailing, .top])

                HStack {
                    VStack {
                        HStack {
                            Text("SETTINGS_GENERAL_TITLE_INPUT")
                                .font(.headline)

                            Spacer()
                        }

                        HStack {
                            Picker(
                                "SETTINGS_GENERAL_INPUT_LEFT_OPTION",
                                selection: $viewModel.leftOptionIsAlt
                            ) {
                                Text(
                                    "SETTINGS_GENERAL_INPUT_BUTTON_WINDOWS_ALT"
                                ).tag(true)
                                Text(
                                    "SETTINGS_GENERAL_INPUT_BUTTON_MACOS_OPTION"
                                ).tag(false)
                            }

                            Picker(
                                "SETTINGS_GENERAL_INPUT_RIGHT_OPTION",
                                selection: $viewModel.rightOptionIsAlt
                            ) {
                                Text(
                                    "SETTINGS_GENERAL_INPUT_BUTTON_WINDOWS_ALT"
                                ).tag(true)
                                Text(
                                    "SETTINGS_GENERAL_INPUT_BUTTON_MACOS_OPTION"
                                ).tag(false)
                            }
                        }

                        HStack {
                            Picker(
                                "SETTINGS_GENERAL_INPUT_LEFT_COMMAND",
                                selection: $viewModel.leftCommandIsCtrl
                            ) {
                                Text("SETTINGS_GENERAL_INPUT_BUTTON_CTRL").tag(
                                    true)
                                Text("SETTINGS_GENERAL_INPUT_BUTTON_ALT").tag(
                                    false)
                            }

                            Picker(
                                "SETTINGS_GENERAL_INPUT_RIGHT_COMMAND",
                                selection: $viewModel.rightCommandIsCtrl
                            ) {
                                Text("SETTINGS_GENERAL_INPUT_BUTTON_CTRL").tag(
                                    true)
                                Text("SETTINGS_GENERAL_INPUT_BUTTON_ALT").tag(
                                    false)
                            }
                        }
                    }

                    Spacer(minLength: 140)
                }
                .padding([.leading, .trailing, .top])

                HStack {
                    VStack {
                        HStack {
                            Text("SETTINGS_GENERAL_TITLE_IME_POSITION")
                                .font(.headline)

                            Spacer()
                        }

                        HStack {
                            Text("SETTINGS_GENERAL_IME_POS_X")
                            TextField(
                                "0-100",
                                text: $viewModel.imePosX
                            )
                            .frame(width: 50)
                            Text("%")

                            Spacer().frame(width: 30)

                            Text("SETTINGS_GENERAL_IME_POS_Y")
                            TextField(
                                "0-100",
                                text: $viewModel.imePosY
                            )
                            .frame(width: 50)
                            Text("%")

                            Spacer()
                        }

                        Text("SETTINGS_GENERAL_IME_POSITION_HINT")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 140)
                }
                .padding([.leading, .trailing, .top])

                HStack {
                    VStack {
                        HStack {
                            Text("SETTINGS_GENERAL_DISCORD_TITLE")
                                .font(.headline)
                            Spacer()
                        }

                        Text("SETTINGS_GENERAL_DISCORD_BLURB")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            Text("SETTINGS_GENERAL_DISCORD_STATUS")
                            Circle()
                                .frame(width: 8, height: 8)
                                .foregroundColor(
                                    viewModel.discordInstalled ? .green : .secondary)
                            Text(
                                viewModel.discordInstalled
                                    ? "SETTINGS_GENERAL_DISCORD_INSTALLED"
                                    : "SETTINGS_GENERAL_DISCORD_NOT_INSTALLED"
                            )
                            .foregroundColor(
                                viewModel.discordInstalled ? .green : .secondary)
                            if viewModel.discordOperating {
                                ProgressView().scaleEffect(0.7)
                            }
                            Spacer()
                        }

                        HStack {
                            Button("SETTINGS_GENERAL_DISCORD_INSTALL_BTN") {
                                viewModel.installDiscord()
                            }
                            .disabled(
                                viewModel.discordInstalled || viewModel.discordOperating)

                            Button("SETTINGS_GENERAL_DISCORD_UNINSTALL_BTN") {
                                viewModel.uninstallDiscord()
                            }
                            .disabled(
                                !viewModel.discordInstalled || viewModel.discordOperating)

                            Spacer()
                        }
                    }
                    Spacer(minLength: 140)
                }
                .padding([.leading, .trailing, .top])

                Spacer()
            }
            Image(nsImage: NSImage(named: "PrefsGeneral") ?? NSImage())
                .padding()
        }
    }
}

struct SettingsGeneralTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsGeneralTabView()
    }
}

extension SettingsGeneralTabView {
    @MainActor class ViewModel: ObservableObject {
        @Published var language: FFXIVLanguage = .english {
            didSet { Settings.language = language }
        }

        @Published var platform: FFXIVPlatform = .windows {
            didSet { Settings.platform = platform }
        }

        @Published var freeTrial: Bool = Settings.freeTrial {
            didSet { Settings.freeTrial = freeTrial }
        }

        @Published var limitDownloadEnabled: Bool = HTTPClient.maxSpeed > 0 {
            didSet { updateHTTPMaxSpeed() }
        }

        @Published var limitDownloadSpeed: String = .init(HTTPClient.maxSpeed) {
            didSet { updateHTTPMaxSpeed() }
        }

        @Published var leftOptionIsAlt: Bool = Wine.leftOptionIsAlt {
            didSet { Wine.leftOptionIsAlt = leftOptionIsAlt }
        }

        @Published var rightOptionIsAlt: Bool = Wine.rightOptionIsAlt {
            didSet { Wine.rightOptionIsAlt = rightOptionIsAlt }
        }

        @Published var leftCommandIsCtrl: Bool = Wine.leftCommandIsCtrl {
            didSet { Wine.leftCommandIsCtrl = leftCommandIsCtrl }
        }

        @Published var rightCommandIsCtrl: Bool = Wine.rightCommandIsCtrl {
            didSet { Wine.rightCommandIsCtrl = rightCommandIsCtrl }
        }

        @Published var imePosX: String = String(Settings.imePosX) {
            didSet { updateImePosX() }
        }

        @Published var imePosY: String = String(Settings.imePosY) {
            didSet { updateImePosY() }
        }

        @Published var discordInstalled: Bool = DiscordBridge.isInstalled
        @Published var discordOperating: Bool = false

        func installDiscord() {
            discordOperating = true
            Task {
                await DiscordBridge.install()
                await MainActor.run {
                    discordInstalled = DiscordBridge.isInstalled
                    discordOperating = false
                }
            }
        }

        func uninstallDiscord() {
            discordOperating = true
            Task {
                await DiscordBridge.uninstall()
                await MainActor.run {
                    discordInstalled = DiscordBridge.isInstalled
                    discordOperating = false
                }
            }
        }

        private func updateImePosX() {
            if let value = Int(imePosX), (0...100).contains(value) {
                Settings.imePosX = value
            }
        }

        private func updateImePosY() {
            if let value = Int(imePosY), (0...100).contains(value) {
                Settings.imePosY = value
            }
        }

        private func updateHTTPMaxSpeed() {
            HTTPClient.maxSpeed =
                limitDownloadEnabled ? Double(limitDownloadSpeed) ?? 0.0 : 0.0
        }
    }
}

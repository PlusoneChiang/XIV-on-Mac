//
//  SettingsPluginsTabView.swift
//  XIV on Mac
//
//  Created by Chris Backas on 1/14/23.
//

import SwiftUI
import XIVLauncher

struct SettingsPluginsTabView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        VStack {
            Text("SETTINGS_PLUGINS_WHAT_IS_DALAMUD_BLURB")
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding([.top, .leading, .trailing])
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Toggle(isOn: $viewModel.dalamudEnabled) {
                    Text("SETTINGS_PLUGINS_DALAMUD_ENABLE")
                }
                .padding(.leading)
                Spacer()
                Toggle(isOn: $viewModel.dalamudEntryPoint) {
                    Text("SETTINGS_PLUGINS_DALAMUD_ENTRYPOINT")
                }
                .padding(.leading)
                .disabled(!viewModel.dalamudEnabled)
                Spacer()
            }
            if !viewModel.dalamudEntryPoint {
                Text("SETTINGS_PLUGINS_DALAMUD_DELAY_BLURB")
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .padding([.top, .leading, .trailing])
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("SETTINGS_PLUGINS_DALAMUD_DELAY_LABEL")
                        .padding([.leading])
                    TextField("0", text: $viewModel.dalamudDelay)
                        .frame(minWidth: 50)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("SETTINGS_PLUGINS_DALAMUD_DELAY_UNITS")
                    Spacer()
                }
            }
            Divider().padding([.top])
            VStack(alignment: .leading, spacing: 8) {
                Text("SETTINGS_PLUGINS_DALAMUD_BRANCH_BLURB")
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .padding([.top, .trailing])
                    .frame(maxWidth: .infinity, alignment: .leading)

                // TC Region: 顯示自訂 Dalamud 版本資訊
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("Dalamud 版本:")
                            .font(.footnote)
                            .fontWeight(.medium)
                        if viewModel.isFetching {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if let version = viewModel.customDalamudVersion {
                            Text(version.displayName)
                                .font(.footnote)
                        }
                    }
                    if let version = viewModel.customDalamudVersion {
                        HStack(spacing: 12) {
                            Text("組件版本: \(version.assemblyVersion ?? "N/A")")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Text("支援遊戲版本: \(version.supportedGameVer ?? "N/A")")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        if let runtime = version.runtimeVersion {
                            Text(".NET Runtime: \(runtime)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let error = viewModel.fetchError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)
            Spacer()
        }
        .onAppear {
            // 只在 Dalamud 啟用時才檢查版本
            if viewModel.dalamudEnabled {
                viewModel.fetchCustomDalamudVersion()
            }
        }
        .onChange(of: viewModel.dalamudEnabled) { enabled in
            // 當 Dalamud 被啟用時，檢查版本
            if enabled && viewModel.customDalamudVersion == nil {
                viewModel.fetchCustomDalamudVersion()
            }
        }
    }
}

struct SettingsPluginsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPluginsTabView()
    }
}

// TC Region: 自訂 Dalamud 版本資訊結構
private struct CustomDalamudVersion: Codable {
    let assemblyVersion: String?
    let supportedGameVer: String?
    let runtimeRequired: Bool?
    let runtimeVersion: String?
    let downloadUrl: String?
    let track: String?
    let displayName: String
    let key: String?
}

extension SettingsPluginsTabView {
    @MainActor class ViewModel: ObservableObject {
        @Published var dalamudEnabled: Bool = Settings.dalamudEnabled {
            didSet { Settings.dalamudEnabled = dalamudEnabled }
        }

        @Published var dalamudEntryPoint: Bool = Settings.dalamudEntryPoint {
            didSet { Settings.dalamudEntryPoint = dalamudEntryPoint }
        }

        @Published var dalamudDelay: String = .init(Settings.injectionDelay) {
            didSet { Settings.injectionDelay = Double(dalamudDelay) ?? 0 }
        }

        // TC Region: 自訂 Dalamud 版本
        @Published fileprivate var customDalamudVersion: CustomDalamudVersion? = nil
        @Published var isFetching: Bool = false
        @Published var fetchError: String? = nil

        // TC Region: 自訂 Dalamud 版本來源 URL
        private static let customDalamudVersionURL = "https://plusonechiang.github.io/XIV-on-Mac-in-TC/dalamud_version.json"

        func fetchCustomDalamudVersion() {
            Task { await fetchCustomDalamudVersionAsync() }
        }

        private func fetchCustomDalamudVersionAsync() async {
            await MainActor.run {
                self.isFetching = true
                self.fetchError = nil
            }
            defer {
                Task { @MainActor in self.isFetching = false }
            }

            guard let url = URL(string: Self.customDalamudVersionURL) else {
                await MainActor.run {
                    self.fetchError = NSLocalizedString("SETTINGS_PLUGINS_DALAMUD_FETCH_ERROR_INVALID_URL", comment: "")
                }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    await MainActor.run {
                        self.fetchError = String(format: NSLocalizedString("SETTINGS_PLUGINS_DALAMUD_FETCH_ERROR_HTTP", comment: ""), http.statusCode)
                    }
                    return
                }

                let decoder = JSONDecoder()
                let version = try decoder.decode(CustomDalamudVersion.self, from: data)

                await MainActor.run {
                    self.customDalamudVersion = version
                }
            } catch {
                await MainActor.run {
                    self.fetchError = String(format: NSLocalizedString("SETTINGS_PLUGINS_DALAMUD_FETCH_ERROR_GENERIC", comment: ""), error.localizedDescription)
                }
            }
        }
    }
}

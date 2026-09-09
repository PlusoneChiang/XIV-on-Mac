//
//  SettingsGraphicsTabView.swift
//  XIV on Mac
//
//  Created by Chris Backas on 1/14/23.
//

import SwiftUI

struct SettingsGraphicsTabView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                Toggle(isOn: .constant(Settings.dxmtEnabled)) {
                    Text("DXMT_ENABLED")
                }
                .disabled(true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: $viewModel.metalFxSpatialEnabled) {
                    Text("METALFX_SPATIAL_ENABLED")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GridRow {
                HStack {
                    Toggle(isOn: $viewModel.fpsLimited) {
                        Text("SETTINGS_FPS_LIMIT")
                    }
                    TextField(
                        "SETTINGS_FPS_LIMIT_PLACEHOLDER",
                        text: $viewModel.fpsLimit
                    )
                    .frame(width: 50)
                    .disabled(!viewModel.fpsLimited)
                    Text("SETTINGS_FPS_LIMIT_UNITS")
                }

                Toggle(isOn: $viewModel.metal3Hud) {
                    Text("SETTINGS_GRAPHICS_METAL3_HUD")
                }
            }

            Toggle(isOn: $viewModel.macScaling) {
                Text("SETTINGS_GRAPHICS_RETINA")
            }
            .gridCellColumns(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            Image(nsImage: NSImage(named: "PrefsGraphics") ?? NSImage())
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .padding()
    }
}

struct SettingsGraphicsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsGraphicsTabView()
    }
}

extension SettingsGraphicsTabView {
    @MainActor class ViewModel: ObservableObject {
        @Published var metalFxSpatialEnabled: Bool = Settings
            .metalFxSpatialEnabled
        {
            didSet { Settings.metalFxSpatialEnabled = metalFxSpatialEnabled }
        }

        @Published var fpsLimited: Bool = Settings.maxFramerate != 0 {
            didSet { updateFpsLimit() }
        }

        @Published var fpsLimit: String = String(Settings.maxFramerate) {
            didSet { updateFpsLimit() }
        }

        @Published var metal3Hud: Bool = Settings.metal3PerformanceOverlay {
            didSet { Settings.metal3PerformanceOverlay = metal3Hud }
        }

        @Published var macScaling: Bool = !Wine.retina {
            didSet {
                if !macScaling {
                    // User is turning OFF scaling mode (enabling Retina mode)
                    // This might be a bad idea...
                    let alert: NSAlert = .init()
                    alert.messageText = NSLocalizedString(
                        "RETINA_WARNING", comment: "")
                    alert.informativeText = NSLocalizedString(
                        "RETINA_WARNING_INFORMATIVE", comment: "")
                    alert.alertStyle = .warning
                    alert.addButton(
                        withTitle: NSLocalizedString(
                            "RETINA_ENABLE_BUTTON", comment: ""))
                    alert.addButton(
                        withTitle: NSLocalizedString(
                            "BUTTON_CANCEL", comment: ""))
                    let result = alert.runModal()
                    guard result == .alertFirstButtonReturn else {
                        DispatchQueue.main.async {
                            // Change it back
                            self.macScaling = true
                        }
                        return
                    }
                }
                Wine.retina = !macScaling
            }
        }

        private func updateFpsLimit() {
            Settings.maxFramerate = fpsLimited ? UInt32(fpsLimit) ?? 0 : 0
        }
    }
}

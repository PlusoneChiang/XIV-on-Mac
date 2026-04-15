//
//  SocialIntegration.swift
//  XIV on Mac
//
//  Created by Ming Quah on 29/12/2021.
//

import Foundation
import OSLog

enum DiscordBridge {
    private static let logger = Logger(subsystem: "XIV on Mac", category: "DiscordBridge")

    // xbridge Windows service (Rust-based Discord RPC bridge)
    private static let downloadURL = URL(
        string: "https://github.com/PlusoneChiang/xbridge/releases/latest/download/xbridge.exe")!

    // Local download cache
    private static var localPath: URL {
        Util.applicationSupport
            .appendingPathComponent("discord-rpc")
            .appendingPathComponent("xbridge.exe")
    }

    // Installed path inside the Wine prefix
    private static var installedPath: URL {
        Wine.prefix.appendingPathComponent("drive_c/windows/xbridge.exe")
    }

    // Registry key for IPC socket path (read by xbridge Windows service on macOS)
    private static let ipcRegistryKey =
        #"HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"#

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPath.path)
    }

    // Write DISCORD_IPC_PATH to the Wine registry.
    // Called before each game launch so xbridge can locate the Discord Unix socket.
    // macOS TMPDIR is session-specific and must be refreshed via registry because
    // Windows services cannot inherit POSIX environment variables.
    static func refreshIpcPath() {
        guard isInstalled else { return }
        let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp/"
        logger.info("[xbridge] refreshing DISCORD_IPC_PATH: \(tmpdir)")
        Wine.addReg(key: ipcRegistryKey, value: "DISCORD_IPC_PATH", data: tmpdir)
    }

    static func install() async {
        if !FileManager.default.fileExists(atPath: localPath.path) {
            logger.info("[xbridge] downloading xbridge.exe...")
            do {
                try await download()
            } catch {
                logger.error("[xbridge] download failed: \(error.localizedDescription)")
                return
            }
        }
        // Write IPC path before install so xbridge finds it at first start
        let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp/"
        Wine.addReg(key: ipcRegistryKey, value: "DISCORD_IPC_PATH", data: tmpdir)

        if !isInstalled {
            logger.info("[xbridge] installing service in Wine prefix...")
            Wine.launch(command: "\"\(localPath.path)\" --install", blocking: true)
            logger.info("[xbridge] install complete.")
        } else {
            logger.info("[xbridge] already installed in prefix, skipping install.")
        }
    }

    static func uninstall() async {
        guard isInstalled else {
            logger.info("[xbridge] not installed, nothing to uninstall.")
            return
        }
        logger.info("[xbridge] uninstalling xbridge service...")
        Wine.launch(command: "\"\(installedPath.path)\" --uninstall", blocking: true)
        logger.info("[xbridge] uninstall complete.")
    }

    private static func download() async throws {
        let dir = localPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: nil)
        let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        try? FileManager.default.removeItem(at: localPath)
        try FileManager.default.moveItem(at: tempURL, to: localPath)
        logger.info("[xbridge] downloaded to \(localPath.path)")
    }
}

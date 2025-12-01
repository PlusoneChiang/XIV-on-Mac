//
//  GraphicsInstaller.swift
//  XIV on Mac
//
//  Created by Marc-Aurel Zent on 25.07.24.
//

import Foundation

enum GraphicsInstaller {
    private static let system32 = Wine.prefix.appendingPathComponent(
        "drive_c/windows/system32")
    private static let d3dcompilerPath = Bundle.main.url(
        forResource: "d3dcompiler", withExtension: nil, subdirectory: "")!
    private static let d3dcompilerDll = d3dcompilerPath.appendingPathComponent("d3dcompiler_47.dll")

    static func install(dll: URL) {
        Log.debug("[GraphicsInstaller] install start \(dll.lastPathComponent) from \(dll.path)")
        let dllName = dll.lastPathComponent
        Util.make(dir: system32)
        let fm = FileManager.default
        let winDllPath = system32.appendingPathComponent(dllName).path
        let oldDllPath = winDllPath + ".old"

        let sourceAttrs = try? fm.attributesOfItem(atPath: dll.path)
        let destAttrs = try? fm.attributesOfItem(atPath: winDllPath)
        Log.debug("[GraphicsInstaller] source size \(sourceAttrs?[.size] ?? -1) dest exists \(fm.fileExists(atPath: winDllPath)) size \(destAttrs?[.size] ?? -1)")

        if !fm.contentsEqual(atPath: winDllPath, andPath: dll.path) {
            if fm.fileExists(atPath: winDllPath) {
                do {
                    if fm.fileExists(atPath: oldDllPath) {
                        try fm.removeItem(atPath: oldDllPath)
                    }
                    try fm.moveItem(atPath: winDllPath, toPath: oldDllPath)
                    Log.debug("[GraphicsInstaller] moved existing \(dllName) to \(oldDllPath)")
                } catch {
                    Log.error(
                        "[GraphicsInstaller] error renaming wine dx dll \(winDllPath)\n\(error)"
                    )
                }
            }
            do {
                try fm.copyItem(atPath: dll.path, toPath: winDllPath)
                Log.information("[GraphicsInstaller] copied \(dllName) to \(winDllPath)")
            } catch {
                Log.error("[GraphicsInstaller] error copying dx dll \(error)")
            }
        } else {
            Log.debug("[GraphicsInstaller] \(dllName) already up to date at \(winDllPath)")
        }
    }

    static func restore(dllName: String) {
        let fm = FileManager.default
        let winDllPath = system32.appendingPathComponent(dllName).path
        let oldDllPath = winDllPath + ".old"

        Log.debug("[GraphicsInstaller] restore \(dllName) oldExists:\(fm.fileExists(atPath: oldDllPath)) newExists:\(fm.fileExists(atPath: winDllPath))")
        if fm.fileExists(atPath: oldDllPath) {
            do {
                try fm.removeItem(atPath: winDllPath)
                try fm.moveItem(atPath: oldDllPath, toPath: winDllPath)
                Log.information(
                    "[GraphicsInstaller] restored old wine dx dll \(oldDllPath) to \(winDllPath)"
                )
            } catch {
                Log.error(
                    "[GraphicsInstaller] error restoring old wine dx dll \(oldDllPath)\n\(error)"
                )
            }
        }
    }

    static func ensureBackend() {
        Log.information("[GraphicsInstaller] ensureBackend start dxmtEnabled:\(Settings.dxmtEnabled)")
        Log.debug("[GraphicsInstaller] installing d3dcompiler from \(d3dcompilerDll.path)")
        install(dll: d3dcompilerDll)
        if Settings.dxmtEnabled {
            Log.information("[GraphicsInstaller] selecting DXMT backend")
            Dxmt.install()
        } else {
            Log.information("[GraphicsInstaller] selecting DXVK backend")
            Dxvk.install()
            Dxmt.uninstall()
        }
        Log.information("[GraphicsInstaller] ensureBackend end")
    }
}

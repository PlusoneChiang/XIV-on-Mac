//
//  LoginPageSchemeHandler.swift
//  XIV on Mac
//
//  自訂 URL Scheme Handler：處理 ffxivlogin:// 協議
//  用於載入本地登入頁面資源
//

import Foundation
import WebKit
import Cocoa

class LoginPageSchemeHandler: NSObject, WKURLSchemeHandler {
    
    // MARK: - Constants
    
    private enum Constants {
        static let scheme = "ffxivlogin"
        static let resourcesPath = "Resources"
    }
    
    // MARK: - WKURLSchemeHandler
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == Constants.scheme else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        
        // 解析路徑（支援 ffxivlogin://user.ffxiv.com.tw/login_page.html 格式）
        // url.path 會是 "/login_page.html"，去除開頭的 "/"
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // 如果路徑為空，記錄完整 URL 資訊以便除錯
        if path.isEmpty {
            Log.error("[LoginPageSchemeHandler] Empty path from URL: \(url.absoluteString)")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        
        Log.information("[LoginPageSchemeHandler] Loading resource: \(path) from URL: \(url.absoluteString)")
        
        // 分離檔名和副檔名
        let fileName = (path as NSString).deletingPathExtension
        let fileExtension = (path as NSString).pathExtension
        
        // 從 Bundle 主資源目錄載入檔案
        let resourceURL: URL?
        if !fileExtension.isEmpty {
            resourceURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension)
        } else {
            resourceURL = Bundle.main.url(forResource: path, withExtension: nil)
        }
        
        guard let resourceURL = resourceURL else {
            Log.error("[LoginPageSchemeHandler] Resource not found: \(path) (fileName: \(fileName), extension: \(fileExtension))")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        
        do {
            // 讀取檔案內容
            let data = try Data(contentsOf: resourceURL)
            
            // 確定 MIME 類型
            let mimeType = getMimeType(for: path)
            
            // 建立回應
            let response = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            
            // 發送回應
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            
            Log.information("[LoginPageSchemeHandler] Resource loaded successfully: \(path)")
            
        } catch {
            Log.error("[LoginPageSchemeHandler] Failed to load resource: \(error.localizedDescription)")
            urlSchemeTask.didFailWithError(error)
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 取消請求（通常不需要特別處理）
        Log.information("[LoginPageSchemeHandler] Task stopped")
    }
    
    // MARK: - Helper
    
    /// 根據檔案副檔名確定 MIME 類型
    private func getMimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "html":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "application/javascript"
        case "json":
            return "application/json"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "svg":
            return "image/svg+xml"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        default:
            return "application/octet-stream"
        }
    }
}

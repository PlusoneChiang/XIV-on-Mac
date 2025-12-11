//
//  LoginPageManager.swift
//  XIV on Mac
//
//  WebView 登入頁面管理器
//  負責 Swift 與 JavaScript 之間的橋接通訊
//

import Foundation
import WebKit
import Cocoa

/// 登入頁面訊息類型
enum LoginPageMessage: String {
    case requestAccounts        // JS → Swift: 請求已儲存帳號列表
    case requestPassword        // JS → Swift: 請求指定帳號的密碼
    case checkOTPKey           // JS → Swift: 檢查帳號是否有已儲存的 OTP 金鑰
    case saveOTPKey            // JS → Swift: 儲存 OTP 金鑰
    case requestOTP            // JS → Swift: 請求生成 OTP
    case executeLogin          // JS → Swift: 執行登入
    case recaptchaError        // JS → Swift: reCAPTCHA 獲取失敗
}

/// 登入頁面管理器
class LoginPageManager: NSObject {
    // MARK: - Properties
    
    weak var webView: WKWebView?
    weak var delegate: LoginPageManagerDelegate?
    
    private var currentAccount: String?
    
    // MARK: - Initialization
    
    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        setupMessageHandlers()
    }
    
    deinit {
        removeMessageHandlers()
    }
    
    // MARK: - Message Handler Setup
    
    private func setupMessageHandlers() {
        guard let webView = webView else { return }
        
        let contentController = webView.configuration.userContentController
        
        // 註冊所有訊息處理器
        for message in [
            LoginPageMessage.requestAccounts,
            .requestPassword,
            .checkOTPKey,
            .saveOTPKey,
            .requestOTP,
            .executeLogin,
            .recaptchaError
        ] {
            contentController.add(self, name: message.rawValue)
        }
        
        Log.information("[LoginPageManager] Message handlers registered")
    }
    
    private func removeMessageHandlers() {
        guard let webView = webView else { return }
        
        let contentController = webView.configuration.userContentController
        
        for message in [
            LoginPageMessage.requestAccounts,
            .requestPassword,
            .checkOTPKey,
            .saveOTPKey,
            .requestOTP,
            .executeLogin,
            .recaptchaError
        ] {
            contentController.removeScriptMessageHandler(forName: message.rawValue)
        }
    }
    
    // MARK: - Swift → JavaScript 通訊
    
    /// 發送已儲存的帳號列表到 JS
    func sendAccounts(_ accounts: [String]) {
        let accountsJSON = accounts.map { "\"\($0)\"" }.joined(separator: ",")
        let script = "window.loginForm.receiveAccounts([\(accountsJSON)]);"
        executeJavaScript(script)
        Log.information("[LoginPageManager] Sent \(accounts.count) accounts to JS")
    }
    
    /// 發送密碼到 JS
    func sendPassword(_ password: String) {
        let escapedPassword = password.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "window.loginForm.receivePassword(\"\(escapedPassword)\");"
        executeJavaScript(script)
        Log.information("[LoginPageManager] Sent password to JS")
    }
    
    /// 通知 JS 該帳號有已儲存的 OTP 金鑰
    func notifyExistingOTPKey() {
        let script = "window.loginForm.onExistingOTPKey();"
        executeJavaScript(script)
        Log.information("[LoginPageManager] Notified JS: existing OTP key")
    }
    
    /// 通知 JS 該帳號沒有已儲存的 OTP 金鑰
    func notifyNoOTPKey() {
        let script = "window.loginForm.onNoOTPKey();"
        executeJavaScript(script)
        Log.information("[LoginPageManager] Notified JS: no OTP key")
    }
    
    /// 發送生成的 OTP 到 JS
    func sendOTP(_ otp: String) {
        let script = "window.loginForm.receiveOTP(\"\(otp)\");"
        executeJavaScript(script)
        Log.information("[LoginPageManager] Sent OTP to JS")
    }
    
    /// 重置登入按鈕狀態
    func resetLoginButton() {
        let script = "window.loginForm.resetLoginButton();"
        executeJavaScript(script)
        Log.information("[LoginPageManager] Reset login button")
    }
    
    /// 通知登入成功
    func notifyLoginSuccess() {
        let script = "window.loginForm.onLoginSuccess();"
        executeJavaScript(script)
        Log.information("[LoginPageManager] Notified login success")
    }
    
    // MARK: - Helper
    
    private func executeJavaScript(_ script: String) {
        webView?.evaluateJavaScript(script) { result, error in
            if let error = error {
                Log.error("[LoginPageManager] JavaScript error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - WKScriptMessageHandler

extension LoginPageManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let messageType = LoginPageMessage(rawValue: message.name) else {
            Log.warning("[LoginPageManager] Unknown message: \(message.name)")
            return
        }
        
        Log.information("[LoginPageManager] Received message: \(messageType.rawValue)")
        
        switch messageType {
        case .requestAccounts:
            handleRequestAccounts()
            
        case .requestPassword:
            if let account = message.body as? String {
                handleRequestPassword(account: account)
            }
            
        case .checkOTPKey:
            if let account = message.body as? String {
                handleCheckOTPKey(account: account)
            }
            
        case .saveOTPKey:
            if let key = message.body as? String {
                handleSaveOTPKey(key: key)
            }
            
        case .requestOTP:
            handleRequestOTP()
            
        case .executeLogin:
            if let credentials = message.body as? [String: String] {
                handleExecuteLogin(credentials: credentials)
            }
            
        case .recaptchaError:
            if let errorMessage = message.body as? String {
                handleRecaptchaError(message: errorMessage)
            }
        }
    }
    
    // MARK: - Message Handlers
    
    private func handleRequestAccounts() {
        delegate?.loginPageManagerRequestAccounts(self)
    }
    
    private func handleRequestPassword(account: String) {
        self.currentAccount = account
        delegate?.loginPageManager(self, requestPasswordForAccount: account)
    }
    
    private func handleCheckOTPKey(account: String) {
        self.currentAccount = account
        delegate?.loginPageManager(self, checkOTPKeyForAccount: account)
    }
    
    private func handleSaveOTPKey(key: String) {
        guard let account = currentAccount else {
            Log.error("[LoginPageManager] No current account when saving OTP key")
            return
        }
        delegate?.loginPageManager(self, saveOTPKey: key, forAccount: account)
    }
    
    private func handleRequestOTP() {
        guard let account = currentAccount else {
            Log.error("[LoginPageManager] No current account when requesting OTP")
            return
        }
        delegate?.loginPageManager(self, requestOTPForAccount: account)
    }
    
    private func handleExecuteLogin(credentials: [String: String]) {
        guard let username = credentials["username"],
              let password = credentials["password"],
              let recaptchaToken = credentials["recaptchaToken"] else {
            Log.error("[LoginPageManager] Invalid credentials format")
            return
        }
        
        let otp = credentials["otp"] ?? ""
        
        delegate?.loginPageManager(self,
                                  executeLoginWithUsername: username,
                                  password: password,
                                  otp: otp,
                                  recaptchaToken: recaptchaToken)
    }
    
    private func handleRecaptchaError(message: String) {
        delegate?.loginPageManager(self, recaptchaErrorOccurred: message)
    }
}

// MARK: - Delegate Protocol

protocol LoginPageManagerDelegate: AnyObject {
    /// 請求已儲存的帳號列表
    func loginPageManagerRequestAccounts(_ manager: LoginPageManager)
    
    /// 請求指定帳號的密碼
    func loginPageManager(_ manager: LoginPageManager, requestPasswordForAccount account: String)
    
    /// 檢查帳號是否有已儲存的 OTP 金鑰
    func loginPageManager(_ manager: LoginPageManager, checkOTPKeyForAccount account: String)
    
    /// 儲存 OTP 金鑰
    func loginPageManager(_ manager: LoginPageManager, saveOTPKey key: String, forAccount account: String)
    
    /// 請求生成 OTP
    func loginPageManager(_ manager: LoginPageManager, requestOTPForAccount account: String)
    
    /// 執行登入
    func loginPageManager(_ manager: LoginPageManager,
                         executeLoginWithUsername username: String,
                         password: String,
                         otp: String,
                         recaptchaToken: String)
    
    /// reCAPTCHA 錯誤發生
    func loginPageManager(_ manager: LoginPageManager, recaptchaErrorOccurred message: String)
}

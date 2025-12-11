//
//  LaunchController.swift
//  XIV on Mac
//
//  Created by Marc-Aurel Zent on 02.02.22.
//

import Cocoa
import WebKit
import XIVLauncher

// 自定義視圖：上方點擊穿透，下方100px可互動
class ClickThroughView: NSView {
    var interactiveHeight: CGFloat = 100 // 下方100px可互動
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 計算點擊位置是否在下方100px範圍內
        if point.y <= interactiveHeight {
            // 下方100px：正常處理點擊（遞迴查找子視圖）
            return super.hitTest(point)
        } else {
            // 上方區域：點擊穿透（返回 nil 讓點擊事件穿透到下層視圖）
            return nil
        }
    }
}

// reCAPTCHA 自定義 URL Scheme Handler
class RecaptchaSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "recaptcha",
              let path = Bundle.main.path(forResource: "recaptcha_page", ofType: "html"),
              let htmlContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "RecaptchaSchemeHandler", code: -1))
            return
        }
        
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(htmlContent.data(using: .utf8)!)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No-op
    }
}

final class RecaptchaTokenProvider: NSObject, WKScriptMessageHandler {
    static let shared = RecaptchaTokenProvider()

    // 持久化 WebView（不再銷毀）
    private var webView: WKWebView!
    
    // Token 快取機制
    private var cachedToken: String?
    private var tokenExpiryTime: Date?
    private let tokenValidDuration: TimeInterval = 110 // 110秒有效期
    
    // 請求佇列（避免並發請求）
    private var pendingCompletions: [(Result<String, Error>) -> Void] = []
    private var isFetchingToken = false
    
    // 初始化狀態
    private var isInitialized = false
    
    // WebView 容器視圖
    weak var containerView: NSView? {
        didSet {
            if let container = containerView {
                container.addSubview(webView)
                webView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    webView.topAnchor.constraint(equalTo: container.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
                ])
            }
        }
    }

    private override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "recaptchaToken")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.setURLSchemeHandler(RecaptchaSchemeHandler(), forURLScheme: "recaptcha")
        
        // 持久化資料存儲
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // 設置合理的 User-Agent
        config.applicationNameForUserAgent = "XIVLauncher/5.2.3 (Macintosh)"

        webView = WKWebView(frame: .zero, configuration: config)
        
        // 設置半透明（50% 用於可見性）
        webView.alphaValue = 0.5
        webView.wantsLayer = true
        webView.layer?.opacity = 0.5
        
        // 設置透明背景
        webView.setValue(false, forKey: "drawsBackground")
    }
    
    // 預熱方法（在應用啟動時呼叫）
    func warmup() {
        guard !isInitialized else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let url = URL(string: "recaptcha://user.ffxiv.com.tw/recaptcha_page.html") else {
                return
            }
            
            self.isInitialized = true
            self.webView.load(URLRequest(url: url))
            
            Log.information("reCAPTCHA WebView warmed up")
        }
    }

    func fetchToken(completion: @escaping (Result<String, Error>) -> Void) {
        // 檢查快取的 token 是否仍有效
        if let cached = cachedToken,
           let expiry = tokenExpiryTime,
           Date() < expiry {
            Log.information("Using cached reCAPTCHA token")
            completion(.success(cached))
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 加入等待佇列
            self.pendingCompletions.append(completion)
            
            // 如果正在取得 token，直接返回
            if self.isFetchingToken {
                Log.information("reCAPTCHA fetch already in progress, queued")
                return
            }
            
            self.isFetchingToken = true
            
            // 如果還沒初始化，先載入頁面
            if !self.isInitialized {
                guard let url = URL(string: "recaptcha://user.ffxiv.com.tw/recaptcha_page.html") else {
                    self.notifyAllCompletions(.failure(NSError(
                        domain: "RecaptchaTokenProvider",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid recaptcha URL"]
                    )))
                    return
                }
                self.isInitialized = true
                self.webView.load(URLRequest(url: url))
            } else {
                // 已經初始化，直接執行 reCAPTCHA
                self.executeRecaptcha()
            }
            
            // 設置超時機制（15秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self = self, self.isFetchingToken else { return }
                
                Log.error("reCAPTCHA token fetch timeout")
                self.notifyAllCompletions(.failure(NSError(
                    domain: "RecaptchaTokenProvider",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Token fetch timeout"]
                )))
            }
        }
    }
    
    private func executeRecaptcha() {
        // 透過 JavaScript 觸發 reCAPTCHA
        let script = "if (typeof window.triggerRecaptcha === 'function') { window.triggerRecaptcha(); }"
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error = error {
                Log.error("Failed to execute reCAPTCHA: \(error)")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "recaptchaToken" else { return }

        let token = message.body as? String ?? ""
        
        if !token.isEmpty {
            // 快取 token
            cachedToken = token
            tokenExpiryTime = Date().addingTimeInterval(tokenValidDuration)
            
            Log.information("reCAPTCHA token received and cached (length: \(token.count))")
            notifyAllCompletions(.success(token))
        } else {
            Log.error("Empty reCAPTCHA token received")
            notifyAllCompletions(.failure(NSError(
                domain: "RecaptchaTokenProvider",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Empty token received"]
            )))
        }
    }
    
    private func notifyAllCompletions(_ result: Result<String, Error>) {
        isFetchingToken = false
        
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        
        for completion in completions {
            completion(result)
        }
    }
    
    // 清除快取
    func invalidateCache() {
        cachedToken = nil
        tokenExpiryTime = nil
        Log.information("reCAPTCHA token cache invalidated")
    }
    
    // 模擬用戶互動（在獲取 token 前呼叫）
    func simulateInteraction() {
        guard isInitialized else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.webView.evaluateJavaScript("if (typeof window.simulateInteraction === 'function') { window.simulateInteraction(); }") { result, error in
                if let error = error {
                    Log.error("Failed to simulate interaction: \(error)")
                } else {
                    Log.information("User interaction simulated for reCAPTCHA")
                }
            }
        }
    }
}

class LaunchController: NSViewController, WKNavigationDelegate {
    var loginSheetWinController: NSWindowController?
    var installerWinController: NSWindowController?
    var patchWinController: NSWindowController?
    var repairWinController: NSWindowController?
    var patchController: PatchController?
    var repairController: RepairController?
    var newsTable: FrontierTableView!
    var newsWebView: WKWebView!  // 新增：WebView 覆蓋層
    var topicsTable: FrontierTableView!
    var otp: OTP?
    
    // Login Page WebView
    var loginPageWebView: WKWebView!
    var loginPageManager: LoginPageManager?
    var loginPageContainerView: NSView!

    @IBOutlet private var loginButton: NSButton!
    @IBOutlet var userField: NSTextField!
    @IBOutlet private var userMenu: NSMenu!
    @IBOutlet private var passwdField: NSTextField!
    @IBOutlet var otpField: NSTextField!
    @IBOutlet var otpCheck: NSButton!
    @IBOutlet var autoLoginCheck: NSButton!
    @IBOutlet private var scrollView: AnimatingScrollView!
    @IBOutlet private var newsView: NSScrollView!
    @IBOutlet private var topicsView: NSScrollView!
    @IBOutlet private var newsContainerView: NSView!
    @IBOutlet var discloseButton: NSButton!
    @IBOutlet private var touchBarLoginButton: NSButtonTouchBarItem!
    @IBOutlet var leftButton: NSButton!
    @IBOutlet var rightButton: NSButton!

    override func loadView() {
        super.loadView()
        update()
        NotificationCenter.default.addObserver(
            self, selector: #selector(installDone(_:)), name: .installDone,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showSideButtons(_:)), name: .bannerEnter,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(hideSideButtons(_:)), name: .bannerLeft,
            object: nil)
        userMenu.minimumWidth = 264
        newsTable = FrontierTableView(
            icon: NSImage(
                systemSymbolName: "newspaper", accessibilityDescription: nil)!)
        topicsTable = FrontierTableView(
            icon: NSImage(
                systemSymbolName: "newspaper.fill",
                accessibilityDescription: nil)!)
        newsView.documentView = newsTable.tableView
        topicsView.documentView = topicsTable.tableView
        leftButton.wantsLayer = true
        rightButton.wantsLayer = true
        setSideButtonVisibility(to: false)
        newsContainerView.isHidden = true
        newsContainerView.removeFromSuperview()

        // 移動 scrollView 向下填補新聞區域空間 (新聞區域高度124px)
        if let scrollView = self.scrollView {
            var frame = scrollView.frame
            frame.origin.y -= 124  // 向下移動124px
            frame.size.height += 124  // 增加高度124px
            scrollView.frame = frame
            // 禁用自動調整大小，完全手動控制位置
            scrollView.translatesAutoresizingMaskIntoConstraints = true
            scrollView.autoresizingMask = []
        }

        // 新增：建立 WebView 覆蓋層（但不載入網頁）
        let webViewConfiguration = WKWebViewConfiguration()
        newsWebView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        newsWebView.translatesAutoresizingMaskIntoConstraints = false
        newsWebView.navigationDelegate = self
        // 設置圓角
        newsWebView.layer?.cornerRadius = 8.0
        newsWebView.layer?.masksToBounds = true

        // 將 WebView 添加到與 scrollView 相同的父視圖
        if let parentView = scrollView.superview {
            parentView.addSubview(newsWebView)

            // 設定約束，使 WebView 覆蓋整個 scrollView
            NSLayoutConstraint.activate([
                newsWebView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                newsWebView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                newsWebView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                newsWebView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
            ])

            // 停止載入外部網頁
            // 新聞版面將由 loginPageWebView 中的 login_page.html 載入
        }
        
        // 設置 Login Page 容器
        setupLoginPageContainer()
        
        // 延遲 3 秒後預熱 reCAPTCHA（給瀏覽器更多時間建立指紋）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            RecaptchaTokenProvider.shared.warmup()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.checkBoot()
        }
        DispatchQueue.global(qos: .userInteractive).async {
            // TEMPORARILY DISABLED: News and banners loading
            // To re-enable: Uncomment the block below
            /*
            if let frontierInfo = Frontier.info {
                self.populateNews(frontierInfo)
            }
            if let frontierBanners = Frontier.banners {
                self.populateBanners(frontierBanners)
            }
            */
        }
    }

    @objc func installDone(_ notif: Notification) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.checkBoot(skipInstallCheck: true)
            DispatchQueue.main.async {
                self.doLogin()
            }
        }
    }

    @objc func hideSideButtons(_ notif: Notification) {
        setSideButtonVisibility(to: false)
    }

    @objc func showSideButtons(_ notif: Notification) {
        setSideButtonVisibility(to: true)
    }

    func setSideButtonVisibility(to: Bool) {
        let buttonAlpha = 0.4
        leftButton.layer?.backgroundColor = .black.copy(
            alpha: to ? buttonAlpha : 0.0)
        rightButton.layer?.backgroundColor = .black.copy(
            alpha: to ? buttonAlpha : 0.0)
    }

    func checkBoot(skipInstallCheck: Bool = false) {
        // TEMPORARILY DISABLED: Boot patches check
        // To re-enable: Uncomment the block below
        /*
        if let bootPatches = try? Patch.bootPatches, !bootPatches.isEmpty,
            FFXIVApp().installed || skipInstallCheck
        {
            startPatch(bootPatches)
        }
        */
        DispatchQueue.main.async {
            self.loginButton.isEnabled = true
            self.touchBarLoginButton.isEnabled = true
            if settings.autoLogin
                && NSEvent.modifierFlags.intersection(
                    .deviceIndependentFlagsMask) != .shift
            {
                self.doLogin()
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loginSheetWinController =
            storyboard?.instantiateController(withIdentifier: "LoginSheet")
            as? NSWindowController
        installerWinController =
            storyboard?.instantiateController(withIdentifier: "InstallerWindow")
            as? NSWindowController
        patchWinController =
            storyboard?.instantiateController(withIdentifier: "PatchSheet")
            as? NSWindowController
        repairWinController =
            storyboard?.instantiateController(withIdentifier: "RepairSheet")
            as? NSWindowController
        patchController =
            patchWinController!.contentViewController! as? PatchController
        repairController =
            repairWinController!.contentViewController! as? RepairController
    }

    private func populateNews(_ info: Frontier.Info) {
        DispatchQueue.main.async {
            self.topicsTable.add(items: info.topics)
            self.newsTable.add(items: info.pinned + info.news)
        }
    }

    private func populateBanners(_ banners: [Frontier.BannerRoot.Banner]) {
        DispatchQueue.main.async {
            self.scrollView.banners = banners
        }
    }

    private func update() {
        autoLoginCheck.state = Settings.autoLogin ? .on : .off
        userField.stringValue = Settings.credentials?.username ?? ""
        passwdField.stringValue = Settings.credentials?.password ?? ""
        setupOTP()
    }

    @objc func update(_ sender: userMenuItem) {
        userField.stringValue = sender.credentials.username
        passwdField.stringValue = sender.credentials.password
        setupOTP()
    }

    @IBAction func showAccounts(_ sender: Any) {
        userMenu.items = []
        let accounts = LoginCredentials.accounts
        for account in accounts {
            let item = userMenuItem(
                title: account.username, action: #selector(update(_:)),
                keyEquivalent: "")
            item.credentials = account
            userMenu.items += [item]
        }
        userMenu.popUp(
            positioning: userMenu.item(at: 0), at: NSPoint(x: 0, y: 29),
            in: userField)
    }

    @IBAction func autoLoginStateChange(_ sender: NSButton) {
        Settings.autoLogin = sender.state == .on

        if Settings.autoLogin {
            let alert: NSAlert = .init()
            alert.messageText = NSLocalizedString(
                "AUTOLOGIN_MESSAGE", comment: "")
            alert.informativeText = NSLocalizedString(
                "AUTOLOGIN_INFORMATIVE", comment: "")
            alert.alertStyle = .informational
            alert.addButton(
                withTitle: NSLocalizedString("BUTTON_OK", comment: ""))

            alert.runModal()
        }
    }

    @IBAction func doLogin(_ sender: Any) {
        doLogin()
    }

    @IBAction func doRepair(_ sender: Any) {
        doLogin(repair: true)
    }

    @IBAction func scrollLeft(_ sender: NSButton) {
        scrollView.scrollLeft()
    }

    @IBAction func scrollRight(_ sender: NSButton) {
        scrollView.scrollRight()
    }
    
    private func setupLoginPageContainer() {
        // 創建 WKWebViewConfiguration
        let config = WKWebViewConfiguration()
        
        // 設置內容控制器
        let contentController = WKUserContentController()
        config.userContentController = contentController
        
        // 註冊自訂 URL Scheme Handler
        config.setURLSchemeHandler(LoginPageSchemeHandler(), forURLScheme: "ffxivlogin")
        
        // 允許 JavaScript
        config.preferences.javaScriptEnabled = true
        
        // 建立 WebView
        loginPageWebView = WKWebView(frame: .zero, configuration: config)
        loginPageWebView.translatesAutoresizingMaskIntoConstraints = false
        loginPageWebView.navigationDelegate = self
        
        // 設置透明背景
        loginPageWebView.setValue(false, forKey: "drawsBackground")
        
        // 啟用檢查器以便調試
        if #available(macOS 13.3, *) {
            loginPageWebView.isInspectable = true
        }
        
        // 建立容器視圖
        loginPageContainerView = NSView(frame: .zero)
        loginPageContainerView.translatesAutoresizingMaskIntoConstraints = false
        loginPageContainerView.wantsLayer = true
        
        // 加入 WebView 到容器
        loginPageContainerView.addSubview(loginPageWebView)
        
        // 加入容器到主視圖（與 scrollView 同一層）
        if let scrollViewParent = scrollView.superview {
            scrollViewParent.addSubview(loginPageContainerView)
        } else {
            view.addSubview(loginPageContainerView)
        }
        
        // 設置約束：嵌入到內容區域
        NSLayoutConstraint.activate([
            // 容器：左右貼齊父視圖
            loginPageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loginPageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // 頂部固定在視圖頂部，加上標題列高度偏移（28px）
            loginPageContainerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            loginPageContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // WebView 填滿容器
            loginPageWebView.leadingAnchor.constraint(equalTo: loginPageContainerView.leadingAnchor),
            loginPageWebView.trailingAnchor.constraint(equalTo: loginPageContainerView.trailingAnchor),
            loginPageWebView.topAnchor.constraint(equalTo: loginPageContainerView.topAnchor),
            loginPageWebView.bottomAnchor.constraint(equalTo: loginPageContainerView.bottomAnchor)
        ])
        
        // 建立 LoginPageManager
        loginPageManager = LoginPageManager(webView: loginPageWebView)
        loginPageManager?.delegate = self
        
        // 載入登入頁面
        if let url = URL(string: "ffxivlogin://user.ffxiv.com.tw/login_page.html") {
            let request = URLRequest(url: url)
            loginPageWebView.load(request)
            Log.information("[LaunchController] Login page WebView loading: \(url.absoluteString)")
        } else {
            Log.error("[LaunchController] Failed to create login page URL")
        }
    }

    func problemConfigurationCheck() -> Bool {
        if FirstAidModel().cfgCheckSevereProblems() {
            let appDelegate = NSApplication.shared.delegate as! AppDelegate
            appDelegate.openFirstAid(self)
            return true
        }
        return false
    }

    func doLogin(repair: Bool = false) {
        // Check for show stopping problems
        if problemConfigurationCheck() {
            return
        }
        
        // 在獲取 token 前模擬用戶互動（讓 reCAPTCHA 記錄點擊行為）
        RecaptchaTokenProvider.shared.simulateInteraction()
        
        view.window?.beginSheet(loginSheetWinController!.window!)
        Settings.credentials = LoginCredentials(
            username: userField.stringValue, password: passwdField.stringValue,
            oneTimePassword: otpField.stringValue)
        RecaptchaTokenProvider.shared.fetchToken { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(token):
                Log.information("Recaptcha token obtained (length: \(token.count))")
                self.executeLogin(repair: repair, recaptchaToken: token)
                
            case let .failure(error):
                DispatchQueue.main.async {
                    self.loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(
                        withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = NSLocalizedString(
                        "LOGIN_RECAPTCHA_FAILED", comment: "")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func executeLogin(repair: Bool, recaptchaToken: String) {
        DispatchQueue.global(qos: .default).async {
            do {
                guard FFXIVApp().installed else {
                    throw FFXIVLoginError.noInstall
                }
                // Ensure graphics backend is installed before starting the game
                GraphicsInstaller.ensureBackend()
                DispatchQueue.global(qos: .userInitiated).async {
                    DiscordBridge.setPresence()
                }
                // TC Region: maintenance checks disabled
                // if Frontier.loginMaintenance {
                //     throw FFXIVLoginError.maintenance
                // }
                let loginResult = try LoginResult(repair, recaptchaToken: recaptchaToken)
                guard loginResult.state != .NoService else {
                    throw FFXIVLoginError.notPlayable
                }
                guard loginResult.state != .NoTerms else {
                    Wine.launch(command: "\"\(FFXIVApp().bootExe64URL.path)\"")
                    throw FFXIVLoginError.noTerms
                }
                if repair {
                    DispatchQueue.main.async { [self] in
                        loginSheetWinController?.window?.close()
                        view.window?.beginSheet(repairWinController!.window!)
                        repairController?.repair(loginResult)
                    }
                    return
                }
                if !(loginResult.pendingPatches?.isEmpty ?? true) {
                    DispatchQueue.main.async { [self] in
                        loginSheetWinController?.window?.close()
                    }
                    self.startPatch(loginResult.pendingPatches!)
                    DispatchQueue.main.async { [self] in
                        view.window?.beginSheet(
                            loginSheetWinController!.window!)
                    }
                }
                // TC Region: maintenance checks disabled
                // if Frontier.gameMaintenance {
                //     throw FFXIVLoginError.maintenance
                // }
                // NotificationCenter.default.post(
                //     name: .loginInfo, object: nil,
                //     userInfo: [Notification.status.info: "Updating Dalamud"])
                // TC Temporarily set dalamudInstallState to .ok
                let dalamudInstallState: Dalamud.InstallState = .failed
                DispatchQueue.main.async {
                    if Settings.dalamudEnabled && dalamudInstallState == .failed
                    {
                        let alert = NSAlert()
                        alert.addButton(
                            withTitle: NSLocalizedString(
                                "BUTTON_OK", comment: ""))
                        alert.alertStyle = .critical
                        alert.messageText = NSLocalizedString(
                            "DALAMUD_START_FAILURE", comment: "")
                        alert.informativeText = NSLocalizedString(
                            "DALAMUD_START_FAILURE_INFORMATIONAL", comment: "")
                        alert.runModal()
                    }
                }
                NotificationCenter.default.post(
                    name: .loginInfo, object: nil,
                    userInfo: [Notification.status.info: "Starting Game"])
                let process = try loginResult.startGame(
                    dalamudInstallState == .ok)
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    view.window?.close()
                }
                AddOn.launchNotify()
                let exitCode = process.exitCode
                Log.information("Game exited with exit code \(exitCode)")
                DispatchQueue.main.async {
                    // Exit codes 0 and 1 are considered normal (1 = user quit from title screen)
                    if exitCode != 0 && exitCode != 1 && Settings.nonZeroExitError {
                        let alert = NSAlert()
                        alert.addButton(
                            withTitle: NSLocalizedString(
                                "BUTTON_OK", comment: ""))
                        alert.alertStyle = .critical
                        alert.messageText = NSLocalizedString(
                            "GAME_START_FAILURE", comment: "")
                        alert.informativeText = NSLocalizedString(
                            "GAME_START_FAILURE_INFORMATIONAL", comment: "")
                        alert.runModal()
                    } else if Settings.exitWithGame {
                        Util.quit()
                    }
                }
            } catch FFXIVLoginError.noInstall {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    view.window?.beginSheet(
                        self.installerWinController!.window!)
                }
            } catch let XLError.loginError(errorMessage) {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(
                        withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = NSLocalizedString(
                        "LOGIN_ERROR", comment: "")
                    alert.informativeText = errorMessage
                    alert.runModal()
                }
            } catch let XLError.startError(errorMessage) {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(
                        withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = NSLocalizedString(
                        "START_ERROR", comment: "")
                    alert.informativeText = errorMessage
                    alert.runModal()
                }
            } catch let error as FFXIVLoginError {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(
                        withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = error.failureReason ?? "Error"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            } catch {  // should not reach
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(
                        withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = "Error"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    func startPatch(_ patches: [Patch]) {
        if Thread.isMainThread {
            view.window?.beginSheet(patchWinController!.window!)
        } else {
            DispatchQueue.main.sync { [self] in
                view.window?.beginSheet(patchWinController!.window!)
            }
        }
        patchController?.install(patches)
    }

    @IBAction func tapTroubleshooting(_ sender: Any) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.openFirstAid(self)
    }

    @IBAction func tapBunnyHUD(_ sender: Any) {
        BunnyHUD.launch()
    }
}

class userMenuItem: NSMenuItem {
    var credentials: LoginCredentials!
}

final class BannerView: NSImageView {
    var banner: Frontier.BannerRoot.Banner? {
        didSet {
            let bannerURL = URL(string: banner!.lsbBanner)!
            DispatchQueue.global(qos: .background).async { [self] in
                let bannerImage = Frontier.fetchImage(
                    url: bannerURL)
                DispatchQueue.main.async { [self] in
                    image = bannerImage
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let banner = banner {
            let url = URL(string: banner.link)!
            NSWorkspace.shared.open(url)
        }
    }
}

final class AnimatingScrollView: NSScrollView {
    private var width: CGFloat {
        return contentSize.width
    }

    private var height: CGFloat {
        return contentSize.height
    }

    private let animationDuration = 2.0
    private let stayDuration = 8.0
    private var index = 0
    private var timer = Timer()

    var banners: [Frontier.BannerRoot.Banner]? {
        didSet {
            let banners = banners!
            documentView?.setFrameSize(
                NSSize(width: width * CGFloat(banners.count), height: height))
            for (i, banner) in banners.enumerated() {
                let bannerView = BannerView()
                bannerView.frame = CGRect(
                    x: CGFloat(i) * width, y: 0, width: width, height: height)
                bannerView.imageScaling = .scaleProportionallyUpOrDown
                bannerView.banner = banner
                documentView?.addSubview(bannerView)
            }
            startTimer()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        DispatchQueue.main.async { [self] in
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil)
            addTrackingArea(trackingArea)
        }
    }

    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(
            withTimeInterval: stayDuration, repeats: true,
            block: { _ in
                DispatchQueue.main.async {
                    self.animate()
                }
            })
    }

    func stopTimer() {
        timer.invalidate()
    }

    // This will override and cancel any running scroll animations
    override public func scroll(_ clipView: NSClipView, to point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.setBoundsOrigin(point)
        CATransaction.commit()
        super.scroll(clipView, to: point)
        index = Int(floor((point.x + width / 2) / width))
        let snap_x = CGFloat(index) * width
        scroll(
            toPoint: NSPoint(x: snap_x, y: 0),
            animationDuration: animationDuration)
        startTimer()
    }

    private func scroll(toPoint: NSPoint, animationDuration: Double) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = animationDuration
        contentView.animator().setBoundsOrigin(toPoint)
        reflectScrolledClipView(contentView)
        NSAnimationContext.endGrouping()
    }

    private func animate() {
        guard let banners = banners else { return }
        index = (index + 1) % banners.count
        scroll(
            toPoint: NSPoint(x: Int(width) * index, y: 0),
            animationDuration: animationDuration)
    }

    func scrollRight() {
        guard let banners = banners, index < banners.count - 1 else {
            return
        }
        startTimer()
        index += 1
        scroll(
            toPoint: NSPoint(x: Int(width) * index, y: 0),
            animationDuration: animationDuration)
    }

    func scrollLeft() {
        guard banners != nil, index > 0 else {
            return
        }
        startTimer()
        index -= 1
        scroll(
            toPoint: NSPoint(x: Int(width) * index, y: 0),
            animationDuration: animationDuration)
    }

    override func mouseEntered(with theEvent: NSEvent) {
        super.mouseEntered(with: theEvent)
        NotificationCenter.default.post(name: .bannerEnter, object: nil)
    }

    override func mouseExited(with theEvent: NSEvent) {
        super.mouseExited(with: theEvent)
        NotificationCenter.default.post(name: .bannerLeft, object: nil)
    }
}

// MARK: - WKNavigationDelegate
extension LaunchController {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 檢查是否為 loginPageWebView
        if webView == loginPageWebView {
            // Login page 載入完成後，先獲取原始高度
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] (result, error) in
                guard let self = self, let originalHeight = result as? CGFloat, error == nil else {
                    Log.error("[LaunchController] Failed to get login page height: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                
                // 加上 20px 緩衝
                let heightWithBuffer = originalHeight + 20
                
                Log.information("[LaunchController] Login page original scrollHeight: \(originalHeight)px")
                Log.information("[LaunchController] Login page height with 20px buffer: \(heightWithBuffer)px")
                
                DispatchQueue.main.async {
                    self.adjustLoginPageContainerAndWindow(for: heightWithBuffer)
                }
            }
        } else {
            // 原本的 newsWebView 邏輯（已不需要）
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] (result, error) in
                guard let self = self, let height = result as? CGFloat, error == nil else { return }
                
                DispatchQueue.main.async {
                    self.adjustScrollViewHeight(for: height)
                }
            }
        }
    }
    
    /// 調整 loginPageContainerView 高度和主視窗高度
    private func adjustLoginPageContainerAndWindow(for contentHeight: CGFloat) {
        guard let window = view.window else { return }
        
        // 設定最大高度（移除 minHeight 限制，讓內容自適應）
        let maxHeight: CGFloat = 900
        let targetHeight = min(contentHeight, maxHeight)
        
        Log.information("[LaunchController] Content height: \(contentHeight)px")
        Log.information("[LaunchController] Target height (clamped): \(targetHeight)px")
        
        // 計算視窗高度變化（包含標題列等）
        let titleBarHeight: CGFloat = 28
        let newWindowHeight = targetHeight + titleBarHeight
        
        Log.information("[LaunchController] New window height: \(newWindowHeight)px (target: \(targetHeight) + titleBar: \(titleBarHeight))")
        
        // 獲取當前視窗位置
        let currentFrame = window.frame
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.main!.frame
        
        Log.information("[LaunchController] Current window frame: \(currentFrame)")
        
        // 計算新的視窗位置（垂直居中）
        let newWindowFrame = NSRect(
            x: currentFrame.origin.x,
            y: screenFrame.midY - newWindowHeight / 2,
            width: currentFrame.width,
            height: newWindowHeight
        )
        
        Log.information("[LaunchController] New window frame: \(newWindowFrame)")
        
        // 平滑調整視窗大小
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            window.setFrame(newWindowFrame, display: true, animate: true)
        } completionHandler: {
            Log.information("[LaunchController] Window adjustment completed")
        }
    }
    
    private func adjustWindowHeight(for contentHeight: CGFloat) {
        guard let window = view.window else { return }
        
        // 計算新的視窗高度
        // 考慮到其他 UI 元素的高度（如標題欄、按鈕等）
        let currentFrame = window.frame
        let titleBarHeight: CGFloat = 28  // 標題欄高度估計
        let buttonAreaHeight: CGFloat = 80  // 按鈕區域高度估計
        let minHeight: CGFloat = 400  // 最小視窗高度
        let maxHeight: CGFloat = 800  // 最大視窗高度
        
        // 新的視窗高度 = 內容高度 + 標題欄 + 按鈕區域
        var newHeight = contentHeight + titleBarHeight + buttonAreaHeight
        newHeight = max(minHeight, min(newHeight, maxHeight))  // 限制在合理範圍內
        
        // 調整視窗框架，保持視窗頂部位置不變
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - newHeight,
            width: currentFrame.width,
            height: newHeight
        )
        
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    private func adjustScrollViewHeight(for contentHeight: CGFloat) {
        guard let scrollView = self.scrollView, let window = view.window else { return }

        // 設定高度上限為640px
        let maxHeight: CGFloat = 640
        let newHeight = min(contentHeight, maxHeight)

        // 獲取當前scrollView frame
        let currentScrollViewFrame = scrollView.frame

        // 計算高度變化量
        let heightDifference = newHeight - currentScrollViewFrame.height

        // 如果高度沒有變化，不需要調整
        guard heightDifference != 0 else { return }

        // 創建新的scrollView frame，保持頂部位置不變，只改變高度
        let newScrollViewFrame = NSRect(
            x: currentScrollViewFrame.origin.x,
            y: currentScrollViewFrame.origin.y,  // 保持頂部Y座標不變
            width: currentScrollViewFrame.width,
            height: newHeight
        )

        // 調整視窗高度
        let currentWindowFrame = window.frame
        let newWindowHeight = currentWindowFrame.height + heightDifference

        // 計算新的視窗frame，保持在畫面中央（水平和垂直）
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.main!.frame
        let newWindowFrame = NSRect(
            x: screenFrame.midX - currentWindowFrame.width / 2,  // 水平居中
            y: screenFrame.midY - newWindowHeight / 2,  // 垂直居中
            width: currentWindowFrame.width,
            height: newWindowHeight
        )

        // 同時調整scrollView和視窗
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            scrollView.frame = newScrollViewFrame
            window.setFrame(newWindowFrame, display: true)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.error("[LaunchController] WebView navigation failed: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.error("[LaunchController] WebView provisional navigation failed: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Log.information("[LaunchController] WebView started loading")
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Log.information("[LaunchController] WebView committed navigation")
    }
}

// MARK: - LoginPageManagerDelegate

extension LaunchController: LoginPageManagerDelegate {
    func loginPageManagerRequestAccounts(_ manager: LoginPageManager) {
        // 測試階段：返回空列表
        Log.information("[LaunchController] Requesting saved accounts")
        manager.sendAccounts([])
    }
    
    func loginPageManager(_ manager: LoginPageManager, requestPasswordForAccount account: String) {
        // 測試階段：返回空密碼
        Log.information("[LaunchController] Requesting password for: \(account)")
        manager.sendPassword("")
    }
    
    func loginPageManager(_ manager: LoginPageManager, checkOTPKeyForAccount account: String) {
        // 測試階段：告知沒有 OTP 金鑰
        Log.information("[LaunchController] Checking OTP key for: \(account)")
        manager.notifyNoOTPKey()
    }
    
    func loginPageManager(_ manager: LoginPageManager, saveOTPKey key: String, forAccount account: String) {
        // 測試階段：僅記錄
        Log.information("[LaunchController] Saving OTP key for: \(account)")
        manager.notifyExistingOTPKey()
    }
    
    func loginPageManager(_ manager: LoginPageManager, requestOTPForAccount account: String) {
        // 測試階段：返回測試 OTP
        Log.information("[LaunchController] Requesting OTP for: \(account)")
        manager.sendOTP("123456")
    }
    
    func loginPageManager(_ manager: LoginPageManager, executeLoginWithUsername username: String, password: String, otp: String, recaptchaToken: String) {
        // 測試階段：記錄 token 並通知成功
        Log.information("[LaunchController] Login executed with reCAPTCHA token (length: \(recaptchaToken.count))")
        Log.information("[LaunchController] Username: \(username), OTP: \(otp)")
        
        // 顯示 token 前 20 個字符
        let tokenPreview = String(recaptchaToken.prefix(20))
        Log.information("[LaunchController] Token preview: \(tokenPreview)...")
        
        // 測試：顯示成功訊息
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "測試成功"
            alert.informativeText = "reCAPTCHA Token 長度: \(recaptchaToken.count)\n預覽: \(tokenPreview)..."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "確定")
            alert.runModal()
            
            manager.notifyLoginSuccess()
        }
    }
    
    func loginPageManager(_ manager: LoginPageManager, recaptchaErrorOccurred message: String) {
        Log.error("[LaunchController] reCAPTCHA error: \(message)")
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "reCAPTCHA 錯誤"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "確定")
            alert.runModal()
            
            manager.resetLoginButton()
        }
    }
}


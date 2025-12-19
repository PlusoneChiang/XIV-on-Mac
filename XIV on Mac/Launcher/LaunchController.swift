//
//  LaunchController.swift
//  XIV on Mac
//
//  Created by Marc-Aurel Zent on 02.02.22.
//

import Cocoa
import WebKit
import XIVLauncher
import KeychainAccess

// MARK: - Helper Functions

/// 遮罩用戶名以保護隱私（顯示前3個字符，其餘用 * 代替）
fileprivate func maskUsername(_ username: String) -> String {
    guard username.count > 3 else {
        return String(repeating: "*", count: username.count)
    }
    let prefix = username.prefix(3)
    let masked = String(repeating: "*", count: username.count - 3)
    return "\(prefix)\(masked)"
}

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
        
        // 設置 Login Page 容器
        setupLoginPageContainer()
        
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
            DispatchQueue.main.async { [self] in
                // 安裝完成後關閉安裝視窗，用戶將回到 WebView 登入介面
                installerWinController?.window?.close()
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
        loginPageContainerView.layer?.backgroundColor = .clear  // 設置透明背景，避免灰色遮罩
        
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

    /// 已廢棄：請使用 LoginPageManager 執行登入
    /// 此方法僅保留用於向後相容，實際上不應再被調用
    @available(*, deprecated, message: "Use LoginPageManager delegate instead")
    func doLogin(repair: Bool = false) {
        Log.warning("[DEPRECATED] doLogin() called - this method is deprecated, use WebView login instead")
        
        // Check for show stopping problems
        if problemConfigurationCheck() {
            return
        }
        
        // 由於已廢棄舊的 reCAPTCHA 流程，這裡直接顯示錯誤訊息
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
            alert.alertStyle = .warning
            alert.messageText = "舊版登入已廢棄"
            alert.informativeText = "請使用新的 WebView 登入介面進行登入操作。"
            alert.runModal()
        }
    }

    private func executeLogin(repair: Bool, recaptchaToken: String) {
        // 檢查配置問題（需在主線程執行，因為可能會顯示 FirstAid UI）
        if problemConfigurationCheck() {
            Log.warning("Login cancelled due to configuration problems")
            DispatchQueue.main.async { [weak self] in
                self?.loginPageManager?.resetLoginButton()
            }
            return
        }
        
        DispatchQueue.global(qos: .default).async {
            do {
                // 安裝檢查已在 loginPageManager 中執行，此處不再需要
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
                
                // 通知 WebView 遊戲已啟動
                DispatchQueue.main.async { [self] in
                    loginPageManager?.notifyGameStarted()
                }
                
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    view.window?.close()
                }
                AddOn.launchNotify()
                let exitCode = process.exitCode
                Log.information("Game exited with exit code \(exitCode)")
                
                // 通知 WebView 遊戲已結束
                DispatchQueue.main.async { [self] in
                    loginPageManager?.notifyGameExited(exitCode: exitCode)
                }
                
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
    func webView(_ webView: WKWebView, 
                 decidePolicyFor navigationAction: WKNavigationAction, 
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        // 只攔截用戶點擊的連結（linkActivated），不影響 iframe 的初始載入（.other）
        if navigationAction.navigationType == .linkActivated {
            if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
                // iframe 內的連結點擊，在系統瀏覽器中打開
                if let url = navigationAction.request.url {

                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        
        // 其他導航正常處理（包括 iframe 的初始載入）
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, 
                 createWebViewWith configuration: WKWebViewConfiguration, 
                 for navigationAction: WKNavigationAction, 
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        // 處理 target="_blank" 連結，在系統瀏覽器中打開
        if let url = navigationAction.request.url {

            NSWorkspace.shared.open(url)
        }
        
        return nil
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Login page 載入完成後，先獲取原始高度
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] (result, error) in
            guard let self = self, let originalHeight = result as? CGFloat, error == nil else {
                Log.error("[LaunchController] Failed to get login page height: \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            // 加上 20px 緩衝
            let heightWithBuffer = originalHeight + 20
            
            DispatchQueue.main.async {
                self.adjustLoginPageContainerAndWindow(for: heightWithBuffer)
                
                // 高度調整完成後，檢查是否為初次執行（遊戲是否已安裝）
                // 在使用者輸入帳號密碼前先安裝，避免 OTP 在安裝過程中過期
                if !FFXIVApp().installed {
                    Log.information("[LaunchController] First run detected, showing installer")
                    self.view.window?.beginSheet(self.installerWinController!.window!)
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
        }
    }
    

    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.error("[LaunchController] WebView navigation failed: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.error("[LaunchController] WebView provisional navigation failed: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    }
}

// MARK: - LoginPageManagerDelegate

extension LaunchController: LoginPageManagerDelegate {
    func loginPageManagerRequestAccounts(_ manager: LoginPageManager) {
        Log.information("[LaunchController] Requesting saved accounts")
        
        // 從 Keychain 讀取所有已儲存的帳號
        let allAccounts = LoginCredentials.accounts
        var accountUsernames = allAccounts.map { $0.username }
        
        // 檢查最後使用的帳號是否還存在於 Keychain 中
        if let lastUsedAccount = Settings.credentials?.username {
            if !accountUsernames.contains(lastUsedAccount) {
                // 最後使用的帳號不在 Keychain 中，清空 Settings
                Log.information("[LaunchController] Last used account '\(maskUsername(lastUsedAccount))' not in Keychain, clearing")
                Settings.credentials = nil
            } else {
                // 將最後使用的帳號移到第一位
                accountUsernames.removeAll { $0 == lastUsedAccount }
                accountUsernames.insert(lastUsedAccount, at: 0)
                Log.information("[LaunchController] Last used account: \(maskUsername(lastUsedAccount))")
            }
        }
        
        Log.information("[LaunchController] Sending \(accountUsernames.count) accounts to JS")
        manager.sendAccounts(accountUsernames)
        
        // 發送自動 OTP 設定狀態
        manager.sendAutoOtpSetting(Settings.usesOneTimePassword)
        
        // 如果有帳號，自動發送第一個帳號的密碼（最後使用的或第一個）
        if let firstAccount = accountUsernames.first,
           let credentials = LoginCredentials.storedLogin(username: firstAccount) {
            Log.information("[LaunchController] Auto-filling password for: \(maskUsername(firstAccount))")
            manager.sendPassword(credentials.password)
        }
    }
    
    func loginPageManager(_ manager: LoginPageManager, requestPasswordForAccount account: String) {
        // 從 Keychain 讀取指定帳號的密碼
        if let credentials = LoginCredentials.storedLogin(username: account) {
            manager.sendPassword(credentials.password)
        } else {
            // 帳號不存在或沒有密碼，返回空字串
            manager.sendPassword("")
        }
    }
    
    func loginPageManager(_ manager: LoginPageManager, checkOTPKeyForAccount account: String) {
        // 檢查 Keychain 是否有儲存的 OTP 金鑰
        if OTP.secretStored(username: account) {
            // 有金鑰：通知 JS 並立即生成 OTP
            Log.information("[LaunchController] OTP key found for: \(maskUsername(account))")
            manager.notifyExistingOTPKey()
            
            // 生成 OTP 並發送
            if let (otp, remaining) = generateOTPWithRemaining(for: account) {
                manager.sendOTP(otp, remainingSeconds: remaining)
            }
        } else {
            // 沒有金鑰：通知 JS 顯示輸入框
            Log.information("[LaunchController] No OTP key found for: \(maskUsername(account))")
            manager.notifyNoOTPKey()
        }
    }
    
    func loginPageManager(_ manager: LoginPageManager, saveOTPKey key: String, forAccount account: String) {
        Log.information("[LaunchController] Saving OTP key for: \(maskUsername(account))")
        
        // 儲存金鑰到 Keychain（使用現有的驗證方式）
        OTP.store(username: account, secret: key)
        Log.information("[LaunchController] OTP key saved successfully")
        
        // 通知 JS 已有金鑰
        manager.notifyExistingOTPKey()
        
        // 立即生成並發送 OTP
        if let (otp, remaining) = generateOTPWithRemaining(for: account) {
            manager.sendOTP(otp, remainingSeconds: remaining)
        }
    }
    
    func loginPageManager(_ manager: LoginPageManager, requestOTPForAccount account: String) {
        // 生成 OTP 並發送
        if let (otp, remaining) = generateOTPWithRemaining(for: account) {
            manager.sendOTP(otp, remainingSeconds: remaining)
        } else {
            Log.error("[LaunchController] Failed to generate OTP - no secret stored")
        }
    }
    
    // MARK: - OTP Helper Methods
    
    /// 生成指定帳號的 OTP 並返回剩餘秒數
    private func generateOTPWithRemaining(for username: String) -> (otp: String, remaining: Int)? {
        let keychain = Keychain(server: "https://www.ffxiv.com.tw", protocolType: .https)
        guard let secretData = keychain[data: "\(username)(OTP secret)"] else {
            return nil
        }
        
        let totp = TOTP(secret: secretData)
        let otp = totp.token
        
        // 計算當前週期的剩餘秒數
        let now = Date().timeIntervalSince1970
        let remaining = 30 - Int(now.truncatingRemainder(dividingBy: 30))
        
        return (otp, remaining)
    }
    
    func loginPageManager(_ manager: LoginPageManager, executeLoginWithUsername username: String, password: String, otp: String, recaptchaToken: String) {
        Log.information("[LaunchController] WebView login initiated for user: \(maskUsername(username))")
        
        // 儲存登入資訊到 Settings
        Settings.credentials = LoginCredentials(
            username: username,
            password: password,
            oneTimePassword: otp
        )
        
        // 安裝檢查已在 WebView 載入完成時執行，此處不再需要
        // 顯示登入進度視窗並執行登入
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.view.window?.beginSheet(self.loginSheetWinController!.window!)
        }
        
        // 呼叫既有的登入流程
        // executeLogin 會處理所有錯誤（透過 NSAlert）並在成功時啟動遊戲
        executeLogin(repair: false, recaptchaToken: recaptchaToken)
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


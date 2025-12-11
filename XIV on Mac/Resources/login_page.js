/**
 * XIV on Mac - 登入頁面邏輯
 * Phase 1: 基礎框架實現
 */

// reCAPTCHA Site Key
const SITE_KEY = "6Ld6VmorAAAAANQdQeqkaOeScR42qHC7Hyalq00r";

/**
 * 登入表單管理類
 */
class LoginForm {
  constructor() {
    // DOM 元素
    this.username = document.getElementById('username');
    this.password = document.getElementById('password');
    this.otp = document.getElementById('otp');
    this.otpGroup = document.getElementById('otpGroup');
    this.autoOTP = document.getElementById('autoOTP');
    this.otpKeyGroup = document.getElementById('otpKeyGroup');
    this.otpKey = document.getElementById('otpKey');
    this.confirmOtpKeyBtn = document.getElementById('confirmOtpKey');
    this.loginButton = document.getElementById('loginButton');
    this.accountDropdownBtn = document.getElementById('accountDropdownBtn');
    this.accountDropdown = document.getElementById('accountDropdown');
    
    // 初始化
    this.init();
  }
  
  /**
   * 初始化事件監聽器
   */
  init() {
    console.log('[LoginPage] Initializing...');
    
    // 帳號下拉按鈕
    this.accountDropdownBtn.addEventListener('click', this.toggleAccountDropdown.bind(this));
    
    // 點擊外部關閉下拉選單
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.account-selector')) {
        this.accountDropdown.style.display = 'none';
      }
    });
    
    // 帳號選擇變化
    this.username.addEventListener('change', this.onAccountChange.bind(this));
    this.username.addEventListener('input', this.onAccountInput.bind(this));
    
    // 自動 OTP 核選框
    this.autoOTP.addEventListener('change', this.onAutoOTPToggle.bind(this));
    
    // OTP 金鑰確認按鈕
    this.confirmOtpKeyBtn.addEventListener('click', this.onConfirmOTPKey.bind(this));
    
    // 登入按鈕
    this.loginButton.addEventListener('click', this.onLogin.bind(this));
    
    // Enter 鍵快捷登入
    this.password.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        this.onLogin();
      }
    });
    
    // 請求已儲存的帳號列表
    this.requestAccounts();
    
    console.log('[LoginPage] Initialized successfully');
  }
  
  // ===== 帳號管理 =====
  
  /**
   * 請求已儲存的帳號列表
   */
  requestAccounts() {
    console.log('[LoginPage] Requesting saved accounts...');
    if (window.webkit && window.webkit.messageHandlers.requestAccounts) {
      window.webkit.messageHandlers.requestAccounts.postMessage(null);
    }
  }
  
  /**
   * 接收已儲存的帳號列表（由 Swift 調用）
   */
  receiveAccounts(accounts) {
    console.log('[LoginPage] Received accounts:', accounts);
    
    const dropdown = this.accountDropdown;
    dropdown.innerHTML = '';
    
    if (accounts.length === 0) {
      const emptyItem = document.createElement('div');
      emptyItem.className = 'account-dropdown-empty';
      emptyItem.textContent = '尚無已儲存的帳號';
      dropdown.appendChild(emptyItem);
    } else {
      accounts.forEach(account => {
        const item = document.createElement('div');
        item.className = 'account-dropdown-item';
        item.textContent = account;
        item.addEventListener('click', () => {
          this.username.value = account;
          this.accountDropdown.style.display = 'none';
          this.onAccountChange({ target: { value: account } });
        });
        dropdown.appendChild(item);
      });
    }
  }
  
  /**
   * 切換帳號下拉選單顯示
   */
  toggleAccountDropdown(event) {
    event.stopPropagation();
    const isVisible = this.accountDropdown.style.display === 'block';
    this.accountDropdown.style.display = isVisible ? 'none' : 'block';
    
    if (!isVisible) {
      // 重新請求帳號列表
      this.requestAccounts();
    }
  }
  
  /**
   * 帳號選擇變化事件
   */
  onAccountChange(event) {
    const selectedAccount = event.target.value;
    console.log('[LoginPage] Account changed:', selectedAccount);
    
    if (selectedAccount) {
      this.requestPasswordForAccount(selectedAccount);
    }
  }
  
  /**
   * 帳號輸入變化（用於自動完成）
   */
  onAccountInput(event) {
    // 可以添加自動完成邏輯
  }
  
  /**
   * 請求指定帳號的密碼
   */
  requestPasswordForAccount(account) {
    console.log('[LoginPage] Requesting password for:', account);
    if (window.webkit && window.webkit.messageHandlers.requestPassword) {
      window.webkit.messageHandlers.requestPassword.postMessage(account);
    }
  }
  
  /**
   * 接收密碼（由 Swift 調用）
   */
  receivePassword(password) {
    console.log('[LoginPage] Password received');
    this.password.value = password;
  }
  
  // ===== OTP 管理 =====
  
  /**
   * 自動 OTP 核選框變化事件
   */
  onAutoOTPToggle(event) {
    const checked = event.target.checked;
    console.log('[LoginPage] Auto OTP toggled:', checked);
    
    if (checked) {
      // 檢查是否已有儲存的金鑰
      const currentAccount = this.username.value;
      if (currentAccount) {
        this.checkOTPKey(currentAccount);
      } else {
        // 沒有選擇帳號，直接展開金鑰輸入框
        this.showOTPKeyGroup();
      }
    } else {
      // 取消勾選：隱藏金鑰輸入框，但保持 OTP 輸入框可見
      this.hideOTPKeyGroup();
      this.otpKey.value = '';
      this.otp.value = '';
    }
  }
  
  /**
   * 檢查帳號是否有已儲存的 OTP 金鑰
   */
  checkOTPKey(account) {
    console.log('[LoginPage] Checking OTP key for:', account);
    if (window.webkit && window.webkit.messageHandlers.checkOTPKey) {
      window.webkit.messageHandlers.checkOTPKey.postMessage(account);
    }
  }
  
  /**
   * 有已儲存的金鑰（由 Swift 調用）
   */
  onExistingOTPKey() {
    console.log('[LoginPage] Existing OTP key found');
    // 隱藏金鑰輸入框
    this.hideOTPKeyGroup();
    // 請求生成 OTP
    this.requestOTP();
  }
  
  /**
   * 沒有已儲存的金鑰（由 Swift 調用）
   */
  onNoOTPKey() {
    console.log('[LoginPage] No OTP key found, showing input');
    // 展開金鑰輸入框（使用平滑動畫）
    this.showOTPKeyGroup();
  }
  
  /**
   * 展開金鑰輸入框（帶平滑動畫）
   */
  showOTPKeyGroup() {
    // 先設置為 block 但高度為 0
    this.otpKeyGroup.style.display = 'block';
    this.otpKeyGroup.style.maxHeight = '0';
    this.otpKeyGroup.style.opacity = '0';
    this.otpKeyGroup.style.overflow = 'hidden';
    this.otpKeyGroup.style.transition = 'max-height 0.3s ease, opacity 0.3s ease, margin 0.3s ease';
    
    // 強制重排以確保動畫生效
    this.otpKeyGroup.offsetHeight;
    
    // 展開到自然高度
    this.otpKeyGroup.style.maxHeight = '200px';
    this.otpKeyGroup.style.opacity = '1';
    
    // 聚焦到金鑰輸入框
    setTimeout(() => {
      this.otpKey.focus();
    }, 300);
  }
  
  /**
   * 收起金鑰輸入框（帶平滑動畫）
   */
  hideOTPKeyGroup() {
    this.otpKeyGroup.style.maxHeight = '0';
    this.otpKeyGroup.style.opacity = '0';
    
    // 動畫結束後隱藏元素
    setTimeout(() => {
      this.otpKeyGroup.style.display = 'none';
    }, 300);
  }
  
  /**
   * 確認 OTP 金鑰按鈕點擊事件
   */
  onConfirmOTPKey() {
    const key = this.otpKey.value.trim();
    console.log('[LoginPage] Confirming OTP key');
    
    if (!key) {
      alert('請輸入 OTP 金鑰');
      return;
    }
    
    // 發送金鑰到 Swift 進行驗證和儲存
    this.saveOTPKey(key);
  }
  
  /**
   * 儲存 OTP 金鑰
   */
  saveOTPKey(key) {
    console.log('[LoginPage] Saving OTP key');
    if (window.webkit && window.webkit.messageHandlers.saveOTPKey) {
      window.webkit.messageHandlers.saveOTPKey.postMessage(key);
    }
  }
  
  /**
   * 請求生成 OTP
   */
  requestOTP() {
    console.log('[LoginPage] Requesting OTP generation');
    if (window.webkit && window.webkit.messageHandlers.requestOTP) {
      window.webkit.messageHandlers.requestOTP.postMessage(null);
    }
  }
  
  /**
   * 接收生成的 OTP（由 Swift 調用）
   */
  receiveOTP(otp) {
    console.log('[LoginPage] OTP received');
    // 填入 OTP
    this.otp.value = otp;
    // 隱藏金鑰輸入框
    this.hideOTPKeyGroup();
  }
  
  // ===== 登入流程 =====
  
  /**
   * 登入按鈕點擊事件
   */
  async onLogin() {
    console.log('[LoginPage] Login button clicked');
    
    // 禁用按鈕，顯示載入狀態
    this.loginButton.disabled = true;
    this.loginButton.classList.add('loading');
    this.loginButton.textContent = '登入中...';
    
    try {
      // 1. 驗證表單
      if (!this.validateForm()) {
        this.resetLoginButton();
        return;
      }
      
      // 2. 獲取 reCAPTCHA token
      const token = await this.getRecaptchaToken();
      console.log('[LoginPage] reCAPTCHA token obtained');
      
      // 3. 收集表單數據
      const credentials = {
        username: this.username.value,
        password: this.password.value,
        otp: this.otp.value || '',
        recaptchaToken: token
      };
      
      // 4. 通知 Swift 執行登入
      this.executeLogin(credentials);
      
    } catch (error) {
      console.error('[LoginPage] Login error:', error);
      // reCAPTCHA 獲取失敗，通知 Swift
      this.notifyRecaptchaError(error.message);
      this.resetLoginButton();
    }
  }
  
  /**
   * 表單驗證
   */
  validateForm() {
    if (!this.username.value.trim()) {
      console.warn('[LoginPage] Username is empty');
      alert('請輸入帳號');
      return false;
    }
    
    if (!this.password.value) {
      console.warn('[LoginPage] Password is empty');
      alert('請輸入密碼');
      return false;
    }
    
    return true;
  }
  
  /**
   * 獲取 reCAPTCHA token
   */
  async getRecaptchaToken() {
    console.log('[LoginPage] Getting reCAPTCHA token...');
    
    return new Promise((resolve, reject) => {
      if (typeof grecaptcha === 'undefined' || !grecaptcha.enterprise) {
        reject(new Error('reCAPTCHA SDK 未載入'));
        return;
      }
      
      grecaptcha.enterprise.ready(() => {
        grecaptcha.enterprise.execute(SITE_KEY, { action: 'LOGIN' })
          .then(token => {
            console.log('[LoginPage] reCAPTCHA token obtained successfully');
            resolve(token);
          })
          .catch(error => {
            console.error('[LoginPage] reCAPTCHA execution failed:', error);
            reject(error);
          });
      });
    });
  }
  
  /**
   * 執行登入（通知 Swift）
   */
  executeLogin(credentials) {
    console.log('[LoginPage] Executing login...');
    if (window.webkit && window.webkit.messageHandlers.executeLogin) {
      window.webkit.messageHandlers.executeLogin.postMessage(credentials);
    } else {
      console.error('[LoginPage] executeLogin handler not available');
      this.resetLoginButton();
    }
  }
  
  /**
   * 通知 reCAPTCHA 錯誤
   */
  notifyRecaptchaError(message) {
    console.error('[LoginPage] Notifying reCAPTCHA error:', message);
    if (window.webkit && window.webkit.messageHandlers.recaptchaError) {
      window.webkit.messageHandlers.recaptchaError.postMessage(message);
    }
  }
  
  // ===== 狀態管理 =====
  
  /**
   * 重置登入按鈕狀態
   */
  resetLoginButton() {
    console.log('[LoginPage] Resetting login button');
    this.loginButton.disabled = false;
    this.loginButton.classList.remove('loading');
    this.loginButton.textContent = '登入';
  }
  
  /**
   * 登入成功回調（由 Swift 調用）
   */
  onLoginSuccess() {
    console.log('[LoginPage] Login successful');
    // 可選：顯示過渡動畫
    document.querySelector('.login-form').style.opacity = '0.5';
  }
}

// ===== 初始化 =====

// 等待 DOM 載入完成
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initLoginPage);
} else {
  initLoginPage();
}

function initLoginPage() {
  console.log('[LoginPage] DOM ready, initializing...');
  window.loginForm = new LoginForm();
}

// ===== 全域錯誤處理 =====

window.addEventListener('error', (event) => {
  console.error('[LoginPage] Global error:', event.error);
});

window.addEventListener('unhandledrejection', (event) => {
  console.error('[LoginPage] Unhandled promise rejection:', event.reason);
});

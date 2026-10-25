//
//  LoginWindowController.swift
//  Tweetintosh - Headless Data-driven Client
//

import Cocoa
import WebKit

final class LoginWindowController: NSWindowController, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private var webView: WKWebView?
    private var completion: ((AuthCredentials?) -> Void)?
    private var captured = false
    
    convenience init(completion: @escaping (AuthCredentials?) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to X (Tweetintosh Authentication)"
        window.center()
        window.backgroundColor = .black
        
        self.init(window: window)
        self.completion = completion
        setupWebView()
    }
    
    private func setupWebView() {
        guard let window = self.window else { return }
        
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let web = WKWebView(frame: window.contentView!.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        
        window.contentView?.addSubview(web)
        self.webView = web
        
        // Listen to cookies
        config.websiteDataStore.httpCookieStore.add(self)
        
        // Load X login page
        if let url = URL(string: "https://x.com/i/flow/login") {
            web.load(URLRequest(url: url))
        }
    }
    
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self, !self.captured else { return }
            
            var authToken: String?
            var ct0: String?
            
            for cookie in cookies {
                if cookie.domain.contains("x.com") || cookie.domain.contains("twitter.com") {
                    if cookie.name == "auth_token" && !cookie.value.isEmpty {
                        authToken = cookie.value
                    } else if cookie.name == "ct0" && !cookie.value.isEmpty {
                        ct0 = cookie.value
                    }
                }
            }
            
            if let token = authToken, let csrf = ct0 {
                self.captured = true
                let creds = AuthCredentials(
                    authToken: token,
                    ct0: csrf,
                    userId: nil,
                    screenName: nil,
                    updatedAt: Date()
                )
                
                DispatchQueue.main.async {
                    self.finishLogin(with: creds)
                }
            }
        }
    }
    
    private func finishLogin(with creds: AuthCredentials?) {
        guard let web = webView else { return }
        web.configuration.websiteDataStore.httpCookieStore.remove(self)
        web.stopLoading()
        web.removeFromSuperview()
        self.webView = nil // Destroy webview instance completely to free memory
        
        self.window?.close()
        self.completion?(creds)
        self.completion = nil
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    func windowWillClose(_ notification: Notification) {
        if !captured {
            finishLogin(with: nil)
        }
    }
}

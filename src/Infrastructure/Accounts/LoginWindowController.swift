//
//  LoginWindowController.swift
//  Tweetintosh - Headless Data-driven Client
//

import Cocoa
import WebKit

final class LoginWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    private var webView: WKWebView?
    private var completion: ((AuthCredentials?) -> Void)?
    private var captured = false
    // "Continue with Google / Apple" opens its sign-in page as a popup (window.open); these are those popups
    private var popups: [(window: NSWindow, web: WKWebView)] = []
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    
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
        web.uiDelegate = self
        web.customUserAgent = Self.userAgent
        
        window.contentView?.addSubview(web)
        self.webView = web
        
        // Start from a clean slate. Whatever session is still stored (for instance an account that was just signed
        // out of) would otherwise be picked up by the cookie listener as soon as any cookie changes, signing in
        // without a password. Only once everything is gone does the page load and the listener start.
        let store = config.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self, weak web] in
            store.httpCookieStore.getAllCookies { cookies in
                let group = DispatchGroup()
                for cookie in cookies {
                    group.enter()
                    store.httpCookieStore.delete(cookie) { group.leave() }
                }
                group.notify(queue: .main) {
                    guard let self = self, let web = web else { return }
                    store.httpCookieStore.add(self)
                    if let url = URL(string: "https://x.com/i/flow/login") {
                        web.load(URLRequest(url: url))
                    }
                }
            }
        }
    }
    
    // MARK: Popups (third-party sign-in)
    
    // The popup must be built from the configuration WebKit passes in: that keeps it connected to the page that
    // opened it, which the provider's page uses to hand the result back when it finishes
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let size = NSSize(width: max(windowFeatures.width?.doubleValue ?? 500, 420),
                          height: max(windowFeatures.height?.doubleValue ?? 640, 560))
        let popupWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        popupWindow.isReleasedWhenClosed = false
        popupWindow.title = "Sign in"
        popupWindow.center()
        
        let popup = WKWebView(frame: popupWindow.contentView!.bounds, configuration: configuration)
        popup.autoresizingMask = [.width, .height]
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.customUserAgent = Self.userAgent
        popupWindow.contentView?.addSubview(popup)
        
        popups.append((popupWindow, popup))
        if let parent = window { parent.addChildWindow(popupWindow, ordered: .above) }
        popupWindow.makeKeyAndOrderFront(nil)
        return popup
    }
    
    // The provider's page calls window.close() when it is done
    func webViewDidClose(_ webView: WKWebView) {
        closePopup(for: webView)
    }
    
    private func closePopup(for webView: WKWebView) {
        guard let index = popups.firstIndex(where: { $0.web === webView }) else { return }
        let entry = popups.remove(at: index)
        entry.web.stopLoading()
        window?.removeChildWindow(entry.window)
        entry.window.close()
    }
    
    private func closeAllPopups() {
        for entry in popups {
            entry.web.stopLoading()
            window?.removeChildWindow(entry.window)
            entry.window.close()
        }
        popups.removeAll()
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
        closeAllPopups()
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

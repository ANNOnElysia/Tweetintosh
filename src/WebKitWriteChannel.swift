//
//  WebKitWriteChannel.swift
//  Tweetintosh - Headless Data-driven Client
//
//  X requires write actions (e.g. CreateTweet, Favorite, Retweet) to originate from a valid browser environment.
//  In modern X, sensitive endpoints verify dynamic client headers (such as x-client-transaction-id) and full session
//  context. This channel operates an offscreen, hidden WebKit runtime loading x.com's lightweight web intent endpoint
//  with the authentic session cookie store and full Safari User-Agent, providing Safari-grade write success while
//  remaining 100% invisible to the user. An idle timer automatically tears down the WebKit process after 60 seconds
//  of inactivity to maintain a near-zero memory footprint during timeline browsing.
//

import Foundation
import WebKit
import os

private let writeLog = Logger(subsystem: "com.anno.tweetintosh", category: "write")

final class WebKitWriteChannel: NSObject, WKNavigationDelegate {
    static let shared = WebKitWriteChannel()
    
    /// How long the page may take to load before the requests waiting on it are failed.
    private let loadTimeout: TimeInterval = 25
    /// How long one mutation may take before it is reported as a network failure.
    private let requestTimeout: TimeInterval = 45
    
    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var identity: String?
    private var isLoaded = false
    private var waitingForLoad: [(ready: () -> Void, failure: (APIError) -> Void)] = []
    
    /// Idle timer to release WebContent memory when no writes occur
    private var idleWorkItem: DispatchWorkItem?
    
    private override init() { super.init() }
    
    // MARK: - Public
    
    /// Runs a GraphQL mutation from inside x.com. The answer is the decoded body of a successful response; a
    /// refusal or a transport failure comes back as the matching APIError.
    func perform(path: String, body: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void) {
        DispatchQueue.main.async {
            guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
                completion(.failure(.unauthenticated))
                return
            }
            self.cancelIdleTeardown()
            self.prepare(for: creds)
            self.whenLoaded(
                ready: {
                    self.send(path: path, body: body, creds: creds) { result in
                        self.scheduleIdleTeardown()
                        completion(result)
                    }
                },
                failure: { error in
                    self.scheduleIdleTeardown()
                    completion(.failure(error))
                }
            )
        }
    }
    
    /// Starts the page before anything is typed, so the first press of the post button does not wait for it.
    func warmUp() {
        DispatchQueue.main.async {
            guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else { return }
            self.cancelIdleTeardown()
            self.prepare(for: creds)
            self.scheduleIdleTeardown(after: 90)
        }
    }
    
    // MARK: - The hidden page
    
    private func prepare(for creds: AuthCredentials) {
        let newIdentity = "\(creds.authToken)|\(creds.ct0)"
        if newIdentity == identity { return }   // already loaded, or loading for these credentials
        
        // A different account (or a fresh sign-in) needs its own cookies, so the page starts over
        reset()
        identity = newIdentity
        startLoading(with: creds)
    }
    
    private func startLoading(with creds: AuthCredentials) {
        cancelIdleTeardown()
        
        let config = WKWebViewConfiguration()
        // Use default persistent store to retain full browser session cookies, device tokens, and local cache
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        view.navigationDelegate = self
        
        // Host the webview in an offscreen window (positioned far off-screen so user never sees it)
        let window = NSWindow(
            contentRect: NSRect(x: -3000, y: -3000, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.isReleasedWhenClosed = false
        hostWindow = window
        webView = view
        isLoaded = false
        
        let store = config.websiteDataStore.httpCookieStore
        let expire = Date().addingTimeInterval(60 * 60 * 24 * 30)
        var cookieList = [("auth_token", creds.authToken), ("ct0", creds.ct0)]
        if let userId = creds.userId, !userId.isEmpty {
            cookieList.append(("twid", "\"u=\(userId)\""))
        }
        
        let domains = [".x.com", ".twitter.com"]
        for domain in domains {
            for (name, value) in cookieList {
                let properties: [HTTPCookiePropertyKey: Any] = [
                    .name: name, .value: value, .domain: domain, .path: "/", .expires: expire,
                    .secure: "TRUE"
                ]
                if let cookie = HTTPCookie(properties: properties) { store.setCookie(cookie) }
            }
        }
        
        // Ensure cookies are in place, then load the home page for genuine browser context
        store.getAllCookies { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let view = self.webView else { return }
                view.load(URLRequest(url: URL(string: "https://x.com/")!))
            }
        }
        
        // A page that never finishes loading must not swallow requests
        DispatchQueue.main.asyncAfter(deadline: .now() + loadTimeout) { [weak self] in
            guard let self, !self.isLoaded, self.webView != nil else { return }
            writeLog.error("the write channel page did not load in time")
            self.failWaiting(.networkError(URLError(.timedOut)))
        }
    }
    
    private func whenLoaded(ready: @escaping () -> Void, failure: @escaping (APIError) -> Void) {
        if isLoaded { ready(); return }
        waitingForLoad.append((ready, failure))
    }
    
    private func failWaiting(_ error: APIError) {
        let queued = waitingForLoad
        waitingForLoad = []
        reset()
        queued.forEach { $0.failure(error) }
    }
    
    private func reset() {
        cancelIdleTeardown()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        hostWindow?.orderOut(nil)
        hostWindow = nil
        identity = nil
        isLoaded = false
    }
    
    private func scheduleIdleTeardown(after seconds: TimeInterval = 60) {
        cancelIdleTeardown()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.waitingForLoad.isEmpty else { return }
            writeLog.info("tearing down idle write channel to free memory")
            self.reset()
        }
        idleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
    
    private func cancelIdleTeardown() {
        idleWorkItem?.cancel()
        idleWorkItem = nil
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isLoaded, webView === self.webView else { return }
        isLoaded = true
        let queued = waitingForLoad
        waitingForLoad = []
        writeLog.debug("write channel ready")
        queued.forEach { $0.ready() }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        writeLog.error("write channel page failed: \(error.localizedDescription, privacy: .public)")
        failWaiting(.networkError(error))
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        writeLog.error("write channel page failed to start: \(error.localizedDescription, privacy: .public)")
        failWaiting(.networkError(error))
    }
    
    // MARK: - The request
    
    private func send(path: String, body: [String: Any], creds: AuthCredentials,
                      completion: @escaping (Result<[String: Any], APIError>) -> Void) {
        guard let webView else {
            completion(.failure(.networkError(URLError(.cannotConnectToHost))))
            return
        }
        
        let script = """
        \(TransactionIdScript.script)

        async function executeRequest() {
            // Generate authentic x-client-transaction-id from X's document shell
            let txId = "";
            try {
                const resp = await fetch("/");
                const html = await resp.text();
                const doc = new DOMParser().parseFromString(html, "text/html");
                const ct = await TweetintoshTx.default.create(doc);
                txId = await ct.generateTransactionId("POST", path);
            } catch (e) {
                console.error("Failed to generate transaction id:", e);
            }

            const headers = {
                "content-type": "application/json",
                "authorization": bearer,
                "x-csrf-token": csrf,
                "x-twitter-active-user": "yes",
                "x-twitter-auth-type": "OAuth2Session",
                "x-twitter-client-language": language
            };
            if (txId) {
                headers["x-client-transaction-id"] = txId;
            }

            const response = await fetch(path, {
                method: "POST",
                credentials: "include",
                headers: headers,
                body: JSON.stringify(body)
            });
            const text = await response.text();

            // Check if an interactive challenge or captcha is demanding user action
            const hasCaptcha = !!document.querySelector('iframe[src*="arkose"], div#arkose, iframe[title*="challenge"]');

            return { status: response.status, text: text, hasCaptcha: hasCaptcha };
        }

        return await executeRequest();
        """
        
        var finished = false
        func finish(_ result: Result<[String: Any], APIError>) {
            guard !finished else { return }
            finished = true
            completion(result)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + requestTimeout) {
            if !finished {
                writeLog.error("\(path, privacy: .public) timed out")
                finish(.failure(.networkError(URLError(.timedOut))))
            }
        }
        
        webView.callAsyncJavaScript(script,
                                    arguments: [
                                        "path": path,
                                        "body": body,
                                        "csrf": creds.ct0,
                                        "bearer": APIClient.shared.bearerToken,
                                        "language": APIClient.shared.clientLanguageHeader
                                    ],
                                    in: nil,
                                    in: .page) { outcome in
            switch outcome {
            case .failure(let error):
                writeLog.error("\(path, privacy: .public) could not be sent: \(error.localizedDescription, privacy: .public)")
                finish(.failure(.networkError(error)))
            case .success(let value):
                guard let answer = value as? [String: Any],
                      let status = answer["status"] as? Int,
                      let text = answer["text"] as? String else {
                    finish(.failure(.parseError))
                    return
                }
                
                if (answer["hasCaptcha"] as? Bool) == true {
                    self.presentCaptchaWindow()
                } else {
                    self.hideCaptchaWindow()
                }
                
                let data = Data(text.utf8)
                if let refusal = APIClient.refusal(from: data) {
                    APIClient.logRefusal(refusal, endpoint: path)
                    finish(.failure(.refused(code: refusal.code, message: refusal.message)))
                    return
                }
                guard (200...299).contains(status) else {
                    finish(.failure(.serverError(APIClient.errorMessage(from: data) ?? "HTTP \(status)")))
                    return
                }
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    finish(.failure(.parseError))
                    return
                }
                finish(.success(json))
            }
        }
    }
    
    // MARK: - CAPTCHA Support
    
    private func presentCaptchaWindow() {
        guard let window = hostWindow else { return }
        window.title = "Security Verification - X"
        window.center()
        window.styleMask = [.titled, .closable]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func hideCaptchaWindow() {
        guard let window = hostWindow else { return }
        window.orderOut(nil)
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
        window.styleMask = [.borderless]
    }
}

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
        perform(path: path, body: body, asForm: false, completion: completion)
    }

    /// The same for X's older 1.1 endpoints, which take a form rather than JSON (such as account/update_profile.json).
    /// A success with an empty body, as some of them answer, comes back as an empty dictionary.
    func performForm(path: String, fields: [String: String], completion: @escaping (Result<[String: Any], APIError>) -> Void) {
        perform(path: path, body: fields, asForm: true, completion: completion)
    }

    private func perform(path: String, body: [String: Any], asForm: Bool, completion: @escaping (Result<[String: Any], APIError>) -> Void) {
        DispatchQueue.main.async {
            guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
                completion(.failure(.unauthenticated))
                return
            }
            self.cancelIdleTeardown()
            self.prepare(for: creds)
            self.whenLoaded(
                ready: {
                    self.send(path: path, body: body, asForm: asForm, creds: creds) { result in
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
    
    private func send(path: String, body: [String: Any], asForm: Bool = false, creds: AuthCredentials,
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
                "content-type": asForm ? "application/x-www-form-urlencoded" : "application/json",
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
                body: asForm ? new URLSearchParams(body).toString() : JSON.stringify(body)
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
                                        "asForm": asForm,
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
                if asForm && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finish(.success([:]))
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
    
    // MARK: - X Chat / Juicebox E2EE Passcode Recovery
    
    struct XChatRecoveredSecret {
        let hex: String
        let publicKeyVersion: String?
    }
    
    /// Reconstructs the user's X Chat secret via X's Juicebox KMS protocol and WebAssembly. The secret is the
    /// 32-byte identity (decryption) key, followed on current accounts by the 32-byte signing key that sending
    /// needs; it comes back as hex together with the version of the key pair it belongs to.
    func recoverXChatPrivateKey(passcode: String, userId: String, completion: @escaping (Result<XChatRecoveredSecret, APIError>) -> Void) {
        DispatchQueue.main.async {
            guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
                completion(.failure(.unauthenticated))
                return
            }
            self.cancelIdleTeardown()
            self.prepare(for: creds)
            self.whenLoaded(
                ready: {
                    self.executeRecovery(passcode: passcode, userId: userId, creds: creds) { result in
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
    
    private func executeRecovery(passcode: String, userId: String, creds: AuthCredentials, completion: @escaping (Result<XChatRecoveredSecret, APIError>) -> Void) {
        guard let webView = webView else {
            completion(.failure(.invalidResponse))
            return
        }
        
        let script = """
        async function runJuiceboxRecovery() {
            try {
                const queryId = "C-YphxeIcPLOGtFNGhkuOw";
                const url = "/i/api/graphql/" + queryId + "/GetPublicKeysQuery?variables=" + encodeURIComponent(JSON.stringify({
                    ids: [userId],
                    include_juicebox_tokens: true
                }));
                
                const csrf = (document.cookie.match(/ct0=([^;]+)/) || [])[1] || creds_csrf;
                const headers = {
                    "authorization": bearer,
                    "x-csrf-token": csrf,
                    "x-twitter-active-user": "yes"
                };
                
                const resp = await fetch(url, { headers });
                if (!resp.ok) {
                    return { success: false, error: "HTTP " + resp.status };
                }
                const json = await resp.json();
                const userRes = json.data?.user_results_by_rest_ids?.[0]?.result;
                const pks = userRes?.get_public_keys?.public_keys_with_token_map || [];
                if (pks.length === 0) {
                    return { success: false, error: "No public keys found for user" };
                }
                
                const jbModule = await import("https://abs.twimg.com/x-web/xchat/embed/assets/juicebox-sdk-Ra1ujYy4.js");
                const jb = await jbModule.load();
                
                // Try from newest to oldest keypair
                const orderedPks = [...pks].reverse();
                let lastErr = null;
                
                for (const pkWithMap of orderedPks) {
                    try {
                        const tokenMapJson = pkWithMap.token_map?.key_store_token_map_json;
                        const tokenEntries = pkWithMap.token_map?.token_map || [];
                        if (!tokenMapJson) continue;
                        
                        const map = {};
                        for (const e of tokenEntries) {
                            map[e.key] = e.value.token;
                            if (e.value.address) map[e.value.address] = e.value.token;
                        }
                        
                        globalThis.JuiceboxGetAuthToken = (arg) => {
                            let key = "";
                            if (arg instanceof Uint8Array || ArrayBuffer.isView(arg)) {
                                for (let i = 0; i < arg.length; i++) key += arg[i].toString(16).padStart(2, "0");
                            } else {
                                key = String(arg);
                            }
                            const tok = map[key] || Object.values(map)[0];
                            return Promise.resolve(tok);
                        };
                        
                        const config = new jb.Configuration(tokenMapJson);
                        const client = new jb.Client(config, []);
                        const pinBytes = new TextEncoder().encode(passcode);
                        const secretBytes = await client.recover(pinBytes, new Uint8Array(0));
                        
                        let hex = "";
                        // Keep all of it: the second half is the signing key that sending needs.
                        for (let i = 0; i < secretBytes.length; i++) {
                            hex += secretBytes[i].toString(16).padStart(2, "0");
                        }
                        const keyVersion = pkWithMap.public_key_with_metadata?.version || null;
                        return { success: true, hexKey: hex, keyVersion: keyVersion };
                    } catch (err) {
                        lastErr = err;
                    }
                }
                
                if (lastErr) {
                    let desc = "Incorrect passcode";
                    if (lastErr.guesses_remaining !== undefined) {
                        desc += " (" + lastErr.guesses_remaining + " attempts left)";
                    }
                    return { success: false, error: desc };
                }
                return { success: false, error: "Recovery failed on all keys" };
            } catch (err) {
                return { success: false, error: err.stack || err.message || String(err) };
            }
        }
        return await runJuiceboxRecovery();
        """
        
        webView.callAsyncJavaScript(
            script,
            arguments: [
                "passcode": passcode,
                "userId": userId,
                "creds_csrf": creds.ct0,
                "bearer": APIClient.shared.bearerToken
            ],
            in: nil,
            in: .page
        ) { outcome in
            switch outcome {
            case .failure(let error):
                writeLog.error("Juicebox recovery JS execution failed: \(error.localizedDescription)")
                completion(.failure(.networkError(error)))
            case .success(let val):
                guard let res = val as? [String: Any],
                      let success = res["success"] as? Bool else {
                    completion(.failure(.parseError))
                    return
                }
                if success, let hexKey = res["hexKey"] as? String, !hexKey.isEmpty {
                    completion(.success(XChatRecoveredSecret(hex: hexKey, publicKeyVersion: res["keyVersion"] as? String)))
                } else {
                    let errStr = res["error"] as? String ?? "Recovery failed"
                    completion(.failure(.serverError(errStr)))
                }
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

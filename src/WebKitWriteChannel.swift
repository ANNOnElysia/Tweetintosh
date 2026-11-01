//
//  WebKitWriteChannel.swift
//  Tweetintosh - Headless Data-driven Client
//
//  X only takes writes from a browser's network stack. The identical CreateTweet request sent from URLSession (the
//  way everything else in this app talks to X) comes back as 200 with {"data":{"create_tweet":{"tweet_results":{}}}}
//  — no error, no post — while the same request issued from inside a WKWebView is accepted and returns the new post.
//  Reads are unaffected, which is why timelines and profiles keep working normally.
//
//  So every request that changes something on X goes through this one hidden web view, and nothing else does. It
//  loads the smallest page on the site, a text file with no app scripts, because the page itself is irrelevant: the
//  request is accepted because of the connection it is made over, not because of anything the page runs.

import Foundation
import WebKit
import os

private let writeLog = Logger(subsystem: "com.anno.tweetintosh", category: "write")

final class WebKitWriteChannel: NSObject, WKNavigationDelegate {
    static let shared = WebKitWriteChannel()
    
    /// How long the page may take to load before the requests waiting on it are failed.
    private let loadTimeout: TimeInterval = 20
    /// How long one mutation may take before it is reported as a network failure.
    private let requestTimeout: TimeInterval = 45
    
    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var identity: String?
    private var isLoaded = false
    private var waitingForLoad: [(ready: () -> Void, failure: (APIError) -> Void)] = []
    
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
            self.prepare(for: creds)
            self.whenLoaded(
                ready: { self.send(path: path, body: body, creds: creds, completion: completion) },
                failure: { completion(.failure($0)) }
            )
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
        let config = WKWebViewConfiguration()
        // Nothing on disk: the session cookies are handed over as they are needed, and the login window keeps its
        // own store, so the two can never pick up each other's cookies.
        config.websiteDataStore = .nonPersistent()
        
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: config)
        view.navigationDelegate = self
        // WebKit throttles a view that no window ever held, so it gets an offscreen window that is never shown
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.isReleasedWhenClosed = false
        hostWindow = window
        webView = view
        isLoaded = false
        
        let store = config.websiteDataStore.httpCookieStore
        let expire = Date().addingTimeInterval(60 * 60 * 24 * 30)
        for (name, value) in [("auth_token", creds.authToken), ("ct0", creds.ct0)] {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: ".x.com", .path: "/", .expires: expire
            ]
            if let cookie = HTTPCookie(properties: properties) { store.setCookie(cookie) }
        }
        // The cookies have to be in place before the first load, or the page arrives signed out
        store.getAllCookies { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let view = self.webView else { return }
                view.load(URLRequest(url: URL(string: "https://x.com/robots.txt")!))
            }
        }
        
        // A page that never finishes loading must not swallow the post
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
        webView?.navigationDelegate = nil
        webView = nil
        hostWindow = nil
        identity = nil
        isLoaded = false
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
        
        // The page's fetch carries the same headers a signed-in browser sends, and the cookies the page holds
        let script = """
        const response = await fetch(path, {
            method: "POST",
            credentials: "include",
            headers: {
                "content-type": "application/json",
                "authorization": bearer,
                "x-csrf-token": csrf,
                "x-twitter-active-user": "yes",
                "x-twitter-auth-type": "OAuth2Session",
                "x-twitter-client-language": language
            },
            body: JSON.stringify(body)
        });
        const text = await response.text();
        return { status: response.status, text: text };
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
}

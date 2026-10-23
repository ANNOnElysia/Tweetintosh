//
//  AuthCredentials.swift
//  MaX - Headless Data-driven Client
//

import Foundation
import WebKit
import Security

struct AuthCredentials: Codable, Equatable {
    var authToken: String
    var ct0: String
    var userId: String?
    var screenName: String?
    var updatedAt: Date
    
    var isValid: Bool {
        return !authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !ct0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var cookieHeaderString: String {
        return "auth_token=\(authToken); ct0=\(ct0);"
    }
}

final class CredentialsManager {
    static let shared = CredentialsManager()
    
    private let fileURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maxDir = appSupport.appendingPathComponent("MaX", isDirectory: true)
        try? FileManager.default.createDirectory(at: maxDir, withIntermediateDirectories: true)
        self.fileURL = maxDir.appendingPathComponent("credentials.json")
    }
    
    func loadCredentials() -> AuthCredentials? {
        guard let data = try? Data(contentsOf: fileURL),
              let creds = try? JSONDecoder().decode(AuthCredentials.self, from: data) else {
            return nil
        }
        return creds.isValid ? creds : nil
    }
    
    func saveCredentials(_ creds: AuthCredentials) {
        if let data = try? JSONEncoder().encode(creds) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    func clearCredentials() {
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Attempt to silently extract existing auth cookies from WKWebsiteDataStore without showing any UI
    func tryExtractFromDefaultStore(completion: @escaping (AuthCredentials?) -> Void) {
        if let existing = loadCredentials() {
            completion(existing)
            return
        }
        
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { [weak self] cookies in
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
                let creds = AuthCredentials(authToken: token, ct0: csrf, userId: nil, screenName: nil, updatedAt: Date())
                self?.saveCredentials(creds)
                DispatchQueue.main.async {
                    completion(creds)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

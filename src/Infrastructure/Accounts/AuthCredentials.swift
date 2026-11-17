//
//  AuthCredentials.swift
//  Tweetintosh - Headless Data-driven Client
//

import Foundation

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

// The login used for every request is the active account's (see Accounts.swift)
final class CredentialsManager {
    static let shared = CredentialsManager()
    private init() {}
    
    func loadCredentials() -> AuthCredentials? {
        guard let creds = AccountManager.shared.active?.credentials, creds.isValid else { return nil }
        return creds
    }
    
    /// The signed-in account's login, if there is one (nothing is read from the web view's cookies any more: the
    /// login window clears them before every sign-in, so they never belong to an account the app knows about)
    func tryExtractFromDefaultStore(completion: @escaping (AuthCredentials?) -> Void) {
        completion(loadCredentials())
    }
}

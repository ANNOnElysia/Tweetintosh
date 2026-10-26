//
//  Accounts.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Several signed-in accounts, one of them active. Each account keeps its own login and its own cached timeline,
//  notifications and lists; everything that talks to X reads the active account's login through CredentialsManager.
//

import Foundation

struct Account: Codable, Identifiable, Equatable {
    // X's user id. A login carried over from before accounts existed starts with a placeholder id until X has
    // been asked who it belongs to.
    var id: String
    var screenName: String
    var name: String
    var avatarUrl: String?
    var authToken: String
    var ct0: String
    // Where this account's cached data lives, relative to the app's data folder ("" is the folder itself, which
    // is where the first account's files already were)
    var folder: String

    var credentials: AuthCredentials {
        AuthCredentials(authToken: authToken, ct0: ct0, userId: id.hasPrefix(Account.placeholderPrefix) ? nil : id,
                        screenName: screenName.isEmpty ? nil : screenName, updatedAt: Date())
    }

    static let placeholderPrefix = "unverified-"
    var isVerified: Bool { !id.hasPrefix(Account.placeholderPrefix) }
}

private struct AccountsFile: Codable {
    var accounts: [Account]
    var activeId: String?
}

struct AccountInfo {
    var id: String
    var screenName: String
    var name: String
    var avatarUrl: String?
}

final class AccountManager: ObservableObject {
    static let shared = AccountManager()

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var activeId: String?

    private let baseDirectory: URL
    private let fileURL: URL

    var active: Account? {
        accounts.first { $0.id == activeId } ?? accounts.first
    }

    // The data folder of the active account (the base folder when nobody is signed in)
    var activeDirectory: URL {
        directory(for: active)
    }

    func directory(for account: Account?) -> URL {
        guard let account = account, !account.folder.isEmpty else { return baseDirectory }
        let url = baseDirectory.appendingPathComponent(account.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Tweetintosh", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        fileURL = baseDirectory.appendingPathComponent("accounts.json")
        load()
    }

    // MARK: Storage

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let file = try? JSONDecoder().decode(AccountsFile.self, from: data) {
            accounts = file.accounts
            activeId = file.activeId
            return
        }
        // First launch with accounts: the single login saved by earlier versions becomes the first account, and its
        // cached data stays where it already is
        let legacyURL = baseDirectory.appendingPathComponent("credentials.json")
        if let data = try? Data(contentsOf: legacyURL),
           let creds = try? JSONDecoder().decode(AuthCredentials.self, from: data), creds.isValid {
            let account = Account(
                id: creds.userId ?? Account.placeholderPrefix + "first",
                screenName: creds.screenName ?? "", name: creds.screenName ?? "", avatarUrl: nil,
                authToken: creds.authToken, ct0: creds.ct0, folder: ""
            )
            accounts = [account]
            activeId = account.id
            save()
            // Keep the old file as a backup rather than deleting someone's login
            try? FileManager.default.moveItem(at: legacyURL, to: baseDirectory.appendingPathComponent("credentials.json.migrated"))
        }
    }

    private func save() {
        let file = AccountsFile(accounts: accounts, activeId: activeId)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Changes

    // Adds an account (or refreshes the login of one that is already there) and makes it the active one
    func addOrUpdate(creds: AuthCredentials, info: AccountInfo) {
        if let index = accounts.firstIndex(where: { $0.id == info.id }) {
            accounts[index].authToken = creds.authToken
            accounts[index].ct0 = creds.ct0
            accounts[index].screenName = info.screenName
            accounts[index].name = info.name
            accounts[index].avatarUrl = info.avatarUrl
        } else if let index = accounts.firstIndex(where: { !$0.isVerified && $0.authToken == creds.authToken }) {
            // A login carried over from before accounts existed, now identified
            accounts[index].id = info.id
            accounts[index].screenName = info.screenName
            accounts[index].name = info.name
            accounts[index].avatarUrl = info.avatarUrl
        } else {
            accounts.append(Account(
                id: info.id, screenName: info.screenName, name: info.name, avatarUrl: info.avatarUrl,
                authToken: creds.authToken, ct0: creds.ct0, folder: "accounts/\(info.id)"
            ))
        }
        activeId = info.id
        save()
    }

    // Fills in the name and picture of an account that was carried over, and keeps them fresh
    func refreshActiveInfo() {
        guard let account = active else { return }
        AccountManager.fetchInfo(for: account.credentials) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, case .success(let info) = result,
                      let index = self.accounts.firstIndex(where: { $0.authToken == account.authToken }) else { return }
                self.accounts[index].id = info.id
                self.accounts[index].screenName = info.screenName
                self.accounts[index].name = info.name
                self.accounts[index].avatarUrl = info.avatarUrl
                if self.activeId == account.id { self.activeId = info.id }
                self.save()
            }
        }
    }

    func setActive(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeId = id
        save()
    }

    // Removes the active account and returns the one that takes its place, if any
    @discardableResult
    func removeActive() -> Account? {
        guard let current = active else { return nil }
        accounts.removeAll { $0.id == current.id }
        activeId = accounts.first?.id
        save()
        // The account's cached data goes with it (the first account's files share the base folder and are cleared
        // separately, since that folder also holds the accounts file)
        if !current.folder.isEmpty {
            try? FileManager.default.removeItem(at: baseDirectory.appendingPathComponent(current.folder, isDirectory: true))
        }
        return active
    }

    // MARK: Who is this login?

    // Asks X which account a login belongs to. X's account switcher list is what answers: it names the account(s)
    // the login can act as, with their id, name, handle and picture.
    static func fetchInfo(for creds: AuthCredentials, completion: @escaping (Result<AccountInfo, Error>) -> Void) {
        guard let url = URL(string: "https://x.com/i/api/1.1/account/multi/list.json") else { return }
        let api = APIClient.shared
        var request = URLRequest(url: url)
        request.setValue(api.bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue("https://x.com/", forHTTPHeaderField: "referer")
        request.setValue(api.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        api.session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let users = json["users"] as? [[String: Any]],
                  let user = users.first,
                  let id = user["user_id"] as? String,
                  let screenName = user["screen_name"] as? String else {
                completion(.failure(APIError.invalidResponse))
                return
            }
            let avatar = (user["avatar_image_url"] as? String)?.replacingOccurrences(of: "_normal", with: "_400x400")
            completion(.success(AccountInfo(id: id, screenName: screenName,
                                            name: (user["name"] as? String) ?? screenName, avatarUrl: avatar)))
        }.resume()
    }
}

//
//  DMCacheManager.swift
//  Tweetintosh
//
//  Chats as last seen, decrypted, in the active account's data folder. X Chat hands out only a window of recent
//  events per conversation, and x.com keeps the rest in its own local database; this is the app's equivalent, so
//  history stays readable after it leaves that window, and chats show at launch before the network answers.
//
//  The file holds decrypted message text, so it is written readable by the user only and removed on sign-out.
//

import Foundation

final class DMCacheManager {
    static let shared = DMCacheManager()

    struct Snapshot: Codable {
        var accountId: String
        var conversations: [DMConversation]
        var messages: [String: [DMMessage]]
    }

    private let queue = DispatchQueue(label: "com.anno.tweetintosh.dmcache", qos: .utility)

    private init() {}

    private var url: URL {
        AccountManager.shared.activeDirectory.appendingPathComponent("dm_cache.json")
    }

    /// The active account's snapshot; one written for another account is never handed back.
    func load() -> Snapshot? {
        guard let accountId = AccountManager.shared.activeId,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.accountId == accountId else { return nil }
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        let target = url
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            guard let data = try? encoder.encode(snapshot) else { return }
            do {
                try data.write(to: target, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            } catch {
                dmLog.error("DM cache write failed: \(error.localizedDescription)")
            }
        }
    }

    func clearCache() {
        let target = url
        queue.async {
            try? FileManager.default.removeItem(at: target)
        }
    }
}

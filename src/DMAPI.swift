//
//  DMAPI.swift
//  Tweetintosh
//
//  Direct Messages networking service communicating with X's private DM endpoints.
//  Reads inbox state, user updates, and conversation histories with URLSession;
//  supports modern X Chat GraphQL endpoints (GetInitialXChatPageQuery, GetConversationPageQuery)
//  with a native Thrift binary protocol decoder, while falling back gracefully to legacy REST endpoints.
//  Dispatches outbound messages via WebKitWriteChannel to satisfy X's anti-abuse and browser context requirements.
//

import Foundation
import CryptoKit
import os

let dmLog = Logger(subsystem: "com.anno.tweetintosh", category: "dm")

// MARK: - Lightweight Thrift Binary Protocol Reader

struct ThriftBinaryReader {
    let data: Data
    var offset: Int = 0
    
    mutating func readByte() -> UInt8? {
        guard offset < data.count else { return nil }
        let b = data[offset]
        offset += 1
        return b
    }
    
    mutating func readBool() -> Bool? {
        guard let b = readByte() else { return nil }
        return b != 0
    }
    
    mutating func readInt16() -> Int16? {
        guard offset + 2 <= data.count else { return nil }
        let val = data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: Int16.self).bigEndian }
        offset += 2
        return val
    }
    
    mutating func readInt32() -> Int32? {
        guard offset + 4 <= data.count else { return nil }
        let val = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        offset += 4
        return val
    }
    
    mutating func readInt64() -> Int64? {
        guard offset + 8 <= data.count else { return nil }
        let val = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: Int64.self).bigEndian }
        offset += 8
        return val
    }
    
    mutating func readBinary() -> Data? {
        guard let len = readInt32(), len >= 0, offset + Int(len) <= data.count else { return nil }
        let sub = data.subdata(in: offset..<offset+Int(len))
        offset += Int(len)
        return sub
    }
    
    mutating func readString() -> String? {
        guard let bin = readBinary() else { return nil }
        return String(data: bin, encoding: .utf8)
    }
    
    mutating func skip(type: UInt8) {
        switch type {
        case 2, 3: // Bool, Byte
            offset += 1
        case 6: // I16
            offset += 2
        case 8: // I32
            offset += 4
        case 10: // I64
            offset += 8
        case 11: // String / Binary
            if let len = readInt32(), len >= 0 {
                offset += Int(len)
            }
        case 12: // Struct
            while let fType = readByte(), fType != 0 {
                _ = readInt16()
                skip(type: fType)
            }
        case 14, 15: // Set, List
            guard let elemType = readByte(), let count = readInt32(), count >= 0 else { return }
            for _ in 0..<count {
                skip(type: elemType)
            }
        case 13: // Map
            guard let kType = readByte(), let vType = readByte(), let count = readInt32(), count >= 0 else { return }
            for _ in 0..<count {
                skip(type: kType)
                skip(type: vType)
            }
        default:
            offset = data.count
        }
    }
}

// MARK: - Parsed X Chat Event Structure

struct ParsedXChatMessage {
    var eventId: String = ""
    var messageId: String = ""
    var senderId: String = ""
    var conversationId: String = ""
    var timestampMs: Int64 = 0
    var decoded = DMDecodedContent()
    var isEncrypted: Bool = false
    var hasMessagePayload: Bool = false
    var rawCiphertext: Data? = nil
    var keyVersion: String? = nil
    var mediaUrl: String? = nil
    var isReadReceipt: Bool = false
    var isDelete: Bool = false
    var conversationToken: String? = nil
}

final class DMAPI {
    static let shared = DMAPI()
    private init() {}
    
    // GraphQL Query IDs captured from modern X Web
    private let initialXChatQueryId = "hI8FUrv1eY-ze6SrR9mbVA"
    private let conversationPageQueryId = "GX9ZijkxG8AqRMQVD7hMnQ"
    
    // MARK: - 1. Fetch Unified Inbox (X Chat GraphQL + Legacy REST)
    
    func fetchInbox(completion: @escaping (Result<([DMConversation], [String: [DMMessage]]), APIError>) -> Void) {
        // First fetch X Chat GraphQL inbox (modern conversations)
        fetchXChatInbox { [weak self] xChatResult in
            guard let self = self else { return }
            
            switch xChatResult {
            case .success(let (xChatConvs, xChatMsgs)):
                // Concurrently fetch legacy inbox to backfill any older historical threads
                self.fetchLegacyInbox { legacyResult in
                    var mergedConvs = xChatConvs
                    var mergedMsgs = xChatMsgs
                    
                    if case .success(let (legacyConvs, legacyMsgs)) = legacyResult {
                        for lConv in legacyConvs {
                            // Only add if not already covered by an X Chat conversation
                            let alreadyCovered = mergedConvs.contains { xc in
                                xc.id == lConv.id ||
                                (xc.otherParticipant?.id != nil && xc.otherParticipant?.id == lConv.otherParticipant?.id)
                            }
                            if !alreadyCovered {
                                mergedConvs.append(lConv)
                            }
                        }
                        
                        // Merge message dictionary
                        for (cid, mList) in legacyMsgs {
                            if mergedMsgs[cid] == nil {
                                mergedMsgs[cid] = mList
                            }
                        }
                    }
                    
                    // Sort conversations: pinned first, then newest sortTimestamp descending
                    mergedConvs.sort {
                        if $0.isPinned != $1.isPinned {
                            return $0.isPinned && !$1.isPinned
                        }
                        return $0.sortTimestamp > $1.sortTimestamp
                    }
                    
                    DispatchQueue.main.async {
                        completion(.success((mergedConvs, mergedMsgs)))
                    }
                }
                
            case .failure(let error):
                dmLog.warning("X Chat GraphQL fetch failed: \(error.localizedDescription), falling back to legacy inbox")
                self.fetchLegacyInbox(completion: completion)
            }
        }
    }
    
    // MARK: - 1a. Fetch Modern X Chat Inbox (GraphQL GetInitialXChatPageQuery)
    
    func fetchXChatInbox(completion: @escaping (Result<([DMConversation], [String: [DMMessage]]), APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let variables: [String: Any] = [
            "max_local_sequence_id": NSNull(),
            "query_settings": [
                "conversation_event_limit": 200,
                "inbox_conversation_event_limit": 5,
                "inbox_conversation_limit": 50,
                "user_event_limit": 500
            ],
            "message_pull_version": NSNull()
        ]
        
        guard let varData = try? JSONSerialization.data(withJSONObject: variables),
              let varStr = String(data: varData, encoding: .utf8),
              let encodedVars = varStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.x.com/graphql/\(initialXChatQueryId)/GetInitialXChatPageQuery?variables=\(encodedVars)") else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.shared.bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(APIClient.shared.userAgent, forHTTPHeaderField: "user-agent")
        
        APIClient.shared.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any],
                      let page = dataDict["get_initial_chat_page"] as? [String: Any],
                      let items = page["items"] as? [[String: Any]] else {
                    completion(.failure(.parseError))
                    return
                }
                
                let activeUserId = AccountManager.shared.activeId ?? ""
                let (convs, msgs) = self.parseXChatItems(items, activeUserId: activeUserId)
                
                completion(.success((convs, msgs)))
            } catch {
                dmLog.error("X Chat initial page JSON error: \(error.localizedDescription)")
                completion(.failure(.parseError))
            }
        }.resume()
    }
    
    // MARK: - 1b. Fetch Legacy REST Inbox (1.1 inbox_initial_state.json)
    
    func fetchLegacyInbox(completion: @escaping (Result<([DMConversation], [String: [DMMessage]]), APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let urlStr = "https://x.com/i/api/1.1/dm/inbox_initial_state.json?" +
            "include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&" +
            "include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&" +
            "include_ext_is_blue_verified=1&include_ext_verified_type=1&include_ext_profile_image_shape=1&" +
            "skip_status=1&dm_secret_conversations_enabled=true&krs_registration_enabled=true&" +
            "cards_platform=Web-12&include_cards=1&include_ext_alt_text=true&include_ext_limited_action_results=true&" +
            "include_quote_count=true&include_reply_count=1&tweet_mode=extended&include_ext_views=true&dm_users=true&include_groups=true"
        
        guard let url = URL(string: urlStr) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.shared.bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(APIClient.shared.userAgent, forHTTPHeaderField: "user-agent")
        
        APIClient.shared.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let inbox = json["inbox_initial_state"] as? [String: Any] else {
                    completion(.failure(.parseError))
                    return
                }
                
                let activeUserId = AccountManager.shared.activeId ?? ""
                let (convs, msgs) = self.parseInboxPayload(inbox, activeUserId: activeUserId)
                
                completion(.success((convs, msgs)))
            } catch {
                dmLog.error("Inbox decode error: \(error.localizedDescription)")
                completion(.failure(.parseError))
            }
        }.resume()
    }
    
    // MARK: - 1c. Fetch User Updates (Latest real-time messages & active conversations)
    
    func fetchUserUpdates(completion: @escaping (Result<([DMConversation], [String: [DMMessage]]), APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let urlStr = "https://x.com/i/api/1.1/dm/user_updates.json?cards_platform=Web-12&include_cards=1&include_ext_alt_text=true&tweet_mode=extended&dm_users=true&include_groups=true"
        guard let url = URL(string: urlStr) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.shared.bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(APIClient.shared.userAgent, forHTTPHeaderField: "user-agent")
        
        APIClient.shared.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let userInbox = json["user_inbox"] as? [String: Any] else {
                    completion(.failure(.parseError))
                    return
                }
                
                let activeUserId = AccountManager.shared.activeId ?? ""
                let (convs, msgs) = self.parseInboxPayload(userInbox, activeUserId: activeUserId)
                
                DispatchQueue.main.async {
                    completion(.success((convs, msgs)))
                }
            } catch {
                dmLog.error("User updates decode error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(.parseError))
                }
            }
        }.resume()
    }
    
    // MARK: - 1d. Fetch DM Events Stream
    
    func fetchDMEvents(completion: @escaping (Result<[DMMessage], APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let urlStr = "https://x.com/i/api/1.1/direct_messages/events/list.json?count=50"
        guard let url = URL(string: urlStr) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.shared.bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(APIClient.shared.userAgent, forHTTPHeaderField: "user-agent")
        
        APIClient.shared.session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = json["events"] as? [[String: Any]] else {
                    completion(.failure(.parseError))
                    return
                }
                
                let activeUserId = AccountManager.shared.activeId ?? ""
                var messages: [DMMessage] = []
                for ev in events {
                    let msgId = (ev["id"] as? String) ?? ""
                    let timeMs = (ev["created_timestamp"] as? String).flatMap(Double.init)
                        ?? Double(ev["created_timestamp"] as? Int64 ?? 0)
                    let date = Date(timeIntervalSince1970: timeMs / 1000.0)
                    let mc = ev["message_create"] as? [String: Any] ?? [:]
                    let senderId = (mc["sender_id"] as? String) ?? ""
                    let target = mc["target"] as? [String: Any] ?? [:]
                    let recipientId = target["recipient_id"] as? String
                    let mData = mc["message_data"] as? [String: Any] ?? [:]
                    let rawText = (mData["text"] as? String) ?? ""
                    let isOutgoing = (senderId == activeUserId)
                    
                    var mediaUrl: String? = nil
                    if let attachment = mData["attachment"] as? [String: Any],
                       let photo = attachment["photo"] as? [String: Any] {
                        mediaUrl = (photo["media_url_https"] as? String) ?? (photo["media_url"] as? String)
                    }
                    
                    let otherId = isOutgoing ? (recipientId ?? "") : senderId
                    let convId = [activeUserId, otherId].sorted().joined(separator: "-")
                    
                    messages.append(
                        DMMessage(
                            id: msgId,
                            conversationId: convId,
                            senderId: senderId,
                            recipientId: recipientId,
                            text: rawText,
                            createdAt: date,
                            isOutgoing: isOutgoing,
                            mediaUrl: mediaUrl
                        )
                    )
                }
                
                DispatchQueue.main.async {
                    completion(.success(messages))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.parseError))
                }
            }
        }.resume()
    }
    
    // MARK: - 2. Fetch Conversation History (Auto-routing GraphQL vs Legacy)
    
    func fetchConversation(
        conversationId: String,
        maxId: String? = nil,
        completion: @escaping (Result<[DMMessage], APIError>) -> Void
    ) {
        if conversationId.contains(":") {
            fetchXChatConversation(conversationId: conversationId, minSequenceId: maxId, completion: completion)
        } else {
            fetchLegacyConversation(conversationId: conversationId, maxId: maxId, completion: completion)
        }
    }
    
    // MARK: - 2a. Fetch X Chat Conversation Page (GraphQL GetConversationPageQuery)
    
    func fetchXChatConversation(
        conversationId: String,
        minSequenceId: String? = nil,
        completion: @escaping (Result<[DMMessage], APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let variables: [String: Any] = [
            "conversation_id": conversationId,
            "min_local_sequence_id": minSequenceId ?? "9223372036854775807",
            "min_conversation_key_version": "9223372036854775807",
            "query_settings": [
                "conversation_event_limit": 200,
                "inbox_conversation_event_limit": 5,
                "inbox_conversation_limit": 20,
                "user_event_limit": 500
            ]
        ]
        
        guard let varData = try? JSONSerialization.data(withJSONObject: variables),
              let varStr = String(data: varData, encoding: .utf8),
              let encodedVars = varStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.x.com/graphql/\(conversationPageQueryId)/GetConversationPageQuery?variables=\(encodedVars)") else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.shared.bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(APIClient.shared.userAgent, forHTTPHeaderField: "user-agent")
        
        APIClient.shared.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any],
                      let convPage = dataDict["get_conversation_page"] as? [String: Any],
                      let encodedEvents = convPage["encoded_message_events"] as? [String] else {
                    completion(.failure(.parseError))
                    return
                }
                
                let activeUserId = AccountManager.shared.activeId ?? ""
                
                // Parse missing conversation key change events first if provided
                if let missingKeys = convPage["missing_conversation_key_change_events"] as? [String] {
                    for kEv in missingKeys {
                        if let (kVer, encPayload) = self.parseKeyChangeEvent(base64: kEv, activeUserId: activeUserId) {
                            DMViewModel.shared.rawConversationKeyEvents[kVer] = encPayload
                            if let privKey = DMViewModel.shared.privateKey, DMViewModel.shared.conversationKeys[kVer] == nil {
                                if let convKey = self.decryptConversationKey(data: encPayload, privateKey: privKey) {
                                    DMViewModel.shared.conversationKeys[kVer] = convKey
                                }
                            }
                        }
                    }
                }
                
                var messages: [DMMessage] = []
                for b64 in encodedEvents {
                    if let parsed = self.parseXChatEvent(base64: b64, activeUserId: activeUserId) {
                        messages.append(parsed)
                    }
                }
                
                messages.sort { $0.createdAt < $1.createdAt }
                
                DispatchQueue.main.async {
                    completion(.success(messages))
                }
            } catch {
                dmLog.error("X Chat conversation decode error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(.parseError))
                }
            }
        }.resume()
    }
    
    // MARK: - 2b. Fetch Legacy Conversation History (1.1 dm/conversation/...)
    
    func fetchLegacyConversation(
        conversationId: String,
        maxId: String? = nil,
        completion: @escaping (Result<[DMMessage], APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        var urlStr = "https://x.com/i/api/1.1/dm/conversation/\(conversationId).json?" +
            "include_profile_interstitial_type=1&cards_platform=Web-12&include_cards=1&" +
            "include_ext_alt_text=true&tweet_mode=extended&dm_users=true"
        if let maxId = maxId {
            urlStr += "&max_id=\(maxId)"
        }
        
        guard let url = URL(string: urlStr) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.shared.bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(APIClient.shared.userAgent, forHTTPHeaderField: "user-agent")
        
        APIClient.shared.session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let convTimeline = json["conversation_timeline"] as? [String: Any] else {
                    completion(.failure(.parseError))
                    return
                }
                
                let activeUserId = AccountManager.shared.activeId ?? ""
                var messages: [DMMessage] = []
                
                if let entries = convTimeline["entries"] as? [[String: Any]] {
                    for entry in entries {
                        if let msg = entry["message"] as? [String: Any] {
                            let msgId = (msg["id"] as? String) ?? "\(msg["id"] as? Int64 ?? 0)"
                            let convId = (msg["conversation_id"] as? String) ?? conversationId
                            let timeMs = (msg["time"] as? String).flatMap(Double.init)
                                ?? Double(msg["time"] as? Int64 ?? 0)
                            let date = Date(timeIntervalSince1970: timeMs / 1000.0)
                            
                            let mData = msg["message_data"] as? [String: Any] ?? [:]
                            let text = (mData["text"] as? String) ?? ""
                            let senderId = (mData["sender_id"] as? String) ?? ""
                            let recipientId = mData["recipient_id"] as? String
                            let isOutgoing = (senderId == activeUserId)
                            
                            var mediaUrl: String? = nil
                            if let attachment = mData["attachment"] as? [String: Any] {
                                if let photo = attachment["photo"] as? [String: Any] {
                                    mediaUrl = (photo["media_url_https"] as? String) ?? (photo["media_url"] as? String)
                                } else if let video = attachment["video"] as? [String: Any] {
                                    mediaUrl = (video["media_url_https"] as? String) ?? (video["media_url"] as? String)
                                }
                            }
                            
                            messages.append(
                                DMMessage(
                                    id: msgId,
                                    conversationId: convId,
                                    senderId: senderId,
                                    recipientId: recipientId,
                                    text: text,
                                    createdAt: date,
                                    isOutgoing: isOutgoing,
                                    mediaUrl: mediaUrl
                                )
                            )
                        }
                    }
                }
                
                messages.sort { $0.createdAt < $1.createdAt }
                
                DispatchQueue.main.async {
                    completion(.success(messages))
                }
            } catch {
                dmLog.error("Conversation decode error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(.parseError))
                }
            }
        }.resume()
    }
    
    // MARK: - 3. Parse X Chat Items into DMConversations & DMMessages
    
    private func parseXChatItems(_ items: [[String: Any]], activeUserId: String) -> ([DMConversation], [String: [DMMessage]]) {
        var convList: [DMConversation] = []
        var messagesByConv: [String: [DMMessage]] = [:]
        let pinnedIds = Set(UserDefaults.standard.stringArray(forKey: "com.anno.tweetintosh.dm.pinned") ?? [])
        
        for item in items {
            guard let cd = item["conversation_detail"] as? [String: Any],
                  let convId = cd["conversation_id"] as? String else {
                continue
            }
            
            let isMuted = (cd["is_muted"] as? Bool) ?? false
            let isPinned = pinnedIds.contains(convId)
            
            // 1. Parse Participants
            var participants: [DMParticipant] = []
            if let pResults = cd["participants_results"] as? [[String: Any]] {
                for pr in pResults {
                    let restId = pr["rest_id"] as? String ?? ""
                    let uResult = pr["result"] as? [String: Any] ?? [:]
                    let core = uResult["core"] as? [String: Any]
                    let name = core?["name"] as? String ?? uResult["name"] as? String ?? restId
                    let screenName = core?["screen_name"] as? String ?? uResult["screen_name"] as? String ?? ""
                    
                    var avatar: String? = nil
                    if let av = uResult["avatar"] as? [String: Any] {
                        avatar = av["image_url"] as? String
                    } else if let leg = uResult["legacy"] as? [String: Any] {
                        avatar = leg["profile_image_url_https"] as? String
                    }
                    
                    let isBlue = (uResult["is_blue_verified"] as? Bool) ?? ((uResult["verification"] as? [String: Any])?["is_blue_verified"] as? Bool ?? false)
                    let isVer = (uResult["verified"] as? Bool) ?? isBlue
                    
                    participants.append(
                        DMParticipant(
                            id: restId,
                            name: name,
                            screenName: screenName,
                            avatarUrl: avatar,
                            isBlueVerified: isBlue,
                            isVerified: isVer
                        )
                    )
                }
            }
            
            let other = participants.first { $0.id != activeUserId } ?? participants.first
            
            // 2. Parse Key Change Events to register conversation keys
            if let keyEvents = item["latest_conversation_key_change_events"] as? [String] {
                for kEv in keyEvents {
                    if let (kVer, encPayload) = self.parseKeyChangeEvent(base64: kEv, activeUserId: activeUserId) {
                        DMViewModel.shared.rawConversationKeyEvents[kVer] = encPayload
                        if let privKey = DMViewModel.shared.privateKey, DMViewModel.shared.conversationKeys[kVer] == nil {
                            if let convKey = self.decryptConversationKey(data: encPayload, privateKey: privKey) {
                                DMViewModel.shared.conversationKeys[kVer] = convKey
                            }
                        }
                    }
                }
            }
            
            // 3. Parse Messages in latest_message_events
            var parsedMsgs: [DMMessage] = []
            let evs = item["latest_message_events"] as? [String] ?? []
            for b64 in evs {
                if let parsed = parseXChatEvent(base64: b64, activeUserId: activeUserId) {
                    parsedMsgs.append(parsed)
                }
            }
            
            parsedMsgs.sort { $0.createdAt < $1.createdAt }
            messagesByConv[convId] = parsedMsgs
            
            // 4. Compute Sort Timestamp
            var sortDate = Date.distantPast
            if let lastParsed = parsedMsgs.last {
                sortDate = lastParsed.createdAt
            }
            if let notifB64 = item["latest_notifiable_message_create_event"] as? String,
               let notifMsg = parseXChatEvent(base64: notifB64, activeUserId: activeUserId) {
                if notifMsg.createdAt > sortDate {
                    sortDate = notifMsg.createdAt
                }
            }
            
            let lastMsg = DMMessage.latestListed(in: parsedMsgs)
            let hasEncrypted = parsedMsgs.contains { $0.isEncrypted }
            
            convList.append(
                DMConversation(
                    id: convId,
                    type: .oneToOne,
                    participants: participants,
                    otherParticipant: other,
                    lastMessage: lastMsg,
                    lastReadEventId: nil,
                    sortTimestamp: sortDate,
                    isMuted: isMuted,
                    isTrusted: true,
                    isPinned: isPinned,
                    unreadCount: 0,
                    hasEncryptedMessages: hasEncrypted
                )
            )
        }
        
        return (convList, messagesByConv)
    }
    
    // MARK: - 4. Parse Thrift Binary Encoded X Chat Event
    
    func parseXChatEvent(base64: String, activeUserId: String) -> DMMessage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        var reader = ThriftBinaryReader(data: data)
        var msg = ParsedXChatMessage()
        
        while let fType = reader.readByte(), fType != 0 {
            guard let fId = reader.readInt16() else { break }
            switch fId {
            case 1:
                if fType == 11, let s = reader.readString() { msg.eventId = s } else { reader.skip(type: fType) }
            case 2:
                if fType == 11, let s = reader.readString() { msg.messageId = s } else { reader.skip(type: fType) }
            case 3:
                if fType == 11, let s = reader.readString() { msg.senderId = s } else { reader.skip(type: fType) }
            case 4:
                if fType == 11, let s = reader.readString() { msg.conversationId = s } else { reader.skip(type: fType) }
            case 5:
                if fType == 11, let s = reader.readString() { msg.conversationToken = s } else { reader.skip(type: fType) }
            case 6:
                if fType == 11, let s = reader.readString(), let t = Int64(s) { msg.timestampMs = t } else { reader.skip(type: fType) }
            case 7:
                if fType == 12 {
                    parsePayloadStruct(&reader, msg: &msg)
                } else {
                    reader.skip(type: fType)
                }
            default:
                reader.skip(type: fType)
            }
        }
        
        // Sending needs the conversation's token and the key versions in use; every event can carry them.
        if !msg.conversationId.isEmpty {
            if let token = msg.conversationToken, !token.isEmpty {
                XChatConversationState.shared.recordToken(token, conversationId: msg.conversationId, sequenceId: msg.eventId)
            }
            if let version = msg.keyVersion {
                XChatConversationState.shared.recordKeyVersion(version, conversationId: msg.conversationId)
            }
        }
        
        // A read receipt is not a chat entry, but its sender and time say who saw which messages, which the
        // message Info card reports.
        if msg.isReadReceipt, !msg.conversationId.isEmpty, !msg.senderId.isEmpty, msg.timestampMs > 0 {
            DMReadReceiptStore.shared.record(DMReadReceipt(
                eventId: msg.eventId.isEmpty ? "\(msg.senderId)-\(msg.timestampMs)" : msg.eventId,
                conversationId: msg.conversationId,
                readerId: msg.senderId,
                readAt: Date(timeIntervalSince1970: Double(msg.timestampMs) / 1000.0)
            ))
        }
        
        // Only events carrying actual message payloads (pId == 1) should be presented as chat entries.
        // Read receipts (pId == 12), reactions, and typing signals must not create dummy message bubbles.
        // Deletions (pId == 7) come back as entries too, so the chat can drop the messages they name.
        guard msg.hasMessagePayload || msg.isDelete else { return nil }
        
        let date = msg.timestampMs > 0 ? Date(timeIntervalSince1970: Double(msg.timestampMs) / 1000.0) : Date()
        let isOutgoing = (msg.senderId == activeUserId)
        let resolvedId = msg.messageId.isEmpty ? (msg.eventId.isEmpty ? UUID().uuidString : msg.eventId) : msg.messageId
        
        var isActuallyEncrypted = msg.isEncrypted
        var content = msg.decoded
        
        if isActuallyEncrypted, let raw = msg.rawCiphertext {
            if let cached = DMViewModel.shared.decryptedMessageCache[resolvedId] ?? DMViewModel.shared.decryptedMessageCache[msg.eventId] {
                content = cached
                isActuallyEncrypted = false
            } else {
                var convKey: Data? = nil
                if let keyVer = msg.keyVersion {
                    convKey = DMViewModel.shared.conversationKeys[keyVer]
                    if convKey == nil, let privKey = DMViewModel.shared.privateKey, let rawKey = DMViewModel.shared.rawConversationKeyEvents[keyVer] {
                        convKey = decryptConversationKey(data: rawKey, privateKey: privKey)
                        if let k = convKey {
                            DMViewModel.shared.conversationKeys[keyVer] = k
                        }
                    }
                }
                
                if let k = convKey, let decrypted = decryptMessagePayload(rawBinary: raw, conversationKey: k) {
                    content = decrypted
                    isActuallyEncrypted = false
                    DMViewModel.shared.decryptedMessageCache[resolvedId] = decrypted
                } else {
                    // Robust fallback: try all known conversation keys
                    for k in DMViewModel.shared.conversationKeys.values {
                        if let decrypted = decryptMessagePayload(rawBinary: raw, conversationKey: k) {
                            content = decrypted
                            isActuallyEncrypted = false
                            DMViewModel.shared.decryptedMessageCache[resolvedId] = decrypted
                            break
                        }
                    }
                }
            }
        }
        
        let rawB64 = msg.rawCiphertext?.base64EncodedString()
        
        var message = DMMessage(
            id: resolvedId,
            conversationId: msg.conversationId,
            senderId: msg.senderId,
            recipientId: nil,
            text: content.text,
            createdAt: date,
            isOutgoing: isOutgoing,
            mediaUrl: msg.mediaUrl,
            isEncrypted: isActuallyEncrypted,
            rawCiphertextBase64: rawB64,
            keyVersion: msg.keyVersion,
            sequenceId: msg.eventId.isEmpty ? nil : msg.eventId,
            entryKind: content.kind,
            targetSequenceId: content.targetSequenceId,
            emoji: content.emoji,
            readAt: content.readAt
        )
        message.apply(content)
        return message
    }
    
    // MARK: - End-to-End Encryption Decryption Pipeline (X Chat 2-Tier Hierarchy)
    
    /// Tier 1: Decrypts 113-byte encrypted conversation key using recipient's P-256 private key via ECDH + SHA-256 HKDF + AES-GCM
    func decryptConversationKey(data: Data, privateKey: P256.KeyAgreement.PrivateKey) -> Data? {
        guard data.count >= 65 + 16 else { return nil }
        let ephemPubBytes = data.prefix(65)
        let ciphertextAndTag = data.dropFirst(65)
        
        do {
            let ephemPub = try P256.KeyAgreement.PublicKey(x963Representation: ephemPubBytes)
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemPub)
            
            var kdfInput = Data()
            sharedSecret.withUnsafeBytes { kdfInput.append(contentsOf: $0) }
            kdfInput.append(Data([0, 0, 0, 1]))
            kdfInput.append(ephemPubBytes)
            
            let hash = SHA256.hash(data: kdfInput)
            let hashData = Data(hash)
            let aesKey = SymmetricKey(data: hashData.prefix(16))
            let iv = hashData.subdata(in: 16..<32)
            let nonce = try AES.GCM.Nonce(data: iv)
            
            let ciphertext = ciphertextAndTag.dropLast(16)
            let tag = ciphertextAndTag.suffix(16)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let decryptedConvKey = try AES.GCM.open(box, using: aesKey)
            return decryptedConvKey
        } catch {
            dmLog.debug("Conversation key decryption error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Tier 2: Decrypts message contents payload (Field 100) using 32-byte conversation key via XSalsa20-Poly1305 (Libsodium secretbox)
    func decryptMessagePayload(rawBinary: Data, conversationKey: Data) -> DMDecodedContent? {
        guard rawBinary.count > 24 + 16 else { return nil }
        let nonce = rawBinary.prefix(24)
        let box = rawBinary.dropFirst(24) // 16-byte MAC followed by ciphertext
        
        guard let decryptedThrift = XSalsa20Poly1305.open(box: box, nonce: nonce, key: conversationKey) else {
            return nil
        }
        
        // Anything that is not a recognised entry decodes as `.other` and stays out of the chat, rather than
        // its raw bytes being shown as text (a read receipt used to appear as its sequence id).
        var innerReader = ThriftBinaryReader(data: decryptedThrift)
        return decodeEntryHolder(&innerReader)
    }
    
    /// Parses Thrift binary encoded KeyChangeEvent to extract (conversationKeyVersion, encryptedPayload) for the active user.
    func parseKeyChangeEvent(base64: String, activeUserId: String) -> (keyVersion: String, encryptedPayload: Data)? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        var reader = ThriftBinaryReader(data: data)
        var keyVersion: String? = nil
        var encryptedPayload: Data? = nil
        var conversationId: String? = nil
        
        while let fType = reader.readByte(), fType != 0 {
            guard let fId = reader.readInt16() else { break }
            if fId == 4 && fType == 11 {
                conversationId = reader.readString()
            } else if fId == 7 && fType == 12 {
                while let pType = reader.readByte(), pType != 0 {
                    guard let pId = reader.readInt16() else { break }
                    if pId == 3 && pType == 12 {
                        while let kType = reader.readByte(), kType != 0 {
                            guard let kId = reader.readInt16() else { break }
                            if kId == 1 && kType == 11 {
                                keyVersion = reader.readString()
                            } else if kId == 2 && kType == 15 {
                                guard let elemType = reader.readByte(), elemType == 12,
                                      let count = reader.readInt32(), count > 0 else {
                                    reader.skip(type: kType)
                                    continue
                                }
                                for _ in 0..<count {
                                    var pUid: String? = nil
                                    var pEncData: Data? = nil
                                    while let mType = reader.readByte(), mType != 0 {
                                        guard let mId = reader.readInt16() else { break }
                                        if mId == 1 && mType == 11 {
                                            pUid = reader.readString()
                                        } else if mId == 2 && mType == 11 {
                                            if let bin = reader.readBinary() {
                                                if bin.count == 113 {
                                                    pEncData = bin
                                                } else if let str = String(data: bin, encoding: .utf8),
                                                          let b64 = Data(base64Encoded: str) {
                                                    pEncData = b64
                                                } else if let b64 = Data(base64Encoded: bin) {
                                                    pEncData = b64
                                                }
                                            }
                                        } else {
                                            reader.skip(type: mType)
                                        }
                                    }
                                    if pUid == activeUserId, let enc = pEncData {
                                        encryptedPayload = enc
                                    }
                                }
                            } else {
                                reader.skip(type: kType)
                            }
                        }
                    } else {
                        reader.skip(type: pType)
                    }
                }
            } else {
                reader.skip(type: fType)
            }
        }
        guard let ver = keyVersion, let payload = encryptedPayload else { return nil }
        if let conversationId {
            XChatConversationState.shared.recordKeyVersion(ver, conversationId: conversationId)
        }
        return (ver, payload)
    }
    
    private func parsePayloadStruct(_ reader: inout ThriftBinaryReader, msg: inout ParsedXChatMessage) {
        while let pType = reader.readByte(), pType != 0 {
            guard let pId = reader.readInt16() else { break }
            if pId == 1 && pType == 12 {
                // pId == 1 is the ONLY event payload that represents message create!
                msg.hasMessagePayload = true
                parseMessageCreatePayload(&reader, msg: &msg)
            } else if pId == 7 && pType == 12 {
                // MessageDeleteEvent { 1: list<string> sequence_ids, 2: delete_message_action }
                msg.isDelete = true
                var ids: [String] = []
                while let dType = reader.readByte(), dType != 0 {
                    guard let dId = reader.readInt16() else { break }
                    if dId == 1 && dType == 15, let elem = reader.readByte(), let count = reader.readInt32() {
                        for _ in 0..<max(0, Int(count)) {
                            if elem == 11, let s = reader.readString() { ids.append(s) } else { reader.skip(type: elem) }
                        }
                    } else {
                        reader.skip(type: dType)
                    }
                }
                msg.decoded = DMDecodedContent(kind: .delete, deletedSequenceIds: ids)
            } else {
                // Read receipts (pId == 12) only matter for who sent them and when, which the event header holds.
                // Typing indicators and the rest are ignored.
                if pId == 12 { msg.isReadReceipt = true }
                reader.skip(type: pType)
            }
        }
    }
    
    private func parseMessageCreatePayload(_ reader: inout ThriftBinaryReader, msg: inout ParsedXChatMessage) {
        var rawBinary: Data? = nil
        var keyVersion: String? = nil
        var contentsEncryptionVer: Int16? = nil
        
        while let uType = reader.readByte(), uType != 0 {
            guard let uId = reader.readInt16() else { break }
            switch uId {
            case 100: // contents
                if uType == 11 {
                    rawBinary = reader.readBinary()
                } else {
                    reader.skip(type: uType)
                }
            case 101: // conversation_key_version
                if uType == 11 {
                    keyVersion = reader.readString()
                } else {
                    reader.skip(type: uType)
                }
            case 102: // should_notify (Bool)
                _ = reader.readBool()
            case 112: // contents_encryption_version (Int16)
                if uType == 6 {
                    contentsEncryptionVer = reader.readInt16()
                } else {
                    reader.skip(type: uType)
                }
            default:
                reader.skip(type: uType)
            }
        }
        
        let isEncrypted = (keyVersion != nil || contentsEncryptionVer != nil)
        msg.isEncrypted = isEncrypted
        msg.keyVersion = keyVersion
        msg.rawCiphertext = rawBinary
        
        if let bin = rawBinary, !isEncrypted {
            var innerReader = ThriftBinaryReader(data: bin)
            msg.decoded = decodeEntryHolder(&innerReader)
        }
    }
    
    // MARK: Entry Contents
    
    /// MessageEntryHolder { 1: MessageEntryContents }.
    private func decodeEntryHolder(_ reader: inout ThriftBinaryReader) -> DMDecodedContent {
        var content = DMDecodedContent(kind: .other)
        while let t = reader.readByte(), t != 0 {
            guard let id = reader.readInt16() else { break }
            if id == 1 && t == 12 {
                content = decodeEntryContents(&reader)
            } else {
                reader.skip(type: t)
            }
        }
        return content
    }
    
    /// MessageEntryContents is a union: 1 message, 2 reaction_add, 3 reaction_remove, 4 message_edit,
    /// 5 mark_conversation_read, and kinds the chat does not show (pins, calls, drafts, screen captures…).
    /// Reactions, edits and read marks are kept as structured entries so the chat can apply them to the message
    /// they name instead of drawing them as messages.
    private func decodeEntryContents(_ reader: inout ThriftBinaryReader) -> DMDecodedContent {
        var content = DMDecodedContent(kind: .other)
        while let t = reader.readByte(), t != 0 {
            guard let id = reader.readInt16() else { break }
            guard t == 12 else {
                reader.skip(type: t)
                continue
            }
            switch id {
            case 1:
                content = decodeMessageContents(&reader)
            case 2, 3:
                let f = readScalarFields(&reader)
                content = DMDecodedContent(kind: id == 2 ? .reaction : .reactionRemove, targetSequenceId: f.strings[1], emoji: f.strings[2])
            case 4:
                let f = readScalarFields(&reader)
                content = DMDecodedContent(kind: .edit, text: f.strings[2] ?? "", targetSequenceId: f.strings[1])
            case 5:
                let f = readScalarFields(&reader)
                let readAt = f.ints[2].map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
                content = DMDecodedContent(kind: .read, targetSequenceId: f.strings[1], readAt: readAt)
            default:
                reader.skip(type: t)
            }
        }
        return content
    }
    
    /// MessageContents { 1: message_text, 4: replying_to_preview, 6: forwarded_message, … }. A forward carries
    /// the original's text in its own block and usually no text of its own.
    private func decodeMessageContents(_ reader: inout ThriftBinaryReader) -> DMDecodedContent {
        var content = DMDecodedContent(kind: .message)
        var forwardedText = ""
        while let t = reader.readByte(), t != 0 {
            guard let id = reader.readInt16() else { break }
            if id == 1 && t == 11 {
                content.text = reader.readString() ?? ""
            } else if id == 4 && t == 12 {
                // ReplyingToPreview { 1: sender_id (i64), 2: message_text, 5: sender_display_name,
                // 6: replying_to_message_sequence_id, 7: replying_to_message_id, … }
                let f = readScalarFields(&reader)
                content.replyPreview = DMReplyPreview(
                    senderId: f.strings[1] ?? "",
                    senderName: f.strings[5] ?? "",
                    text: f.strings[2] ?? "",
                    sequenceId: f.strings[6],
                    messageId: f.strings[7]
                )
            } else if id == 6 && t == 12 {
                content.isForwarded = true
                forwardedText = readScalarFields(&reader).strings[1] ?? ""
            } else {
                reader.skip(type: t)
            }
        }
        if content.text.isEmpty { content.text = forwardedText }
        return content
    }
    
    /// A struct's string and i64 fields; sequence ids are strings, but older clients may send them as i64.
    private func readScalarFields(_ reader: inout ThriftBinaryReader) -> (strings: [Int16: String], ints: [Int16: Int64]) {
        var strings: [Int16: String] = [:]
        var ints: [Int16: Int64] = [:]
        while let t = reader.readByte(), t != 0 {
            guard let id = reader.readInt16() else { break }
            if t == 11, let s = reader.readString() {
                strings[id] = s
            } else if t == 10, let v = reader.readInt64() {
                ints[id] = v
                if strings[id] == nil { strings[id] = String(v) }
            } else {
                reader.skip(type: t)
            }
        }
        return (strings, ints)
    }
    
    // MARK: - 5. Legacy REST Payload Parser Helper
    
    private func parseInboxPayload(_ dict: [String: Any], activeUserId: String) -> ([DMConversation], [String: [DMMessage]]) {
        var usersMap: [String: DMParticipant] = [:]
        if let rawUsers = dict["users"] as? [String: [String: Any]] {
            for (uid, uDict) in rawUsers {
                let name = (uDict["name"] as? String) ?? ""
                let screenName = (uDict["screen_name"] as? String) ?? ""
                let avatar = (uDict["profile_image_url_https"] as? String) ?? (uDict["profile_image_url"] as? String)
                let isBlue = (uDict["is_blue_verified"] as? Bool) ?? false
                let isVerified = (uDict["verified"] as? Bool) ?? false
                usersMap[uid] = DMParticipant(
                    id: uid,
                    name: name,
                    screenName: screenName,
                    avatarUrl: avatar,
                    isBlueVerified: isBlue,
                    isVerified: isVerified
                )
            }
        }
        
        var messagesByConv: [String: [DMMessage]] = [:]
        if let entries = dict["entries"] as? [[String: Any]] {
            for entry in entries {
                if let msg = entry["message"] as? [String: Any] {
                    let msgId = (msg["id"] as? String) ?? "\(msg["id"] as? Int64 ?? 0)"
                    let convId = (msg["conversation_id"] as? String) ?? ""
                    let timeMs = (msg["time"] as? String).flatMap(Double.init)
                        ?? Double(msg["time"] as? Int64 ?? 0)
                    let date = Date(timeIntervalSince1970: timeMs / 1000.0)
                    
                    let mData = msg["message_data"] as? [String: Any] ?? [:]
                    let text = (mData["text"] as? String) ?? ""
                    let senderId = (mData["sender_id"] as? String) ?? ""
                    let recipientId = mData["recipient_id"] as? String
                    let isOutgoing = (senderId == activeUserId)
                    
                    var mediaUrl: String? = nil
                    if let attachment = mData["attachment"] as? [String: Any] {
                        if let photo = attachment["photo"] as? [String: Any] {
                            mediaUrl = (photo["media_url_https"] as? String) ?? (photo["media_url"] as? String)
                        } else if let video = attachment["video"] as? [String: Any] {
                            mediaUrl = (video["media_url_https"] as? String) ?? (video["media_url"] as? String)
                        }
                    }
                    
                    let messageObj = DMMessage(
                        id: msgId,
                        conversationId: convId,
                        senderId: senderId,
                        recipientId: recipientId,
                        text: text,
                        createdAt: date,
                        isOutgoing: isOutgoing,
                        mediaUrl: mediaUrl
                    )
                    
                    messagesByConv[convId, default: []].append(messageObj)
                }
            }
        }
        
        for (cid, msgs) in messagesByConv {
            messagesByConv[cid] = msgs.sorted { $0.createdAt < $1.createdAt }
        }
        
        var convList: [DMConversation] = []
        let pinnedIds = Set(UserDefaults.standard.stringArray(forKey: "com.anno.tweetintosh.dm.pinned") ?? [])
        
        if let rawConvs = dict["conversations"] as? [String: [String: Any]] {
            for (cid, cDict) in rawConvs {
                let typeRaw = (cDict["type"] as? String) ?? "ONE_TO_ONE"
                let type: DMConversationType = (typeRaw == "GROUP_DM") ? .group : .oneToOne
                
                var participants: [DMParticipant] = []
                if let pArray = cDict["participants"] as? [[String: Any]] {
                    for pItem in pArray {
                        if let pUid = pItem["user_id"] as? String, let pUser = usersMap[pUid] {
                            participants.append(pUser)
                        }
                    }
                }
                
                let other = participants.first { $0.id != activeUserId } ?? participants.first
                
                let sortMs = (cDict["sort_timestamp"] as? String).flatMap(Double.init)
                    ?? Double(cDict["sort_timestamp"] as? Int64 ?? 0)
                let sortDate = Date(timeIntervalSince1970: sortMs / 1000.0)
                
                let lastRead = cDict["last_read_event_id"] as? String
                let isMuted = (cDict["muted"] as? Bool) ?? false
                let isTrusted = (cDict["trusted"] as? Bool) ?? true
                let isPinned = pinnedIds.contains(cid)
                
                let lastMsg = messagesByConv[cid]?.last
                
                convList.append(
                    DMConversation(
                        id: cid,
                        type: type,
                        participants: participants,
                        otherParticipant: other,
                        lastMessage: lastMsg,
                        lastReadEventId: lastRead,
                        sortTimestamp: sortDate,
                        isMuted: isMuted,
                        isTrusted: isTrusted,
                        isPinned: isPinned,
                        unreadCount: 0
                    )
                )
            }
        }
        
        convList.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.sortTimestamp > $1.sortTimestamp
        }
        
        return (convList, messagesByConv)
    }
    
    // MARK: - 6. Send Outbound Message (via WebKitWriteChannel)
    
    func sendMessage(
        conversationId: String,
        text: String,
        mediaUrls: [String] = [],
        completion: @escaping (Result<DMMessage, APIError>) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !mediaUrls.isEmpty else {
            completion(.failure(.invalidResponse))
            return
        }
        
        let requestId = UUID().uuidString
        var body: [String: Any] = [
            "conversation_id": conversationId,
            "recipient_ids": false,
            "request_id": requestId,
            "text": trimmed,
            "cards_platform": "Web-12",
            "include_cards": 1,
            "include_quote_count": true,
            "dm_users": false
        ]
        
        if let firstMedia = mediaUrls.first {
            body["media_id"] = firstMedia
        }
        
        let activeUserId = AccountManager.shared.activeId ?? ""
        let optimisticMessage = DMMessage(
            id: "temp-\(UUID().uuidString)",
            conversationId: conversationId,
            senderId: activeUserId,
            recipientId: nil,
            text: trimmed,
            createdAt: Date(),
            isOutgoing: true,
            mediaUrl: mediaUrls.first
        )
        
        WebKitWriteChannel.shared.perform(path: "/i/api/1.1/dm/new2.json", body: body) { result in
            switch result {
            case .success(let json):
                dmLog.debug("DM sent successfully: \(json.keys)")
                completion(.success(optimisticMessage))
            case .failure(let error):
                dmLog.error("Failed to send DM: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
}

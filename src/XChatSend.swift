//
//  XChatSend.swift
//  Tweetintosh
//
//  Sending an end-to-end encrypted X Chat message, built the way x.com's own chat client builds it:
//
//  1. The text is serialised as a MessageEntryHolder (Thrift binary) and sealed with the conversation key
//     (XSalsa20-Poly1305, a random 24-byte nonce in front).
//  2. Franking data lets a recipient report the message: a random 32-byte nonce sealed with the same key, and
//     SHA-256("xchat-franking" ‖ SHA-256(plaintext) ‖ media count ‖ media hashes ‖ nonce ‖ message id ‖
//     conversation id length ‖ conversation id) as the tag.
//  3. The MessageCreateEvent is signed with the account's signing key (ECDSA P-256 over SHA-256), signature
//     version 7: "MessageCreateEvent,<message id>,<sender>,<conversation>,<key version>,<base64 contents>".
//  4. SendMessageCreateMutation posts both, through the web view like every other write.
//
//  Each step was checked against a message sent from x.com: the plaintext bytes, the franking tag and the
//  signature all reproduce.
//

import Foundation
import CryptoKit

// MARK: - Thrift Binary Writer

struct ThriftBinaryWriter {
    private(set) var data = Data()

    private mutating func header(_ id: Int16, type: UInt8) {
        data.append(type)
        append16(id)
    }

    private mutating func append16(_ v: Int16) {
        withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) }
    }

    private mutating func append32(_ v: Int32) {
        withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func binary(_ id: Int16, _ value: Data) {
        header(id, type: 11)
        append32(Int32(value.count))
        data.append(value)
    }

    mutating func string(_ id: Int16, _ value: String) {
        binary(id, Data(value.utf8))
    }

    mutating func bool(_ id: Int16, _ value: Bool) {
        header(id, type: 2)
        data.append(value ? 1 : 0)
    }

    mutating func i32(_ id: Int16, _ value: Int32) {
        header(id, type: 8)
        append32(value)
    }

    mutating func i64(_ id: Int16, _ value: Int64) {
        header(id, type: 10)
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func stringList(_ id: Int16, _ values: [String]) {
        header(id, type: 15)
        data.append(11)
        append32(Int32(values.count))
        for v in values {
            let bytes = Data(v.utf8)
            append32(Int32(bytes.count))
            data.append(bytes)
        }
    }

    mutating func structure(_ id: Int16, _ build: (inout ThriftBinaryWriter) -> Void) {
        header(id, type: 12)
        var inner = ThriftBinaryWriter()
        build(&inner)
        data.append(inner.finished)
    }

    mutating func structList(_ id: Int16, _ items: [(inout ThriftBinaryWriter) -> Void]) {
        header(id, type: 15)
        data.append(12)
        append32(Int32(items.count))
        for build in items {
            var inner = ThriftBinaryWriter()
            build(&inner)
            data.append(inner.finished)
        }
    }

    /// The struct with its stop byte.
    var finished: Data { data + [0] }
}

// MARK: - Per-conversation Send State

/// What decoding learns about each conversation that sending needs: the conversation token X hands out and the
/// conversation key versions in use. Decoding runs off the main thread, so access is locked.
final class XChatConversationState {
    static let shared = XChatConversationState()
    private init() {}

    private let lock = NSLock()
    private var tokens: [String: (token: String, sequence: Int64)] = [:]
    private var keyVersions: [String: Set<String>] = [:]

    /// Keeps the token from the newest event, as x.com does.
    func recordToken(_ token: String, conversationId: String, sequenceId: String) {
        let sequence = Int64(sequenceId) ?? 0
        lock.lock()
        if let known = tokens[conversationId], known.sequence > sequence {
            lock.unlock()
            return
        }
        tokens[conversationId] = (token, sequence)
        lock.unlock()
    }

    func token(for conversationId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return tokens[conversationId]?.token
    }

    func recordKeyVersion(_ version: String, conversationId: String) {
        lock.lock()
        keyVersions[conversationId, default: []].insert(version)
        lock.unlock()
    }

    func keyVersions(for conversationId: String) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return keyVersions[conversationId] ?? []
    }

    /// A different account's chats may share an id with these, and its tokens are not theirs.
    func reset() {
        lock.lock()
        tokens = [:]
        keyVersions = [:]
        lock.unlock()
    }
}

// MARK: - Outgoing Message

/// Everything a send needs from the unlocked account.
struct XChatSendKeys {
    let conversationKey: Data
    let conversationKeyVersion: String
    let signingKey: P256.Signing.PrivateKey
    let signingKeyVersion: String
}

enum XChatOutgoing {
    /// The signature scheme x.com uses for messages today.
    static let signatureVersion = "7"

    struct Built {
        let encodedCreateEvent: Data
        let encodedSignature: Data
    }

    /// What a MessageCreateEvent carries. Everything but deletion travels this way, encrypted and signed alike.
    enum Entry {
        case text(String, replyingTo: DMReplyPreview?)
        case forward(String)
        case reaction(targetSequenceId: String, emoji: String)
        case reactionRemove(targetSequenceId: String, emoji: String)
    }

    /// The plaintext of an entry: MessageEntryHolder { contents: MessageEntryContents { … } }. A message is
    /// MessageContents { message_text, entities: [], attachments: [], replying_to_preview, forwarded_message,
    /// sent_from: 1 }; a reaction is { message_sequence_id, emoji } under field 2 (add) or 3 (remove).
    static func plaintext(_ entry: Entry) -> Data {
        var holder = ThriftBinaryWriter()
        holder.structure(1) { contents in
            switch entry {
            case .text(let text, let reply):
                contents.structure(1) { message in
                    message.string(1, text)
                    message.structList(2, [])
                    message.structList(3, [])
                    if let reply {
                        // The preview x.com writes: sender, the first 140 characters, and both ids.
                        message.structure(4) { preview in
                            preview.i64(1, Int64(reply.senderId) ?? 0)
                            preview.string(2, String(reply.text.prefix(140)))
                            preview.structList(3, [])
                            preview.structList(4, [])
                            preview.string(5, reply.senderName)
                            if let seq = reply.sequenceId { preview.string(6, seq) }
                            if let id = reply.messageId { preview.string(7, id) }
                        }
                    }
                    message.i32(7, 1)
                }
            case .forward(let text):
                // A forward has no text of its own; the original's goes in forwarded_message.
                contents.structure(1) { message in
                    message.structList(2, [])
                    message.structList(3, [])
                    message.structure(6) { forwarded in
                        forwarded.string(1, text)
                        forwarded.structList(2, [])
                    }
                    message.i32(7, 1)
                }
            case .reaction(let target, let emoji), .reactionRemove(let target, let emoji):
                let field: Int16
                if case .reaction = entry { field = 2 } else { field = 3 }
                contents.structure(field) { reaction in
                    reaction.string(1, target)
                    reaction.string(2, emoji)
                }
            }
        }
        return holder.finished
    }

    static func plaintext(text: String) -> Data {
        plaintext(.text(text, replyingTo: nil))
    }

    static func seal(_ message: Data, key: Data) -> Data? {
        let nonce = randomBytes(24)
        guard let box = XSalsa20Poly1305.seal(message: message, nonce: nonce, key: key) else { return nil }
        return nonce + box
    }

    static func frankingTag(plaintext: Data, nonce: Data, messageId: String, conversationId: String) -> Data {
        var buffer = Data("xchat-franking".utf8)
        buffer.append(Data(SHA256.hash(data: plaintext)))
        buffer.append(bigEndian32(0)) // No media, so no media hashes follow.
        buffer.append(nonce)
        buffer.append(Data(messageId.utf8))
        let conversation = Data(conversationId.utf8)
        buffer.append(bigEndian32(conversation.count))
        buffer.append(conversation)
        return Data(SHA256.hash(data: buffer))
    }

    static func build(
        entry: Entry,
        messageId: String,
        conversationId: String,
        senderId: String,
        keys: XChatSendKeys
    ) -> Built? {
        let plain = plaintext(entry)
        let frankingNonce = randomBytes(32)
        guard let contents = seal(plain, key: keys.conversationKey),
              let encryptedNonce = seal(frankingNonce, key: keys.conversationKey) else { return nil }
        let tag = frankingTag(plaintext: plain, nonce: frankingNonce, messageId: messageId, conversationId: conversationId)

        var event = ThriftBinaryWriter()
        event.binary(100, contents)
        event.string(101, keys.conversationKeyVersion)
        event.bool(102, true)   // should_notify
        event.bool(105, false)  // is_pending_public_key
        event.i32(106, 1)       // priority
        event.structure(108) { franking in
            franking.binary(1, tag)
            franking.binary(2, encryptedNonce)
        }

        let signed = [
            "MessageCreateEvent", messageId, senderId, conversationId,
            keys.conversationKeyVersion, unpaddedBase64(contents)
        ].joined(separator: ",")
        guard let signature = sign(signed, with: keys.signingKey) else { return nil }

        var envelope = ThriftBinaryWriter()
        envelope.string(1, signature)
        envelope.string(2, keys.signingKeyVersion)
        envelope.string(3, signatureVersion)
        envelope.structList(5, [{ info in
            info.string(1, senderId)
            info.string(2, keys.signingKeyVersion)
        }])

        return Built(encodedCreateEvent: event.finished, encodedSignature: envelope.finished)
    }

    /// A deletion is not encrypted: it is the MessageEventDetail { 7: MessageDeleteEvent { sequence_ids, action } }
    /// itself, signed as "MessageDeleteEvent,<action id>,<sender>,<conversation>,<action>,<sequence ids…>".
    static func deletion(
        sequenceIds: [String],
        forEveryone: Bool,
        actionId: String,
        conversationId: String,
        senderId: String,
        signingKey: P256.Signing.PrivateKey
    ) -> (detail: Data, signature: String)? {
        let action: Int32 = forEveryone ? 2 : 1 // DELETE_FOR_ALL : DELETE_FOR_SELF
        var detail = ThriftBinaryWriter()
        detail.structure(7) { event in
            event.stringList(1, sequenceIds)
            event.i32(2, action)
        }
        let signed = (["MessageDeleteEvent", actionId, senderId, conversationId, String(action)] + sequenceIds)
            .joined(separator: ",")
        guard let signature = sign(signed, with: signingKey) else { return nil }
        return (detail.finished, signature)
    }

    private static func sign(_ text: String, with key: P256.Signing.PrivateKey) -> String? {
        guard let signature = try? key.signature(for: Data(text.utf8)) else { return nil }
        return unpaddedBase64(signature.rawRepresentation)
    }

    private static func unpaddedBase64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private static func bigEndian32(_ n: Int) -> Data {
        withUnsafeBytes(of: Int32(n).bigEndian) { Data($0) }
    }

    private static func randomBytes(_ count: Int) -> Data {
        var rng = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &rng) })
    }
}

// MARK: - Send

extension DMAPI {
    private static let sendMessageCreatePath = "/i/api/graphql/TWRPP7gnKwV_R8-tE-Dd3Q/SendMessageCreateMutation"

    private static let deleteMessagesPath = "/i/api/graphql/4gsDQKEmYkOtvsSIpHXdQA/DeleteMessageMutation"

    /// Sends an entry to an X Chat conversation. On success it comes back as X stored it, with its sequence id,
    /// so reactions and read receipts can find it.
    func sendXChatEntry(
        _ entry: XChatOutgoing.Entry,
        conversationId: String,
        messageId: String,
        keys: XChatSendKeys,
        completion: @escaping (Result<DMMessage, APIError>) -> Void
    ) {
        let senderId = AccountManager.shared.activeId ?? ""
        guard let built = XChatOutgoing.build(
            entry: entry,
            messageId: messageId,
            conversationId: conversationId,
            senderId: senderId,
            keys: keys
        ) else {
            completion(.failure(.invalidResponse))
            return
        }

        var variables: [String: Any] = [
            "conversation_id": conversationId,
            "message_id": messageId,
            "encoded_message_create_event": built.encodedCreateEvent.base64EncodedString(),
            "encoded_message_event_signature": built.encodedSignature.base64EncodedString()
        ]
        if let token = XChatConversationState.shared.token(for: conversationId) {
            variables["conversation_token"] = token
        }
        // x.com sends the variables as a JSON string inside the body, not as an object.
        guard let variablesData = try? JSONSerialization.data(withJSONObject: variables),
              let variablesString = String(data: variablesData, encoding: .utf8) else {
            completion(.failure(.invalidResponse))
            return
        }

        WebKitWriteChannel.shared.perform(path: Self.sendMessageCreatePath, body: ["variables": variablesString]) { result in
            switch result {
            case .success(let json):
                let payload = (json["data"] as? [String: Any])?["xchat_send_create_message_event"] as? [String: Any]
                guard let encoded = payload?["encoded_message_event"] as? String else {
                    dmLog.error("X Chat send returned no event: \(String(describing: json.keys))")
                    completion(.failure(.invalidResponse))
                    return
                }
                guard let message = self.parseXChatEvent(base64: encoded, activeUserId: senderId) else {
                    completion(.failure(.parseError))
                    return
                }
                completion(.success(message))
            case .failure(let error):
                dmLog.error("X Chat send failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    /// Deletes messages by sequence id, for this account's devices or, for one's own messages, for everyone.
    func deleteXChatMessages(
        sequenceIds: [String],
        forEveryone: Bool,
        conversationId: String,
        signingKey: P256.Signing.PrivateKey,
        signingKeyVersion: String,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        let senderId = AccountManager.shared.activeId ?? ""
        let actionId = UUID().uuidString.lowercased()
        guard let deletion = XChatOutgoing.deletion(
            sequenceIds: sequenceIds,
            forEveryone: forEveryone,
            actionId: actionId,
            conversationId: conversationId,
            senderId: senderId,
            signingKey: signingKey
        ) else {
            completion(.failure(.invalidResponse))
            return
        }
        let variables: [String: Any] = [
            "sequence_ids": sequenceIds,
            "conversation_id": conversationId,
            "delete_message_action": forEveryone ? "DeleteForAll" : "DeleteForSelf",
            "action_signatures": [[
                "encoded_message_event_detail": deletion.detail.base64EncodedString(),
                "message_event_signature": [
                    "public_key_version": signingKeyVersion,
                    "signature": deletion.signature,
                    "signature_version": XChatOutgoing.signatureVersion,
                    "signing_public_key": NSNull()
                ],
                "message_id": actionId
            ]]
        ]
        guard let variablesData = try? JSONSerialization.data(withJSONObject: variables),
              let variablesString = String(data: variablesData, encoding: .utf8) else {
            completion(.failure(.invalidResponse))
            return
        }
        WebKitWriteChannel.shared.perform(path: Self.deleteMessagesPath, body: ["variables": variablesString]) { result in
            switch result {
            case .success(let json):
                let response = (json["data"] as? [String: Any])?["xchat_delete_messages"] as? [String: Any]
                if let code = response?["error_code"] as? String, !code.isEmpty {
                    dmLog.error("X Chat delete refused: \(code)")
                    completion(.failure(.serverError(code)))
                } else {
                    completion(.success(()))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

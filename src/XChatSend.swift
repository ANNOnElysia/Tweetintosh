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

    /// The plaintext of a text message: MessageEntryHolder { contents: MessageEntryContents { message:
    /// MessageContents { message_text, entities: [], attachments: [], sent_from: 1 } } }.
    static func plaintext(text: String) -> Data {
        var holder = ThriftBinaryWriter()
        holder.structure(1) { entry in
            entry.structure(1) { contents in
                contents.string(1, text)
                contents.structList(2, [])
                contents.structList(3, [])
                contents.i32(7, 1)
            }
        }
        return holder.finished
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
        text: String,
        messageId: String,
        conversationId: String,
        senderId: String,
        keys: XChatSendKeys
    ) -> Built? {
        let plain = plaintext(text: text)
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
        guard let signature = try? keys.signingKey.signature(for: Data(signed.utf8)) else { return nil }

        var envelope = ThriftBinaryWriter()
        envelope.string(1, unpaddedBase64(signature.rawRepresentation))
        envelope.string(2, keys.signingKeyVersion)
        envelope.string(3, signatureVersion)
        envelope.structList(5, [{ info in
            info.string(1, senderId)
            info.string(2, keys.signingKeyVersion)
        }])

        return Built(encodedCreateEvent: event.finished, encodedSignature: envelope.finished)
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

    /// Sends `text` to an X Chat conversation. On success the message comes back as X stored it, with its
    /// sequence id, so reactions and read receipts can find it.
    func sendXChatMessage(
        conversationId: String,
        messageId: String,
        text: String,
        keys: XChatSendKeys,
        completion: @escaping (Result<DMMessage, APIError>) -> Void
    ) {
        let senderId = AccountManager.shared.activeId ?? ""
        guard let built = XChatOutgoing.build(
            text: text,
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

        // The text is known, so the echoed event never needs decrypting to show it.
        DMViewModel.shared.decryptedMessageCache[messageId] = DMDecodedContent(text: text)

        WebKitWriteChannel.shared.perform(path: Self.sendMessageCreatePath, body: ["variables": variablesString]) { result in
            switch result {
            case .success(let json):
                let payload = (json["data"] as? [String: Any])?["xchat_send_create_message_event"] as? [String: Any]
                guard let encoded = payload?["encoded_message_event"] as? String else {
                    dmLog.error("X Chat send returned no event: \(String(describing: json.keys))")
                    completion(.failure(.invalidResponse))
                    return
                }
                let message = self.parseXChatEvent(base64: encoded, activeUserId: senderId) ?? DMMessage(
                    id: messageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    recipientId: nil,
                    text: text,
                    createdAt: Date(),
                    isOutgoing: true,
                    keyVersion: keys.conversationKeyVersion
                )
                completion(.success(message))
            case .failure(let error):
                dmLog.error("X Chat send failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
}

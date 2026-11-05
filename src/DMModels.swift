//
//  DMModels.swift
//  Tweetintosh
//
//  Core data models for X Direct Messages (DMs), conforming to Apple HIG standards.
//  Includes conversation metadata, message entries, participants, and filtering categories.
//

import Foundation

// MARK: - Text, Emoji & Markdown Helper

enum DMTextHelper {
    /// Decodes HTML entities sent by X API (&lt;, &gt;, &quot;, &#39;, &amp;)
    static func decodeHTML(_ string: String) -> String {
        guard string.contains("&") else { return string }
        return string
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
    
    /// Cleans HTML tags from text (like <u>, <p>, <br>) and unescapes entities
    static func cleanMarkdownTags(_ string: String) -> String {
        var s = decodeHTML(string)
        s = s.replacingOccurrences(of: "<u>", with: "")
             .replacingOccurrences(of: "</u>", with: "")
             .replacingOccurrences(of: "<p>", with: "")
             .replacingOccurrences(of: "</p>", with: "\n")
             .replacingOccurrences(of: "<br>", with: "\n")
             .replacingOccurrences(of: "<br/>", with: "\n")
        return s
    }
    
    /// Parses Markdown and inline emoji / formatting for SwiftUI text rendering
    static func attributedMarkdown(_ string: String) -> AttributedString {
        let clean = cleanMarkdownTags(string)
        if let attr = try? AttributedString(markdown: clean, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(clean)
    }
}

enum DMConversationType: String, Codable {
    case oneToOne = "ONE_TO_ONE"
    case group = "GROUP_DM"
}

struct DMParticipant: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let screenName: String
    let avatarUrl: String?
    let isBlueVerified: Bool
    let isVerified: Bool
    
    init(
        id: String,
        name: String,
        screenName: String,
        avatarUrl: String?,
        isBlueVerified: Bool = false,
        isVerified: Bool = false
    ) {
        self.id = id
        self.name = DMTextHelper.decodeHTML(name)
        self.screenName = screenName
        self.avatarUrl = avatarUrl
        self.isBlueVerified = isBlueVerified
        self.isVerified = isVerified
    }
    
    var formattedHandle: String {
        screenName.hasPrefix("@") ? screenName : "@\(screenName)"
    }
    
    var highResAvatarUrl: String? {
        guard let url = avatarUrl else { return nil }
        return url
            .replacingOccurrences(of: "_normal.", with: "_400x400.")
            .replacingOccurrences(of: "_bigger.", with: "_400x400.")
            .replacingOccurrences(of: "_mini.", with: "_400x400.")
    }
    
    /// Converts DMParticipant into a lightweight TweetUser for opening ProfileView or Peek card
    var asTweetUser: TweetUser {
        TweetUser(
            id: id,
            name: name,
            screenName: screenName,
            avatarUrl: avatarUrl,
            isVerified: isVerified || isBlueVerified
        )
    }
}

/// What kind of entry an X Chat event carries. Only messages are drawn as bubbles; the rest act on the message
/// their target sequence id names.
enum DMEntryKind: String, Codable {
    case message
    case reaction
    case reactionRemove
    case edit
    case read
    /// Removes the messages in `deletedSequenceIds`, for everyone or for this account's devices.
    case delete
    case other
}

/// The quoted message a reply carries, as X stores it in the reply itself.
struct DMReplyPreview: Codable, Equatable {
    var senderId: String
    var senderName: String
    var text: String
    var sequenceId: String?
    var messageId: String?
}

/// What an X Chat payload decodes to once decrypted.
struct DMDecodedContent: Equatable {
    var kind: DMEntryKind = .message
    var text: String = ""
    /// The sequence id of the message a reaction, edit or read mark refers to.
    var targetSequenceId: String? = nil
    var emoji: String? = nil
    var readAt: Date? = nil
    var replyPreview: DMReplyPreview? = nil
    var isForwarded = false
    var deletedSequenceIds: [String]? = nil
}

struct DMMessage: Identifiable, Codable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let recipientId: String?
    let text: String
    let createdAt: Date
    let isOutgoing: Bool
    let mediaUrl: String?
    let isEncrypted: Bool
    let rawCiphertextBase64: String?
    let keyVersion: String?
    /// X Chat's per-conversation sequence id. Reactions point at their target by this id rather than by `id`.
    let sequenceId: String?
    let entryKind: DMEntryKind
    /// For a reaction, edit or read mark: the sequence id of the message it refers to.
    let targetSequenceId: String?
    let emoji: String?
    /// For a read mark: when the reader saw the conversation.
    let readAt: Date?
    /// Set on the copy the chat draws once a later edit has replaced the text.
    var editedAt: Date? = nil
    var replyPreview: DMReplyPreview? = nil
    // Optional so chats cached before these existed still decode.
    var isForwarded: Bool? = nil
    var deletedSequenceIds: [String]? = nil
    
    init(
        id: String,
        conversationId: String,
        senderId: String,
        recipientId: String?,
        text: String,
        createdAt: Date,
        isOutgoing: Bool,
        mediaUrl: String? = nil,
        isEncrypted: Bool = false,
        rawCiphertextBase64: String? = nil,
        keyVersion: String? = nil,
        sequenceId: String? = nil,
        entryKind: DMEntryKind = .message,
        targetSequenceId: String? = nil,
        emoji: String? = nil,
        readAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.recipientId = recipientId
        self.text = DMTextHelper.cleanMarkdownTags(text)
        self.createdAt = createdAt
        self.isOutgoing = isOutgoing
        self.mediaUrl = mediaUrl
        self.isEncrypted = isEncrypted
        self.rawCiphertextBase64 = rawCiphertextBase64
        self.keyVersion = keyVersion
        self.sequenceId = sequenceId
        self.entryKind = entryKind
        self.targetSequenceId = targetSequenceId
        self.emoji = emoji
        self.readAt = readAt
    }
    
    var isReaction: Bool { entryKind == .reaction }
    
    /// Whether the conversation list may show this as the latest thing that happened.
    var isListed: Bool { entryKind == .message || entryKind == .reaction }
    
    /// What the conversation list shows for these entries (oldest first): the newest message or reaction, passing over
    /// reactions that were taken back, deleted messages, and messages with nothing to show. A reaction and its removal
    /// can share a timestamp, so they are compared by time, not by position.
    static func latestListed(in entries: [DMMessage]) -> DMMessage? {
        let removals = entries.filter { $0.entryKind == .reactionRemove }
        let deleted = Set(entries.filter { $0.entryKind == .delete }.flatMap { $0.deletedSequenceIds ?? [] })
        return entries.last { entry in
            guard entry.isListed else { return false }
            if entry.isReaction {
                return !removals.contains {
                    $0.senderId == entry.senderId && $0.targetSequenceId == entry.targetSequenceId
                        && $0.emoji == entry.emoji && $0.createdAt >= entry.createdAt
                }
            }
            if let seq = entry.sequenceId, deleted.contains(seq) { return false }
            return !entry.text.isEmpty || entry.mediaUrl != nil || entry.isEncrypted
        }
    }
    
    /// The same message showing an edit's text.
    func edited(to text: String, at date: Date) -> DMMessage {
        var copy = DMMessage(
            id: id, conversationId: conversationId, senderId: senderId, recipientId: recipientId, text: text,
            createdAt: createdAt, isOutgoing: isOutgoing, mediaUrl: mediaUrl, isEncrypted: isEncrypted,
            rawCiphertextBase64: rawCiphertextBase64, keyVersion: keyVersion, sequenceId: sequenceId,
            entryKind: entryKind, targetSequenceId: targetSequenceId, emoji: emoji, readAt: readAt
        )
        copy.editedAt = date
        copy.replyPreview = replyPreview
        copy.isForwarded = isForwarded
        return copy
    }
    
    /// Whether `targetId`, as carried by a reaction, names this message.
    func isTarget(of targetId: String) -> Bool {
        targetId == id || targetId == sequenceId
    }
    
    /// The same message with its decrypted contents filled in.
    func decrypted(_ content: DMDecodedContent) -> DMMessage {
        var message = DMMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            recipientId: recipientId,
            text: content.text,
            createdAt: createdAt,
            isOutgoing: isOutgoing,
            mediaUrl: mediaUrl,
            isEncrypted: false,
            rawCiphertextBase64: rawCiphertextBase64,
            keyVersion: keyVersion,
            sequenceId: sequenceId,
            entryKind: content.kind,
            targetSequenceId: content.targetSequenceId,
            emoji: content.emoji,
            readAt: content.readAt
        )
        message.apply(content)
        return message
    }
    
    /// Carries over the parts of decoded contents that are not constructor arguments.
    mutating func apply(_ content: DMDecodedContent) {
        replyPreview = content.replyPreview
        isForwarded = content.isForwarded ? true : nil
        deletedSequenceIds = content.deletedSequenceIds
    }
    
    var formattedText: AttributedString {
        DMTextHelper.attributedMarkdown(text)
    }
}

/// A participant's read receipt: they had the conversation open at `readAt`.
struct DMReadReceipt: Equatable {
    let eventId: String
    let conversationId: String
    let readerId: String
    let readAt: Date
}

/// When the other people in a chat saw a message. X Chat reports it two ways: encrypted mark-read entries that
/// name the newest message seen, and plain read-receipt events (`DMReadReceiptStore`).
enum DMSeen {
    static func seenTimes(for message: DMMessage, among messages: [DMMessage]) -> [String: Date] {
        var result = DMReadReceiptStore.shared.seenTimes(for: message)
        let sequence = message.sequenceId.flatMap { Int64($0) }
        for mark in messages where mark.entryKind == .read && mark.senderId != message.senderId {
            let covers: Bool
            if let sequence, let upTo = mark.targetSequenceId.flatMap({ Int64($0) }) {
                covers = upTo >= sequence
            } else {
                covers = mark.createdAt >= message.createdAt
            }
            guard covers else { continue }
            let at = mark.readAt ?? mark.createdAt
            if let known = result[mark.senderId], known <= at { continue }
            result[mark.senderId] = at
        }
        return result
    }
    
    /// Whether anyone but `senderId` has reported reading this chat at all, so "not seen yet" can be trusted.
    static func hasReceipts(in conversationId: String, excluding senderId: String, among messages: [DMMessage]) -> Bool {
        messages.contains { $0.entryKind == .read && $0.senderId != senderId }
            || DMReadReceiptStore.shared.hasReceipts(in: conversationId, excluding: senderId)
    }
}

/// Read receipts seen while decoding X Chat events. Decoding runs off the main thread, so access is locked.
final class DMReadReceiptStore {
    static let shared = DMReadReceiptStore()
    private init() {}
    
    private let lock = NSLock()
    private var receipts: [String: [String: DMReadReceipt]] = [:]
    
    func record(_ receipt: DMReadReceipt) {
        lock.lock()
        receipts[receipt.conversationId, default: [:]][receipt.eventId] = receipt
        lock.unlock()
    }
    
    /// When each other participant first read the conversation after `message` arrived. A receipt carries the time
    /// the reader caught up, so the earliest one at or after the message is when they saw it.
    func seenTimes(for message: DMMessage) -> [String: Date] {
        lock.lock()
        let all = Array((receipts[message.conversationId] ?? [:]).values)
        lock.unlock()
        var result: [String: Date] = [:]
        for r in all where r.readerId != message.senderId && r.readAt >= message.createdAt {
            if let known = result[r.readerId], known <= r.readAt { continue }
            result[r.readerId] = r.readAt
        }
        return result
    }
    
    /// Whether any receipt from someone other than `senderId` has arrived, i.e. whether "not seen yet" can be said.
    func hasReceipts(in conversationId: String, excluding senderId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return receipts[conversationId]?.values.contains { $0.readerId != senderId } ?? false
    }
}

struct DMConversation: Identifiable, Codable, Equatable {
    let id: String
    let type: DMConversationType
    let participants: [DMParticipant]
    let otherParticipant: DMParticipant?
    var lastMessage: DMMessage?
    var lastReadEventId: String?
    var sortTimestamp: Date
    let isMuted: Bool
    let isTrusted: Bool
    var isPinned: Bool
    var unreadCount: Int
    var hasEncryptedMessages: Bool
    
    init(
        id: String,
        type: DMConversationType,
        participants: [DMParticipant],
        otherParticipant: DMParticipant?,
        lastMessage: DMMessage?,
        lastReadEventId: String?,
        sortTimestamp: Date,
        isMuted: Bool = false,
        isTrusted: Bool = true,
        isPinned: Bool = false,
        unreadCount: Int = 0,
        hasEncryptedMessages: Bool = false
    ) {
        self.id = id
        self.type = type
        self.participants = participants
        self.otherParticipant = otherParticipant
        self.lastMessage = lastMessage
        self.lastReadEventId = lastReadEventId
        self.sortTimestamp = sortTimestamp
        self.isMuted = isMuted
        self.isTrusted = isTrusted
        self.isPinned = isPinned
        self.unreadCount = unreadCount
        self.hasEncryptedMessages = hasEncryptedMessages
    }
    
    var displayName: String {
        if let other = otherParticipant {
            return other.name.isEmpty ? other.formattedHandle : other.name
        }
        let names = participants.map { $0.name }
        return names.isEmpty ? "Direct Message" : names.joined(separator: ", ")
    }
    
    var displayHandle: String {
        otherParticipant?.formattedHandle ?? ""
    }
    
    var avatarUrl: String? {
        otherParticipant?.highResAvatarUrl ?? otherParticipant?.avatarUrl
    }
    
    var snippetText: AttributedString {
        if lastMessage?.isReaction == true, let emoji = lastMessage?.emoji {
            return AttributedString(LocalizationManager.shared.format("messages_reacted_snippet", ["emoji": emoji]))
        }
        return DMTextHelper.attributedMarkdown(lastMessage?.text ?? "")
    }
}

enum DMFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case unread = "unread"
    case known = "known"
    case requests = "requests"
    
    var id: String { rawValue }
    
    var locKey: String {
        switch self {
        case .all: return "messages_filter_all"
        case .unread: return "messages_filter_unread"
        case .known: return "messages_filter_known"
        case .requests: return "messages_filter_requests"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .unread: return "envelope.badge"
        case .known: return "person.2"
        case .requests: return "person.badge.shield.checkmark"
        }
    }
}

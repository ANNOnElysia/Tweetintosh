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

/// What an X Chat payload decodes to once decrypted: either a message's text or a reaction to another message.
struct DMDecodedContent: Equatable {
    var text: String = ""
    var reactionTargetId: String? = nil
    var reactionEmoji: String? = nil
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
    /// Set when this event is a reaction rather than a message: the target's sequence id and the emoji.
    let reactionTargetId: String?
    let reactionEmoji: String?
    
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
        reactionTargetId: String? = nil,
        reactionEmoji: String? = nil
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
        self.reactionTargetId = reactionTargetId
        self.reactionEmoji = reactionEmoji
    }
    
    var isReaction: Bool { reactionEmoji != nil }
    
    /// Whether `targetId`, as carried by a reaction, names this message.
    func isTarget(of targetId: String) -> Bool {
        targetId == id || targetId == sequenceId
    }
    
    /// The same message with its decrypted contents filled in.
    func decrypted(_ content: DMDecodedContent) -> DMMessage {
        DMMessage(
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
            reactionTargetId: content.reactionTargetId,
            reactionEmoji: content.reactionEmoji
        )
    }
    
    var formattedText: AttributedString {
        DMTextHelper.attributedMarkdown(text)
    }
}

struct DMConversation: Identifiable, Codable, Equatable {
    let id: String
    let type: DMConversationType
    let participants: [DMParticipant]
    let otherParticipant: DMParticipant?
    var lastMessage: DMMessage?
    var lastReadEventId: String?
    let sortTimestamp: Date
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
        if let emoji = lastMessage?.reactionEmoji {
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

//
//  DMViewModel.swift
//  Tweetintosh
//
//  Observable state manager for Direct Messages.
//  Handles inbox synchronization, conversation selection, real-time filtering,
//  iMessage-style pin management, search indexing, X Chat 4-digit passcode decryption, and optimistic messaging.
//

import SwiftUI
import Combine
import AppKit
import CryptoKit

final class DMViewModel: ObservableObject {
    static let shared = DMViewModel()
    
    @Published var conversations: [DMConversation] = []
    @Published var selectedConversationId: String?
    @Published var messagesByConv: [String: [DMMessage]] = [:]
    
    @Published var filter: DMFilter = .all
    @Published var searchQuery: String = ""
    @Published var isEditMode: Bool = false
    @Published var selectedConversationIds: Set<String> = []
    
    @Published var isLoadingInbox: Bool = false
    @Published var isLoadingMessages: Bool = false
    @Published var isSending: Bool = false
    @Published var inputText: String = ""
    @Published var pendingAttachments: [URL] = []
    @Published var errorMessage: String?
    
    // 4-Digit Passcode (X Chat / Juicebox End-to-End Encryption Unlock)
    @Published var isPasscodeUnlocked: Bool = false
    @Published var showPasscodeSheet: Bool = false
    @Published var passcodeInput: String = ""
    @Published var isVerifyingPasscode: Bool = false
    @Published var passcodeErrorMessage: String? = nil
    
    var privateKey: P256.KeyAgreement.PrivateKey?
    // The second half of the recovered secret, and the version of the key pair it belongs to. Only secrets
    // recovered since sending was added keep it; older ones have to be recovered again before sending.
    var signingKey: P256.Signing.PrivateKey?
    var signingKeyVersion: String?
    var decryptedMessageCache: [String: DMDecodedContent] = [:]
    var rawConversationKeyEvents: [String: Data] = [:]
    var conversationKeys: [String: Data] = [:]
    
    private let pinnedStorageKey = "com.anno.tweetintosh.dm.pinned"
    @Published var pinnedConversationIds: Set<String> = []
    
    private var passcodeStorageKey: String {
        let activeId = AccountManager.shared.activeId ?? "default"
        return "com.anno.tweetintosh.dm.privkey.\(activeId)"
    }
    
    private var keyVersionStorageKey: String {
        let activeId = AccountManager.shared.activeId ?? "default"
        return "com.anno.tweetintosh.dm.pkversion.\(activeId)"
    }
    
    /// Loads a recovered X Chat secret: its first 32 bytes decrypt, and on current accounts the next 32 sign.
    @discardableResult
    private func applySecret(hex: String, keyVersion: String?) -> Bool {
        guard let keyData = Data(hexString: hex),
              let priv = try? P256.KeyAgreement.PrivateKey(rawRepresentation: keyData.prefix(32)) else { return false }
        privateKey = priv
        if keyData.count == 64, let keyVersion,
           let signing = try? P256.Signing.PrivateKey(rawRepresentation: keyData.subdata(in: 32..<64)) {
            signingKey = signing
            signingKeyVersion = keyVersion
        } else {
            signingKey = nil
            signingKeyVersion = nil
        }
        return true
    }
    
    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: pinnedStorageKey) {
            self.pinnedConversationIds = Set(saved)
        }
        
        // Restore verified private key from secure persistent storage if already unlocked
        if let savedHex = UserDefaults.standard.string(forKey: passcodeStorageKey),
           applySecret(hex: savedHex, keyVersion: UserDefaults.standard.string(forKey: keyVersionStorageKey)) {
            self.isPasscodeUnlocked = true
        } else {
            self.isPasscodeUnlocked = false
        }
    }
    
    // MARK: - Filtered & Computed Properties
    
    var selectedConversation: DMConversation? {
        guard let id = selectedConversationId else { return nil }
        return conversations.first { $0.id == id }
    }
    
    var activeMessages: [DMMessage] {
        guard let id = selectedConversationId else { return [] }
        return messagesByConv[id] ?? []
    }
    
    var pinnedConversations: [DMConversation] {
        conversations.filter { pinnedConversationIds.contains($0.id) }
    }
    
    var filteredConversations: [DMConversation] {
        var result = conversations
        
        // 1. Filter Category
        switch filter {
        case .all:
            break
        case .unread:
            result = result.filter { $0.unreadCount > 0 }
        case .known:
            result = result.filter { $0.isTrusted }
        case .requests:
            result = result.filter { !$0.isTrusted }
        }
        
        // 2. Search Query
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter { conv in
                conv.displayName.lowercased().contains(q) ||
                conv.displayHandle.lowercased().contains(q) ||
                (conv.lastMessage?.text.lowercased().contains(q) ?? false)
            }
        }
        
        // 3. Sort: pinned items on top, then newest sortTimestamp first
        return result.sorted {
            let p0 = pinnedConversationIds.contains($0.id)
            let p1 = pinnedConversationIds.contains($1.id)
            if p0 != p1 {
                return p0 && !p1
            }
            return $0.sortTimestamp > $1.sortTimestamp
        }
    }
    
    // MARK: - Media Attachments
    
    func attachMedia(_ urls: [URL]) {
        for url in urls {
            if !pendingAttachments.contains(url) {
                pendingAttachments.append(url)
            }
        }
    }
    
    func removeAttachment(at index: Int) {
        guard pendingAttachments.indices.contains(index) else { return }
        pendingAttachments.remove(at: index)
    }
    
    func clearAttachments() {
        pendingAttachments.removeAll()
    }
    
    func restoreUnlockedStateIfNeeded() {
        if !isPasscodeUnlocked || privateKey == nil {
            if let savedHex = UserDefaults.standard.string(forKey: passcodeStorageKey),
               applySecret(hex: savedHex, keyVersion: UserDefaults.standard.string(forKey: keyVersionStorageKey)) {
                self.isPasscodeUnlocked = true
                decryptAllLoadedMessages()
            }
        }
    }
    
    // MARK: - Inbox & Conversation Loading
    
    func loadInbox(forceRefresh: Bool = false) {
        guard !isLoadingInbox else { return }
        if !forceRefresh && !conversations.isEmpty { return }
        
        restoreUnlockedStateIfNeeded()
        
        isLoadingInbox = true
        errorMessage = nil
        
        // Fetch inbox state baseline (Unified X Chat GraphQL + Legacy REST)
        DMAPI.shared.fetchInbox { [weak self] result in
            guard let self = self else { return }
            self.isLoadingInbox = false
            
            switch result {
            case .success(let (convs, msgs)):
                self.conversations = convs
                self.messagesByConv.merge(msgs) { existing, new in new }
                
                if self.isPasscodeUnlocked {
                    self.decryptAllLoadedMessages()
                }
                
                // Synchronize any additional message updates
                self.fetchLatestUserUpdates()
                
                if self.selectedConversationId == nil, let first = self.filteredConversations.first {
                    self.selectedConversationId = first.id
                    self.loadMessages(for: first.id)
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func fetchLatestUserUpdates() {
        DMAPI.shared.fetchUserUpdates { [weak self] result in
            guard let self = self else { return }
            guard case .success(let (newConvs, newMsgs)) = result else { return }
            
            var mergedConvs = self.conversations
            for nConv in newConvs {
                // Match by ID or by other participant ID so X Chat & legacy conversations correlate
                if let idx = mergedConvs.firstIndex(where: {
                    $0.id == nConv.id ||
                    ($0.otherParticipant?.id != nil && $0.otherParticipant?.id == nConv.otherParticipant?.id)
                }) {
                    var updated = mergedConvs[idx]
                    if updated.lastMessage == nil, let last = nConv.lastMessage {
                        updated.lastMessage = last
                    }
                    mergedConvs[idx] = updated
                } else {
                    mergedConvs.append(nConv)
                }
            }
            
            // Merge messages and deduplicate by id
            for (cid, mList) in newMsgs {
                var existing = self.messagesByConv[cid] ?? []
                for m in mList {
                    if !existing.contains(where: { $0.id == m.id }) {
                        existing.append(m)
                    }
                }
                self.messagesByConv[cid] = existing.sorted { $0.createdAt < $1.createdAt }
            }
            
            // Re-sort with pinned on top, then sortTimestamp descending
            self.conversations = mergedConvs.sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.sortTimestamp > $1.sortTimestamp
            }
        }
    }
    
    func fetchRecentDMEvents() {
        DMAPI.shared.fetchDMEvents { [weak self] result in
            guard let self = self else { return }
            guard case .success(let events) = result else { return }
            
            // Merge events into conversations and messages
            for event in events {
                var current = self.messagesByConv[event.conversationId] ?? []
                if !current.contains(where: { $0.id == event.id }) {
                    current.append(event)
                    self.messagesByConv[event.conversationId] = current.sorted { $0.createdAt < $1.createdAt }
                }
                
                // Update conversation's last message if newer
                if let idx = self.conversations.firstIndex(where: { $0.id == event.conversationId }) {
                    if let last = self.conversations[idx].lastMessage {
                        if event.createdAt > last.createdAt {
                            self.conversations[idx].lastMessage = event
                        }
                    } else {
                        self.conversations[idx].lastMessage = event
                    }
                }
            }
        }
    }
    
    func unlockWithPasscode(_ code: String, completion: ((Bool) -> Void)? = nil) {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 4 else { return }
        
        isVerifyingPasscode = true
        passcodeErrorMessage = nil
        let activeUserId = AccountManager.shared.activeId ?? ""
        
        WebKitWriteChannel.shared.recoverXChatPrivateKey(passcode: clean, userId: activeUserId) { [weak self] result in
            guard let self = self else { return }
            self.isVerifyingPasscode = false
            
            switch result {
            case .success(let secret):
                guard self.applySecret(hex: secret.hex, keyVersion: secret.publicKeyVersion) else {
                    self.passcodeErrorMessage = LocalizationManager.shared.t("messages_passcode_error")
                    completion?(false)
                    return
                }
                
                self.isPasscodeUnlocked = true
                self.passcodeInput = clean
                self.showPasscodeSheet = false
                
                // Persist verified private key so the user stays unlocked across launches
                UserDefaults.standard.set(secret.hex, forKey: self.passcodeStorageKey)
                UserDefaults.standard.set(secret.publicKeyVersion, forKey: self.keyVersionStorageKey)
                
                // Decrypt all existing loaded messages in memory
                self.decryptAllLoadedMessages()
                
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                AppToastManager.shared.show(LocalizationManager.shared.t("messages_passcode_unlocked_toast"), icon: "lock.open.fill")
                completion?(true)
                
            case .failure(let error):
                NSLog("[Passcode-Failure] %{public}@", error.localizedDescription)
                dmLog.warning("Passcode recovery failure: \(error.localizedDescription)")
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                if case .serverError(let msg) = error {
                    self.passcodeErrorMessage = msg
                } else {
                    self.passcodeErrorMessage = LocalizationManager.shared.t("messages_passcode_incorrect")
                }
                completion?(false)
            }
        }
    }
    
    func decryptAllLoadedMessages() {
        guard let privKey = privateKey else { return }
        
        // 1. Decrypt all conversation keys from raw key change events
        for (ver, encPayload) in rawConversationKeyEvents {
            if conversationKeys[ver] == nil {
                if let convKey = DMAPI.shared.decryptConversationKey(data: encPayload, privateKey: privKey) {
                    conversationKeys[ver] = convKey
                }
            }
        }
        
        // 2. Decrypt all loaded messages using their respective conversation keys
        for (convId, msgs) in messagesByConv {
            var updatedMsgs: [DMMessage] = []
            var hasEncrypted = false
            
            for msg in msgs {
                if msg.isEncrypted, let b64 = msg.rawCiphertextBase64, let rawData = Data(base64Encoded: b64) {
                    var decryptedText: DMDecodedContent? = nil
                    
                    if let ver = msg.keyVersion, let convKey = conversationKeys[ver] {
                        decryptedText = DMAPI.shared.decryptMessagePayload(rawBinary: rawData, conversationKey: convKey)
                    }
                    if decryptedText == nil {
                        for convKey in conversationKeys.values {
                            if let text = DMAPI.shared.decryptMessagePayload(rawBinary: rawData, conversationKey: convKey) {
                                decryptedText = text
                                break
                            }
                        }
                    }
                    
                    if let content = decryptedText {
                        decryptedMessageCache[msg.id] = content
                        updatedMsgs.append(msg.decrypted(content))
                    } else {
                        hasEncrypted = true
                        updatedMsgs.append(msg)
                    }
                } else {
                    updatedMsgs.append(msg)
                }
            }
            
            messagesByConv[convId] = updatedMsgs
            
            if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                conversations[idx].lastMessage = updatedMsgs.last
                conversations[idx].hasEncryptedMessages = hasEncrypted
            }
        }
    }
    
    func promptPasscode() {
        showPasscodeSheet = true
    }
    
    func selectConversation(_ conv: DMConversation) {
        selectedConversationId = conv.id
        loadMessages(for: conv.id)
    }
    
    func loadMessages(for conversationId: String) {
        guard !isLoadingMessages else { return }
        isLoadingMessages = true
        
        DMAPI.shared.fetchConversation(conversationId: conversationId) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingMessages = false
            
            switch result {
            case .success(let msgs):
                if !msgs.isEmpty {
                    var current = self.messagesByConv[conversationId] ?? []
                    for m in msgs {
                        if !current.contains(where: { $0.id == m.id }) {
                            current.append(m)
                        }
                    }
                    self.messagesByConv[conversationId] = current.sorted { $0.createdAt < $1.createdAt }
                    if let last = self.messagesByConv[conversationId]?.last,
                       let idx = self.conversations.firstIndex(where: { $0.id == conversationId }) {
                        self.conversations[idx].lastMessage = last
                    }
                    if self.isPasscodeUnlocked {
                        self.decryptAllLoadedMessages()
                    }
                }
            case .failure(let error):
                dmLog.debug("Fetch conversation failure: \(error.localizedDescription)")
            }
        }
    }
    
    func sendMessage() {
        guard let convId = selectedConversationId else { return }
        let textToSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentsToSend = pendingAttachments
        guard (!textToSend.isEmpty || !attachmentsToSend.isEmpty), !isSending else { return }
        
        // X Chat conversations only take encrypted, signed messages; the legacy endpoint answers them with
        // success and delivers nothing.
        if isXChatConversation(convId) {
            sendXChatMessage(textToSend, attachments: attachmentsToSend, conversationId: convId)
            return
        }
        
        inputText = ""
        pendingAttachments.removeAll()
        isSending = true
        
        let activeUserId = AccountManager.shared.activeId ?? ""
        let optimisticMsg = DMMessage(
            id: "local-\(UUID().uuidString)",
            conversationId: convId,
            senderId: activeUserId,
            recipientId: selectedConversation?.otherParticipant?.id,
            text: textToSend,
            createdAt: Date(),
            isOutgoing: true,
            mediaUrl: attachmentsToSend.first?.absoluteString
        )
        
        messagesByConv[convId, default: []].append(optimisticMsg)
        
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].lastMessage = optimisticMsg
        }
        
        DMAPI.shared.sendMessage(conversationId: convId, text: textToSend) { [weak self] result in
            guard let self = self else { return }
            self.isSending = false
            
            switch result {
            case .success(let realMsg):
                // Replace optimistic message
                var current = self.messagesByConv[convId] ?? []
                if let optIdx = current.firstIndex(where: { $0.id == optimisticMsg.id }) {
                    current[optIdx] = realMsg
                }
                self.messagesByConv[convId] = current
                if let idx = self.conversations.firstIndex(where: { $0.id == convId }) {
                    self.conversations[idx].lastMessage = realMsg
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                AppToastManager.shared.show(error.localizedDescription, icon: "exclamationmark.triangle.fill")
            }
        }
    }
    
    // MARK: - X Chat Sending
    
    private func isXChatConversation(_ convId: String) -> Bool {
        convId.contains(":") || (messagesByConv[convId] ?? []).contains { $0.keyVersion != nil }
    }
    
    private func conversationKey(version: String) -> Data? {
        if let key = conversationKeys[version] { return key }
        guard let priv = privateKey, let raw = rawConversationKeyEvents[version],
              let key = DMAPI.shared.decryptConversationKey(data: raw, privateKey: priv) else { return nil }
        conversationKeys[version] = key
        return key
    }
    
    /// The signing key and the newest conversation key this account can open for `convId`.
    func sendKeys(for convId: String) -> XChatSendKeys? {
        guard let signingKey, let signingKeyVersion else { return nil }
        var versions = XChatConversationState.shared.keyVersions(for: convId)
        for m in messagesByConv[convId] ?? [] {
            if let v = m.keyVersion { versions.insert(v) }
        }
        // Versions are creation times in milliseconds, so the largest is the newest.
        for version in versions.sorted(by: { (Int64($0) ?? 0) > (Int64($1) ?? 0) }) {
            if let key = conversationKey(version: version) {
                return XChatSendKeys(
                    conversationKey: key,
                    conversationKeyVersion: version,
                    signingKey: signingKey,
                    signingKeyVersion: signingKeyVersion
                )
            }
        }
        return nil
    }
    
    private func sendXChatMessage(_ text: String, attachments: [URL], conversationId convId: String) {
        let loc = LocalizationManager.shared
        guard attachments.isEmpty else {
            AppToastManager.shared.show(loc.t("messages_send_attachments_unsupported"), icon: "paperclip")
            return
        }
        guard let keys = sendKeys(for: convId) else {
            // Without the signing key nothing can be sent; recovering the secret again brings it back.
            if signingKey == nil {
                AppToastManager.shared.show(loc.t("messages_send_needs_passcode"), icon: "lock.fill")
                promptPasscode()
            } else {
                AppToastManager.shared.show(loc.t("messages_send_no_key"), icon: "exclamationmark.triangle.fill")
            }
            return
        }
        
        inputText = ""
        isSending = true
        let activeUserId = AccountManager.shared.activeId ?? ""
        let messageId = UUID().uuidString.lowercased()
        let optimisticMsg = DMMessage(
            id: messageId,
            conversationId: convId,
            senderId: activeUserId,
            recipientId: selectedConversation?.otherParticipant?.id,
            text: text,
            createdAt: Date(),
            isOutgoing: true,
            keyVersion: keys.conversationKeyVersion
        )
        messagesByConv[convId, default: []].append(optimisticMsg)
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].lastMessage = optimisticMsg
        }
        
        DMAPI.shared.sendXChatMessage(conversationId: convId, messageId: messageId, text: text, keys: keys) { [weak self] result in
            guard let self else { return }
            self.isSending = false
            var current = self.messagesByConv[convId] ?? []
            switch result {
            case .success(let realMsg):
                if let i = current.firstIndex(where: { $0.id == messageId }) {
                    current[i] = realMsg
                }
                self.messagesByConv[convId] = current
                if let idx = self.conversations.firstIndex(where: { $0.id == convId }) {
                    self.conversations[idx].lastMessage = realMsg
                }
            case .failure(let error):
                // Take the message back out and give the text back, so nothing typed is lost.
                current.removeAll { $0.id == messageId }
                self.messagesByConv[convId] = current
                if let idx = self.conversations.firstIndex(where: { $0.id == convId }) {
                    self.conversations[idx].lastMessage = current.last
                }
                if self.inputText.isEmpty { self.inputText = text }
                AppToastManager.shared.show(
                    loc.format("messages_send_failed", ["reason": error.localizedDescription]),
                    icon: "exclamationmark.triangle.fill"
                )
            }
        }
    }
    
    // MARK: - Pin Management
    
    func togglePin(for conversationId: String) {
        if pinnedConversationIds.contains(conversationId) {
            pinnedConversationIds.remove(conversationId)
        } else {
            pinnedConversationIds.insert(conversationId)
        }
        UserDefaults.standard.set(Array(pinnedConversationIds), forKey: pinnedStorageKey)
        
        // Update model in-place
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].isPinned = pinnedConversationIds.contains(conversationId)
        }
    }
    
    func batchTogglePinSelected() {
        for cid in selectedConversationIds {
            togglePin(for: cid)
        }
        selectedConversationIds.removeAll()
        isEditMode = false
    }
    
    func batchMarkAsReadSelected() {
        for cid in selectedConversationIds {
            if let idx = conversations.firstIndex(where: { $0.id == cid }) {
                conversations[idx].unreadCount = 0
            }
        }
        selectedConversationIds.removeAll()
        isEditMode = false
    }
}

// MARK: - Hex Data Conversion Extension

private extension Data {
    init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            let byteString = clean[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

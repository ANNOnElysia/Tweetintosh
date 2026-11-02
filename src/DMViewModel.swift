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
    var decryptedMessageCache: [String: String] = [:]
    var rawConversationKeyEvents: [String: Data] = [:]
    var conversationKeys: [String: Data] = [:]
    
    private let pinnedStorageKey = "com.anno.tweetintosh.dm.pinned"
    @Published var pinnedConversationIds: Set<String> = []
    
    private var passcodeStorageKey: String {
        let activeId = AccountManager.shared.activeId ?? "default"
        return "com.anno.tweetintosh.dm.privkey.\(activeId)"
    }
    
    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: pinnedStorageKey) {
            self.pinnedConversationIds = Set(saved)
        }
        
        // Restore verified private key from secure persistent storage if already unlocked
        if let savedHex = UserDefaults.standard.string(forKey: "com.anno.tweetintosh.dm.privkey.\(AccountManager.shared.activeId ?? "default")"),
           let keyData = Data(hexString: savedHex),
           let priv = try? P256.KeyAgreement.PrivateKey(rawRepresentation: keyData.prefix(32)) {
            self.privateKey = priv
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
               let keyData = Data(hexString: savedHex),
               let priv = try? P256.KeyAgreement.PrivateKey(rawRepresentation: keyData.prefix(32)) {
                self.privateKey = priv
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
            case .success(let hexKey):
                guard let keyData = Data(hexString: hexKey),
                      let privKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: keyData.prefix(32)) else {
                    self.passcodeErrorMessage = LocalizationManager.shared.t("messages_passcode_error")
                    completion?(false)
                    return
                }
                
                self.privateKey = privKey
                self.isPasscodeUnlocked = true
                self.passcodeInput = clean
                self.showPasscodeSheet = false
                
                // Persist verified private key so the user stays unlocked across launches
                UserDefaults.standard.set(hexKey, forKey: self.passcodeStorageKey)
                
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
                    var decryptedText: String? = nil
                    
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
                    
                    if let text = decryptedText {
                        decryptedMessageCache[msg.id] = text
                        let newMsg = DMMessage(
                            id: msg.id,
                            conversationId: msg.conversationId,
                            senderId: msg.senderId,
                            recipientId: msg.recipientId,
                            text: text,
                            createdAt: msg.createdAt,
                            isOutgoing: msg.isOutgoing,
                            mediaUrl: msg.mediaUrl,
                            isEncrypted: false,
                            rawCiphertextBase64: b64,
                            keyVersion: msg.keyVersion
                        )
                        updatedMsgs.append(newMsg)
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

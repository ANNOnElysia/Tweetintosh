//
//  TweetTranslation.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Post translation supporting Apple's on-device Translation framework (macOS 15+) and custom OpenAI-compatible BYOK endpoints.
//

import SwiftUI
import NaturalLanguage
import Translation

enum TranslationEngine: String, CaseIterable, Identifiable {
    case apple
    case byok

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .apple: return LocalizationManager.shared.t("translation_engine_apple")
        case .byok: return LocalizationManager.shared.t("translation_engine_byok")
        }
    }
}

/// A row of the model picker. The search key is lowered once when the catalog is built, so filtering compares strings
/// instead of lowercasing every model on every keystroke.
struct ModelOption: Identifiable, Hashable {
    let id: String
    let label: String
    let searchKey: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
        // A preset's label carries its family ("Claude · …"), which users search for, while a fetched model's label
        // is its identifier again; joining the two would double every fetched model's key.
        self.searchKey = label == id ? id.lowercased() : "\(id) \(label)".lowercased()
    }
}

/// Everything the model picker shows, sorted and grouped when `/models` answers. The picker reads this straight, so
/// opening it sorts and filters nothing.
struct ModelCatalog {
    let recommended: [ModelOption]
    let models: [ModelOption]

    /// Curated list used before `/models` has been fetched, or when the endpoint's models match no known family.
    static let fallback = ModelCatalog(
        recommended: [
            ModelOption(id: "deepseek-chat", label: "DeepSeek · deepseek-chat"),
            ModelOption(id: "gpt-4.1-mini", label: "OpenAI · gpt-4.1-mini"),
            ModelOption(id: "gpt-4o-mini", label: "OpenAI · gpt-4o-mini"),
            ModelOption(id: "claude-haiku-4-5", label: "Claude · claude-haiku-4-5"),
            ModelOption(id: "gemini-2.5-flash", label: "Gemini · gemini-2.5-flash"),
        ],
        models: []
    )
}

final class TranslationSettingsManager: ObservableObject {
    static let shared = TranslationSettingsManager()

    @Published var engine: TranslationEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: Keys.engine) }
    }
    /// `nil` means follow `LocalizationManager.shared.currentLanguage`.
    @Published var targetLanguage: AppLanguage? {
        didSet { UserDefaults.standard.set(targetLanguage?.rawValue ?? "", forKey: Keys.targetLanguage) }
    }
    @Published var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }
    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: Keys.modelName) }
    }
    @Published private(set) var catalog = ModelCatalog.fallback
    @Published var isVerifying: Bool = false
    @Published var verificationStatus: VerificationStatus? = nil

    enum VerificationStatus: Equatable {
        case success(String)
        case failure(String)
    }

    /// One fetched identifier with the values the sorts need, so a comparison never re-parses a model name.
    private struct KeyedModel {
        let id: String
        let searchKey: String
        let numbers: [Int]
    }

    /// Sorts the fetched identifiers and picks the recommended tiers once, when the endpoint answers.
    private static func makeCatalog(from ids: [String]) -> ModelCatalog {
        let keyed = Set(ids).map {
            KeyedModel(id: $0, searchKey: $0.lowercased(), numbers: extractNumbers($0))
        }
        let sorted = keyed.sorted { lhs, rhs in
            let lScore = flashSortScore(lhs.searchKey)
            let rScore = flashSortScore(rhs.searchKey)
            if lScore != rScore { return lScore < rScore }
            return versionNumbersDescending(lhs, rhs)
        }

        let families: [(name: String, matches: (String) -> Bool)] = [
            ("DeepSeek", { s in
                s.contains("deepseek") && !s.contains("r1") && !s.contains("reasoner")
            }),
            ("OpenAI", { s in
                (s.contains("gpt") || s.hasPrefix("o")) && (s.contains("mini") || s.contains("nano"))
                    && !s.contains("audio") && !s.contains("realtime") && !s.contains("tts")
                    && !s.contains("transcribe") && !s.contains("image") && !s.contains("search")
            }),
            ("Claude", { s in
                s.contains("claude") && s.contains("haiku")
            }),
            ("Gemini", { s in
                s.contains("gemini") && s.contains("flash")
                    && !s.contains("image") && !s.contains("tts") && !s.contains("live")
            }),
        ]

        var recommended: [ModelOption] = []
        for family in families {
            let candidates = sorted
                .filter { family.matches($0.searchKey) }
                .sorted { versionNumbersDescending($0, $1) }
                .prefix(2)
            for model in candidates {
                recommended.append(ModelOption(id: model.id, label: "\(family.name) · \(model.id)"))
            }
        }

        return ModelCatalog(
            recommended: recommended.isEmpty ? ModelCatalog.fallback.recommended : recommended,
            models: sorted.map { ModelOption(id: $0.id, label: $0.id) }
        )
    }

    var effectiveTargetLanguage: AppLanguage {
        targetLanguage ?? LocalizationManager.shared.currentLanguage
    }

    private enum Keys {
        static let engine = "Tweetintosh_TranslationEngine"
        static let targetLanguage = "Tweetintosh_TranslationTargetLanguage"
        static let apiBaseURL = "Tweetintosh_TranslationBaseURL"
        static let apiKey = "Tweetintosh_TranslationAPIKey"
        static let modelName = "Tweetintosh_TranslationModelName"
    }

    private init() {
        let rawEngine = UserDefaults.standard.string(forKey: Keys.engine) ?? TranslationEngine.apple.rawValue
        self.engine = TranslationEngine(rawValue: rawEngine) ?? .apple
        let rawTarget = UserDefaults.standard.string(forKey: Keys.targetLanguage) ?? ""
        self.targetLanguage = AppLanguage(rawValue: rawTarget)
        self.apiBaseURL = UserDefaults.standard.string(forKey: Keys.apiBaseURL) ?? "https://api.openai.com/v1"
        self.apiKey = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
        self.modelName = UserDefaults.standard.string(forKey: Keys.modelName) ?? "gpt-4o-mini"
    }

    enum BYOKError: LocalizedError {
        case missingKey
        case invalidURL
        case serverError(String)
        case emptyResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return LocalizationManager.shared.t("translation_missing_key")
            case .invalidURL:
                return "Invalid API Base URL"
            case .serverError(let msg):
                return msg
            case .emptyResponse(let detail):
                return detail.isEmpty ? "Empty response from model" : "Empty response from model (\(detail))"
            }
        }
    }

    /// Resolves `/chat/completions` or `/models` against the user's configured Base URL.
    private func resolvedEndpoint(suffix: String) throws -> URL {
        let rawBase = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = rawBase.isEmpty ? "https://api.openai.com/v1" : rawBase
        var trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedBase.hasSuffix("/chat/completions") {
            trimmedBase = String(trimmedBase.dropLast("/chat/completions".count))
        }
        let endpointString: String
        if let parsed = URL(string: trimmedBase), parsed.path.isEmpty || parsed.path == "/" {
            // Bare domain (e.g. https://relay.example.com) -> default to /v1/...
            endpointString = trimmedBase + "/v1" + suffix
        } else {
            endpointString = trimmedBase + suffix
        }
        guard let url = URL(string: endpointString) else { throw BYOKError.invalidURL }
        return url
    }

    /// Verifies Base URL + API Key and fetches available models (prioritizing Flash/fast-tier models).
    @MainActor
    func verifyAndFetchModels() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            verificationStatus = .failure(LocalizationManager.shared.t("translation_missing_key"))
            return
        }
        isVerifying = true
        verificationStatus = nil
        defer { isVerifying = false }

        do {
            let url = try resolvedEndpoint(suffix: "/models")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Tweetintosh/0.1", forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard (200...299).contains(status) else {
                let apiMessage = (json?["error"] as? [String: Any])?["message"] as? String
                verificationStatus = .failure(apiMessage ?? "HTTP \(status)")
                return
            }

            if let items = json?["data"] as? [[String: Any]] {
                let ids = items.compactMap { $0["id"] as? String }
                catalog = Self.makeCatalog(from: ids)
                if !catalog.models.isEmpty && !catalog.models.contains(where: { $0.id == modelName }) {
                    if let firstRecommended = catalog.recommended.first?.id {
                        modelName = firstRecommended
                    }
                }
                verificationStatus = .success(
                    LocalizationManager.shared.format("translation_verified_count", ["count": String(catalog.models.count)])
                )
            } else {
                let rawPreview = String(data: data.prefix(100), encoding: .utf8)?
                    .replacingOccurrences(of: "\n", with: " ") ?? "HTTP \(status)"
                if rawPreview.lowercased().contains("<html") || rawPreview.lowercased().contains("<!doctype") {
                    verificationStatus = .failure("Endpoint returned HTML instead of JSON (check Base URL)")
                } else {
                    verificationStatus = .failure("Unexpected /models response")
                }
            }
        } catch {
            verificationStatus = .failure(error.localizedDescription)
        }
    }

    private static func flashSortScore(_ searchKey: String) -> Int {
        if searchKey.contains("flash") { return 0 }
        if searchKey.contains("haiku") { return 1 }
        if searchKey.contains("mini") || searchKey.contains("nano") { return 2 }
        if searchKey == "deepseek-chat" || searchKey.contains("deepseek-v3") { return 3 }
        return 4
    }

    /// Compares model IDs primarily by their embedded version numbers descending (e.g. 4.5 > 4.1 > 3.5, 3 > 2.5).
    private static func versionNumbersDescending(_ lhs: KeyedModel, _ rhs: KeyedModel) -> Bool {
        for (a, b) in zip(lhs.numbers, rhs.numbers) where a != b {
            return a > b
        }
        if lhs.numbers.count != rhs.numbers.count {
            return lhs.numbers.count > rhs.numbers.count
        }
        return lhs.searchKey < rhs.searchKey
    }

    private static func extractNumbers(_ s: String) -> [Int] {
        var numbers: [Int] = []
        var buffer = ""
        for ch in s {
            if ch.isASCII && ch.isNumber {
                buffer.append(ch)
            } else if !buffer.isEmpty {
                if let val = Int(buffer) { numbers.append(val) }
                buffer = ""
            }
        }
        if !buffer.isEmpty, let val = Int(buffer) {
            numbers.append(val)
        }
        return numbers
    }

    /// Translates `text` using the user's configured OpenAI-compatible Chat Completions endpoint.
    func translateWithBYOK(_ text: String, to target: AppLanguage) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw BYOKError.missingKey }

        let url = try resolvedEndpoint(suffix: "/chat/completions")

        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.isEmpty ? "gpt-4o-mini" : model
        let targetName = targetLanguageEnglishName(for: target)

        let payload: [String: Any] = [
            "model": resolvedModel,
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": "Translate the following social media post into \(targetName). Preserve @mentions, #hashtags, emojis, line breaks, and tone. Output ONLY the translated text without quotes or explanations."
                ],
                [
                    "role": "user",
                    "content": text
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Tweetintosh/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard (200...299).contains(status) else {
            let apiMessage = (json?["error"] as? [String: Any])?["message"] as? String
            throw BYOKError.serverError(apiMessage ?? "HTTP \(status)")
        }

        if let choices = json?["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let parts = message["content"] as? [[String: Any]] {
                let joined = parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { return joined }
            }
            let finishReason = first["finish_reason"] as? String ?? "unknown"
            throw BYOKError.emptyResponse("finish_reason=\(finishReason)")
        }

        let rawPreview = String(data: data.prefix(120), encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ") ?? "HTTP \(status)"
        if rawPreview.lowercased().contains("<html") || rawPreview.lowercased().contains("<!doctype") {
            throw BYOKError.serverError("Endpoint returned HTML instead of JSON (check API Base URL, e.g. missing /v1)")
        }
        throw BYOKError.emptyResponse(rawPreview)
    }

    private func targetLanguageEnglishName(for language: AppLanguage) -> String {
        switch language {
        case .english: return "English"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        }
    }
}

/// In-memory cache of translated post bodies keyed by "<tweetId>:<targetLang>:<engine>".
final class TweetTranslationCache {
    static let shared = TweetTranslationCache()
    private var entries: [String: String] = [:]
    // The order entries arrived, so a long session can drop its oldest translations rather than keep every post read.
    private var order: [String] = []
    private static let entryLimit = 200
    private let lock = NSLock()

    private init() {}

    func get(tweetId: String, target: AppLanguage, engine: TranslationEngine) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries["\(tweetId):\(target.rawValue):\(engine.rawValue)"]
    }

    func set(_ text: String, tweetId: String, target: AppLanguage, engine: TranslationEngine) {
        let key = "\(tweetId):\(target.rawValue):\(engine.rawValue)"
        lock.lock()
        defer { lock.unlock() }
        if entries.updateValue(text, forKey: key) == nil {
            order.append(key)
            if order.count > Self.entryLimit {
                let excess = order.count - Self.entryLimit
                for old in order.prefix(excess) { entries[old] = nil }
                order.removeFirst(excess)
            }
        }
    }
}

enum TweetTranslationSupport {
    /// Returns true when the post body has meaningful natural-language text that differs from the app's current language.
    static func needsTranslation(text: String, target: AppLanguage) -> Bool {
        let stripped = stripNonLinguisticTokens(text)
        guard stripped.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return false
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(stripped)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            return false
        }
        return dominant != nlLanguage(for: target)
    }

    private static func nlLanguage(for appLanguage: AppLanguage) -> NLLanguage {
        switch appLanguage {
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        case .simplifiedChinese: return .simplifiedChinese
        case .traditionalChinese: return .traditionalChinese
        }
    }

    /// Removes URLs and @handles so they don't skew language detection on short posts.
    private static func stripNonLinguisticTokens(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .filter { token in
                let s = token.lowercased()
                return !s.hasPrefix("http://") && !s.hasPrefix("https://") && !s.hasPrefix("@")
            }
            .joined(separator: " ")
    }
}

/// Inline "Translate post" / "Show original" control placed directly under the post body, matching X's layout.
struct TweetTranslateControl: View {
    let tweetId: String
    let sourceText: String
    @Binding var translatedText: String?
    @Binding var showingTranslation: Bool

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var settings = TranslationSettingsManager.shared
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false

    private var targetLanguage: AppLanguage {
        settings.targetLanguage ?? loc.currentLanguage
    }

    var body: some View {
        if TweetTranslationSupport.needsTranslation(text: sourceText, target: targetLanguage) {
            Button(action: handleTap) {
                HStack(spacing: 5) {
                    if isTranslating {
                        ProgressView()
                            .controlSize(.mini)
                        Text(loc.t("translating_post"))
                            .font(theme.appFont(size: 13))
                            .foregroundColor(ThemeManager.secondaryText)
                    } else {
                        Text(showingTranslation ? loc.t("show_original") : loc.t("translate_post"))
                            .font(theme.appFont(size: 13, weight: .medium))
                            .foregroundColor(ThemeManager.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.target)
            .disabled(isTranslating)
            .padding(.top, 2)
            .onAppear {
                if translatedText == nil,
                   let cached = TweetTranslationCache.shared.get(tweetId: tweetId, target: targetLanguage, engine: settings.engine) {
                    translatedText = cached
                }
            }
            .onChange(of: targetLanguage) { _, newLang in
                showingTranslation = false
                translatedText = TweetTranslationCache.shared.get(tweetId: tweetId, target: newLang, engine: settings.engine)
            }
            .onChange(of: settings.engine) { _, newEngine in
                showingTranslation = false
                translatedText = TweetTranslationCache.shared.get(tweetId: tweetId, target: targetLanguage, engine: newEngine)
            }
            .translationTask(translationConfig) { session in
                await performAppleTranslation(using: session)
            }
        }
    }

    private func handleTap() {
        if showingTranslation {
            showingTranslation = false
            return
        }
        if let cached = translatedText ?? TweetTranslationCache.shared.get(tweetId: tweetId, target: targetLanguage, engine: settings.engine) {
            translatedText = cached
            showingTranslation = true
            return
        }

        switch settings.engine {
        case .apple:
            isTranslating = true
            let target = Locale.Language(identifier: targetLanguage.rawValue)
            if translationConfig == nil {
                translationConfig = TranslationSession.Configuration(source: nil, target: target)
            } else {
                translationConfig?.target = target
                translationConfig?.invalidate()
            }
        case .byok:
            isTranslating = true
            let target = targetLanguage
            Task {
                await performBYOKTranslation(target: target)
            }
        }
    }

    @MainActor
    private func performAppleTranslation(using session: TranslationSession) async {
        defer { isTranslating = false }
        do {
            let response = try await session.translate(sourceText)
            let result = response.targetText
            TweetTranslationCache.shared.set(result, tweetId: tweetId, target: targetLanguage, engine: .apple)
            translatedText = result
            showingTranslation = true
        } catch {
            showingTranslation = false
        }
    }

    @MainActor
    private func performBYOKTranslation(target: AppLanguage) async {
        defer { isTranslating = false }
        do {
            let result = try await settings.translateWithBYOK(sourceText, to: target)
            TweetTranslationCache.shared.set(result, tweetId: tweetId, target: target, engine: .byok)
            translatedText = result
            showingTranslation = true
        } catch {
            showingTranslation = false
            let msg = (error as? TranslationSettingsManager.BYOKError)?.errorDescription ?? error.localizedDescription
            if case TranslationSettingsManager.BYOKError.missingKey = error {
                AppToastManager.shared.show(msg, icon: "key")
            } else {
                AppToastManager.shared.show(loc.format("translation_failed", ["error": msg]), icon: "exclamationmark.triangle")
            }
        }
    }
}

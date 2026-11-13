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
    @Published var fetchedModels: [String] = []
    @Published var isVerifying: Bool = false
    @Published var verificationStatus: VerificationStatus? = nil

    enum VerificationStatus: Equatable {
        case success(String)
        case failure(String)
    }

    struct PresetModel: Identifiable {
        let id: String
        let label: String
    }

    /// Curated fallback list used only before `/models` has been fetched.
    static let fallbackFlashModels: [PresetModel] = [
        PresetModel(id: "deepseek-chat", label: "DeepSeek · deepseek-chat"),
        PresetModel(id: "gpt-4.1-mini", label: "OpenAI · gpt-4.1-mini"),
        PresetModel(id: "gpt-4o-mini", label: "OpenAI · gpt-4o-mini"),
        PresetModel(id: "claude-haiku-4-5", label: "Claude · claude-haiku-4-5"),
        PresetModel(id: "gemini-2.5-flash", label: "Gemini · gemini-2.5-flash"),
    ]

    /// Returns the latest 1-2 Flash/fast-tier models per family from `fetchedModels` when available,
    /// falling back to `fallbackFlashModels` before models are fetched.
    var activeRecommendedModels: [PresetModel] {
        guard !fetchedModels.isEmpty else { return Self.fallbackFlashModels }

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

        var result: [PresetModel] = []
        for family in families {
            let candidates = fetchedModels
                .filter { family.matches($0.lowercased()) }
                .sorted { Self.versionNumbersDescending($0, $1) }
                .prefix(2)
            for id in candidates {
                result.append(PresetModel(id: id, label: "\(family.name) · \(id)"))
            }
        }
        return result.isEmpty ? Self.fallbackFlashModels : result
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
                let unique = Array(Set(ids)).sorted { lhs, rhs in
                    let lScore = Self.flashSortScore(lhs)
                    let rScore = Self.flashSortScore(rhs)
                    if lScore != rScore { return lScore < rScore }
                    return Self.versionNumbersDescending(lhs, rhs)
                }
                fetchedModels = unique
                if !unique.isEmpty && !unique.contains(modelName) {
                    if let firstRecommended = activeRecommendedModels.first?.id {
                        modelName = firstRecommended
                    }
                }
                verificationStatus = .success(
                    LocalizationManager.shared.format("translation_verified_count", ["count": String(unique.count)])
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

    private static func flashSortScore(_ id: String) -> Int {
        let s = id.lowercased()
        if s.contains("flash") { return 0 }
        if s.contains("haiku") { return 1 }
        if s.contains("mini") || s.contains("nano") { return 2 }
        if s == "deepseek-chat" || s.contains("deepseek-v3") { return 3 }
        return 4
    }

    /// Compares model IDs primarily by their embedded version numbers descending (e.g. 4.5 > 4.1 > 3.5, 3 > 2.5).
    private static func versionNumbersDescending(_ lhs: String, _ rhs: String) -> Bool {
        let lNums = extractNumbers(lhs)
        let rNums = extractNumbers(rhs)
        for (a, b) in zip(lNums, rNums) {
            if a != b { return a > b }
        }
        if lNums.count != rNums.count {
            return lNums.count > rNums.count
        }
        return lhs.lowercased() < rhs.lowercased()
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
    private let lock = NSLock()

    private init() {}

    func get(tweetId: String, target: AppLanguage, engine: TranslationEngine) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries["\(tweetId):\(target.rawValue):\(engine.rawValue)"]
    }

    func set(_ text: String, tweetId: String, target: AppLanguage, engine: TranslationEngine) {
        lock.lock()
        entries["\(tweetId):\(target.rawValue):\(engine.rawValue)"] = text
        lock.unlock()
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

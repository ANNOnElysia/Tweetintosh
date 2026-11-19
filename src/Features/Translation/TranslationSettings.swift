//
//  TranslationSettings.swift
//  Tweetintosh
//
//  Translation engine choice, endpoint settings, model catalog and the OpenAI-compatible BYOK client.
//

import Foundation
import SwiftUI

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
    let searchKey: String

    init(id: String) {
        self.id = id
        self.searchKey = id.lowercased()
    }
}

/// Everything the model picker shows: only the identifiers the user's endpoint returned. The picker reads this
/// straight, so opening it sorts and filters nothing.
struct ModelCatalog {
    let models: [ModelOption]

    /// What the picker holds before `/models` answers; there is nothing to offer until the user verifies.
    static let empty = ModelCatalog(models: [])
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
    @Published private(set) var catalog = ModelCatalog.empty
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

    /// Sorts the fetched identifiers once, when the endpoint answers.
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

        return ModelCatalog(models: sorted.map { ModelOption(id: $0.id) })
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
                return LocalizationManager.shared.t("translation_invalid_base_url")
            case .serverError(let msg):
                return msg
            case .emptyResponse(let detail):
                let loc = LocalizationManager.shared
                return detail.isEmpty
                    ? loc.t("translation_empty_response")
                    : loc.format("translation_empty_response_detail", ["detail": detail])
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
                    if let firstModel = catalog.models.first?.id {
                        modelName = firstModel
                    }
                }
                verificationStatus = .success(
                    LocalizationManager.shared.format("translation_verified_count", ["count": String(catalog.models.count)])
                )
            } else {
                let rawPreview = String(data: data.prefix(100), encoding: .utf8)?
                    .replacingOccurrences(of: "\n", with: " ") ?? "HTTP \(status)"
                if rawPreview.lowercased().contains("<html") || rawPreview.lowercased().contains("<!doctype") {
                    verificationStatus = .failure(LocalizationManager.shared.t("translation_html_response"))
                } else {
                    verificationStatus = .failure(LocalizationManager.shared.t("translation_unexpected_response"))
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
            throw BYOKError.serverError(LocalizationManager.shared.t("translation_html_response"))
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


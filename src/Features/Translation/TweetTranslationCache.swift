//
//  TweetTranslationCache.swift
//  Tweetintosh
//
//  Translated post bodies and the language check that decides whether a post needs translating.
//

import Foundation
import NaturalLanguage

/// In-memory cache of translated post bodies keyed by "<tweetId>:<targetLang>:<engine>".
final class TweetTranslationCache {
    static let shared = TweetTranslationCache()
    private var entries: [String: String] = [:]
    // Bounded so a long session does not keep every translation it ever showed; a miss asks the engine again.
    private var order: [String] = []
    private static let maxEntries = 300
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
        if entries[key] == nil { order.append(key) }
        entries[key] = text
        if order.count > Self.maxEntries {
            entries.removeValue(forKey: order.removeFirst())
        }
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

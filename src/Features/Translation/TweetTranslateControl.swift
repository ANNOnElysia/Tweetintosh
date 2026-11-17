//
//  TweetTranslateControl.swift
//  Tweetintosh
//
//  Inline "Translate post" / "Show original" control placed under a post body.
//

import SwiftUI
import Translation

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

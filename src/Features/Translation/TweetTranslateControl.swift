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
    // Identifies the translation whose result may still be shown. A language or engine change bumps it so a late
    // answer cannot replace the newly chosen language's result.
    @State private var requestGeneration = 0
    // Apple's translation task hands back only the session, so the target it started for travels here.
    @State private var appleRequest: AppleRequest?

    private struct AppleRequest {
        let generation: Int
        let target: AppLanguage
    }

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
                cancelInFlightTranslation()
                showingTranslation = false
                translatedText = TweetTranslationCache.shared.get(tweetId: tweetId, target: newLang, engine: settings.engine)
            }
            .onChange(of: settings.engine) { _, newEngine in
                cancelInFlightTranslation()
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

        requestGeneration &+= 1
        let generation = requestGeneration
        switch settings.engine {
        case .apple:
            let target = targetLanguage
            appleRequest = AppleRequest(generation: generation, target: target)
            isTranslating = true
            let localeTarget = Locale.Language(identifier: target.rawValue)
            if translationConfig == nil {
                translationConfig = TranslationSession.Configuration(source: nil, target: localeTarget)
            } else {
                translationConfig?.target = localeTarget
                translationConfig?.invalidate()
            }
        case .byok:
            let target = targetLanguage
            appleRequest = nil
            translationConfig = nil
            isTranslating = true
            Task {
                await performBYOKTranslation(target: target, generation: generation)
            }
        }
    }

    // Called when the chosen language or engine changes: the old answer is no longer the one this control should show.
    private func cancelInFlightTranslation() {
        requestGeneration &+= 1
        appleRequest = nil
        translationConfig = nil
        isTranslating = false
    }

    @MainActor
    private func performAppleTranslation(using session: TranslationSession) async {
        guard let request = appleRequest else { return }
        defer {
            if requestGeneration == request.generation {
                isTranslating = false
                appleRequest = nil
            }
        }
        do {
            let response = try await session.translate(sourceText)
            let result = response.targetText
            // Cache under the language this request actually asked for, not whichever is selected now.
            TweetTranslationCache.shared.set(result, tweetId: tweetId, target: request.target, engine: .apple)
            guard requestGeneration == request.generation else { return }
            translatedText = result
            showingTranslation = true
        } catch {
            guard requestGeneration == request.generation else { return }
            showingTranslation = false
        }
    }

    @MainActor
    private func performBYOKTranslation(target: AppLanguage, generation: Int) async {
        defer {
            if requestGeneration == generation {
                isTranslating = false
            }
        }
        do {
            let result = try await settings.translateWithBYOK(sourceText, to: target)
            TweetTranslationCache.shared.set(result, tweetId: tweetId, target: target, engine: .byok)
            guard requestGeneration == generation else { return }
            translatedText = result
            showingTranslation = true
        } catch {
            guard requestGeneration == generation else { return }
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

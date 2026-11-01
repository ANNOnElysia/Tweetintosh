//
//  XFailures.swift
//  Tweetintosh - Headless Data-driven Client
//  What X's numeric refusal codes mean. X's own web client carries the same table: 344 is
//  UserActionRateLimitExceeded, 226 is TieredActionTweetSpammer, 187 a duplicate status, and so on. Showing the
//  number on its own ("344") told the user nothing and looked like a crash, so refusals are explained here, and the
//  explanation says what would actually lift the limit.

import Foundation

enum XFailure {
    /// The code X answered with, from {"errors":[{"code":344,"message":"..."}]}. It arrives as a number, sometimes as
    /// a numeric string, and the oldest responses only carry `message`.
    static func code(in errors: [[String: Any]]) -> Int? {
        for error in errors {
            if let number = error["code"] as? Int { return number }
            if let text = error["code"] as? String, let number = Int(text) { return number }
        }
        return nil
    }

    /// The localization key explaining a refusal, or nil when the code is one this app has nothing to add about.
    static func localizationKey(for code: Int?) -> String? {
        switch code {
        // "You have reached your daily limit for this action. Please add a phone to your account to remove the
        // limit." X applies it per action, to accounts it trusts least
        case 344: return "error_rate_limited"
        case 185: return "error_daily_limit"
        // The automated-activity tier: posting, replying or mentioning in a way X's spam scoring dislikes
        case 225, 226, 227, 228, 283, 292, 429: return "error_automated"
        case 187: return "error_duplicate"
        case 186: return "error_too_long"
        // The session behind the request is gone: X wants the account signed in again
        case 32, 89: return "error_session_expired"
        case 63, 64: return "error_account_suspended"
        // The post itself is hidden from everyone but the author
        case 421, 422: return "error_post_bounced"
        default: return nil
        }
    }

    /// A symbol that matches the reason, so a limit looks like a wait rather than a refusal.
    static func iconName(for code: Int?) -> String {
        switch code {
        case 344, 185: return "hourglass"
        case 225, 226, 227, 228, 283, 292, 429: return "exclamationmark.shield"
        case 32, 89: return "person.crop.circle.badge.exclamationmark"
        default: return "hand.raised.fill"
        }
    }

    /// What to show for a refusal. X's own wording is kept when there is nothing better to say, because a message
    /// that is oddly phrased still beats a bare number.
    static func describe(code: Int?, serverMessage: String?, language: AppLanguage = LocalizationManager.shared.currentLanguage) -> String {
        if let key = localizationKey(for: code) {
            return LocalizationManager.shared.t(key, language: language)
        }
        if let serverMessage, !serverMessage.isEmpty { return serverMessage }
        if let code { return "X refused this (\(code))" }
        return "X refused this"
    }
}

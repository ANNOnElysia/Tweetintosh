//
//  EULA.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The End User License Agreement, and whether this Mac has accepted the current version of it.
//
//  The agreement is kept in English only: a translation of a legal text can be read differently from the original, so
//  one binding version is shown everywhere, with a plain-language summary above it in the reader's language.
//

import Foundation

// The version people see, read from Info.plist so it is set in one place
enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}

enum EULA {
    // Raise this when the text changes in a way people should agree to again; they are asked once more on next launch
    static let version = 1
    static let lastUpdated = "7 November 2026"
    static let contactAddress = "cyronanno@outlook.com"

    private static let acceptedVersionKey = "Tweetintosh_AcceptedEULAVersion"

    static var acceptedVersion: Int {
        UserDefaults.standard.integer(forKey: acceptedVersionKey)
    }

    static var needsAcceptance: Bool {
        acceptedVersion < version
    }

    // Accepted an earlier version, so this is an update rather than a first launch
    static var isUpdate: Bool {
        acceptedVersion > 0 && needsAcceptance
    }

    static func recordAcceptance() {
        UserDefaults.standard.set(version, forKey: acceptedVersionKey)
    }

    static let text = """
    TWEETINTOSH END USER LICENSE AGREEMENT
    Version \(version) · Last updated \(lastUpdated)

    Please read this agreement before using Tweetintosh (the "App"). By clicking "Agree" or by using the App, you accept \
    this agreement. If you do not accept it, click "Quit" and do not use the App.

    1. WHO THIS AGREEMENT IS WITH
    This agreement is between you and the developer of Tweetintosh ("we", "us"). The App is an independent project. It \
    is not made, sponsored, endorsed or supported by X Corp. "X" and related names and marks belong to their owners and \
    are used only to describe what the App works with.

    2. LICENSE
    We grant you a personal, non-exclusive, non-transferable, revocable license to install and use the App on Macs that \
    you own or control, for your own non-commercial use. We keep all rights not expressly granted to you. You may not \
    sell, rent or sublicense the App, or remove any notices from it, except as the law allows.

    3. YOUR X ACCOUNT AND X'S TERMS
    The App lets you use your own X account. It signs in through X's own website and then exchanges data with X's servers \
    in the same way X's website does. X does not offer this way of connecting as a public service for other apps, and it \
    may change, limit or stop it at any time. Features can therefore stop working without notice.
    Your use of X, including through the App, remains subject to X's own terms, rules and policies, which you are \
    responsible for following. Using a third-party app with your X account may be treated by X as against its rules, and \
    X could restrict or suspend your account as a result. You choose whether to use the App with your account, and you \
    accept that risk.

    4. YOUR DATA AND PRIVACY
    The App has no servers of its own and does not collect, sell or share your data. It contains no analytics, \
    advertising or tracking.
    - Your sign-in session, your accounts and cached timelines, notifications and media are stored only on your Mac, in \
      your user Library. Signing out of an account removes its stored sign-in. Removing the App's data folder removes \
      the rest.
    - The App connects only to X's servers (such as x.com, api.x.com and twimg.com), to do what you ask: load posts, \
      post, like, follow and so on.
    - A web page you choose to open or preview is loaded from its own website. Previews open in a private browsing \
      session that keeps no cookies or website data.
    What X does with data it receives is governed by X's own privacy policy.

    5. CONTENT
    Posts, images, videos and other content shown in the App come from X and its users, not from us. We do not control, \
    review or endorse that content and are not responsible for it. Content may be offensive, inaccurate or inappropriate, \
    and you view it at your own discretion.

    6. UPDATES
    We may update the App or this agreement. If this agreement changes in a meaningful way, the App will ask you to \
    accept the new version before you continue using it.

    7. NO WARRANTY
    THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING ANY \
    WARRANTY OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, OR THAT IT WILL WORK WITHOUT \
    INTERRUPTION OR ERROR, OR CONTINUE TO WORK WITH X.

    8. LIMITATION OF LIABILITY
    TO THE FULLEST EXTENT PERMITTED BY LAW, WE WILL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL \
    OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF DATA, ACCOUNT ACCESS, PROFITS OR GOODWILL, ARISING FROM YOUR USE OF OR \
    INABILITY TO USE THE APP, INCLUDING ANY ACTION X TAKES ON YOUR ACCOUNT. Some jurisdictions do not allow these \
    limitations, so they may not apply to you; nothing in this agreement limits rights you have under consumer law that \
    cannot be limited.

    9. TERMINATION
    This license ends automatically if you break this agreement. You may end it at any time by deleting the App and its \
    data. Sections 4 to 10 continue to apply after it ends.

    10. GENERAL
    If any part of this agreement is found unenforceable, the rest remains in effect. This agreement is the entire agreement between you and us \
    about the App.

    11. CONTACT
    Questions about this agreement: \(contactAddress).
    """
}

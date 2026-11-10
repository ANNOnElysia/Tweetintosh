//
//  UpdateManager.swift
//  Tweetintosh - Headless Data-driven Client
//
//  New versions come from GitHub Releases through Sparkle: the app reads appcast.xml from the main branch, and an
//  update installs only if its EdDSA signature matches the public key in Info.plist (SUPublicEDKey). Sparkle offers
//  only releases newer than the running build (by CFBundleVersion) whose minimum macOS and architecture fit this Mac,
//  so it never downgrades. RELEASING.md has the release steps.
//
//  Accounts, settings and caches live outside the app bundle (Application Support and the app's defaults), so an
//  update leaves them as they were.
//

import AppKit
import Observation
import Sparkle

@Observable
final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    // Developer Preview builds also take preview releases; other builds take only stable ones
    static let previewChannel = "preview"
    private var isPreviewBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "TweetintoshUpdateChannel") as? String) == Self.previewChannel
    }

    // nil until the build carries a signing key, so a build without one never offers an update it can't verify
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    // A scheduled check that found an update while a post was being written; shown once the composer closes
    @ObservationIgnored private var heldUpdate = false
    @ObservationIgnored private var composerObserver: Any?

    private(set) var isAvailable = false

    // Both choices are kept by Sparkle itself, in the app's defaults (SUEnableAutomaticChecks, SUAutomaticallyUpdate)
    var checksAutomatically: Bool = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    var installsAutomatically: Bool = false {
        didSet { controller?.updater.automaticallyDownloadsUpdates = installsAutomatically }
    }

    private override init() {
        super.init()
    }

    // Called once the app has finished launching
    func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard controller == nil, !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        isAvailable = true
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    // Check for Updates…: always answers, with the new version and its notes, "up to date", or why it couldn't check
    func checkForUpdates() {
        heldUpdate = false
        controller?.checkForUpdates(nil)
    }

    private var isComposing: Bool {
        let nav = NavigationManager.shared
        return nav.isShowingCompose || nav.isReplyComposerOpen
    }

    // Brings a held update forward once nothing is being written
    private func showHeldUpdateWhenFree() {
        guard composerObserver == nil else { return }
        composerObserver = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self, !self.isComposing else { return }
            timer.invalidate()
            self.composerObserver = nil
            if self.heldUpdate { self.checkForUpdates() }
        }
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        isPreviewBuild ? [Self.previewChannel] : []
    }
}

extension UpdateManager: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    // An update found in the background waits while a post or reply is being written, rather than covering it
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        if isComposing {
            heldUpdate = true
            showHeldUpdateWhenFree()
            return false
        }
        return true
    }
}

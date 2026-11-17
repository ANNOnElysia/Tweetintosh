//
//  Welcome.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The window shown on first launch, and again whenever the License Agreement changes: a short welcome and the agreement,
//  in one step, so people reach their timeline quickly. Nothing loads and nothing talks to X until it is accepted.
//  Settings → License Agreement shows the agreement again, to read only.
//

import SwiftUI
import AppKit

// MARK: - Window

final class WelcomeWindowController {
    private var window: NSWindow?
    private let onAccept: () -> Void
    private var appearanceObserver: NSObjectProtocol?

    init(onAccept: @escaping () -> Void) {
        self.onAccept = onAccept
        // The window's own background is AppKit's, so it is told when the Mac (or the app) switches appearance
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("Tweetintosh_AppearanceDidChange"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.window?.backgroundColor = ThemeManager.windowBackgroundColor
        }
    }

    deinit {
        if let observer = appearanceObserver { NotificationCenter.default.removeObserver(observer) }
    }

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeView.width, height: WelcomeView.height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = ThemeManager.windowBackgroundColor
        // Quit and Agree are the only ways out, so the window has no buttons of its own
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.contentView = NSHostingView(rootView: WelcomeView(
            isUpdate: EULA.isUpdate,
            onAgree: { [weak self] in self?.accept() },
            onQuit: { NSApp.terminate(nil) }
        ))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func accept() {
        EULA.recordAcceptance()
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        onAccept()
    }
}

// Settings → License Agreement: the same text, to read only
final class LicenseAgreementWindow {
    private static var window: NSWindow?

    static func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizationManager.shared.t("license_agreement")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = ThemeManager.windowBackgroundColor
        window.minSize = NSSize(width: 420, height: 400)
        window.contentView = NSHostingView(rootView: LicenseAgreementView { window.close() })
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Views

struct WelcomeView: View {
    static let width: CGFloat = 560
    static let height: CGFloat = 720

    let isUpdate: Bool
    let onAgree: () -> Void
    let onQuit: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(loc.t(isUpdate ? "eula_updated_title" : "welcome_title"))
                        .font(theme.appFont(size: 24, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                    Text(loc.t(isUpdate ? "eula_updated_subtitle" : "welcome_subtitle"))
                        .font(theme.appFont(size: 13))
                        .foregroundColor(ThemeManager.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !isUpdate {
                    VStack(alignment: .leading, spacing: 12) {
                        WelcomeFeatureRow(icon: "macwindow", title: loc.t("welcome_native_title"), detail: loc.t("welcome_native_detail"))
                        WelcomeFeatureRow(icon: "lock.shield", title: loc.t("welcome_private_title"), detail: loc.t("welcome_private_detail"))
                        WelcomeFeatureRow(icon: "person.badge.shield.checkmark", title: loc.t("welcome_independent_title"), detail: loc.t("welcome_independent_detail"))
                    }
                    .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.t("license_agreement"))
                        .font(theme.appFont(size: 13, weight: .semibold))
                        .foregroundColor(ThemeManager.primaryText)
                    Text(loc.t("eula_summary"))
                        .font(theme.appFont(size: 12))
                        .foregroundColor(ThemeManager.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    AgreementTextBox()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Text(loc.t("eula_accept_note"))
                    .font(theme.appFont(size: 11))
                    .foregroundColor(ThemeManager.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onQuit) {
                    Text(loc.t("eula_quit")).frame(minWidth: 64)
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Button(action: onAgree) {
                    Text(loc.t("eula_agree"))
                        .frame(minWidth: 64)
                        .foregroundStyle(ThemeManager.onAccent)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(ThemeManager.accent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .frame(width: Self.width, height: Self.height)
        .background(ThemeManager.background)
        .overlay(alignment: .topTrailing) {
            // Below the title bar's strip, where a click would otherwise start dragging the window
            WelcomeLanguagePicker()
                .padding(.top, 34)
                .padding(.trailing, 20)
        }
    }
}

// Sets the app's language for good, not just this window: everything after the welcome opens in the language chosen here
private struct WelcomeLanguagePicker: View {
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Picker(selection: $loc.currentLanguage) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        } label: {
            Label(loc.t("language"), systemImage: "globe")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help(loc.t("language"))
    }
}

private struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let detail: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(ThemeManager.accent)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.appFont(size: 13, weight: .semibold))
                    .foregroundColor(ThemeManager.primaryText)
                Text(detail)
                    .font(theme.appFont(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// The agreement itself, selectable so it can be copied
private struct AgreementTextBox: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ScrollView {
            Text(EULA.text)
                .font(.system(size: 11.5))
                .foregroundColor(ThemeManager.primaryText)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ThemeManager.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ThemeManager.border, lineWidth: 0.6)
        )
    }
}

struct LicenseAgreementView: View {
    let onDone: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.t("eula_summary"))
                .font(theme.appFont(size: 12))
                .foregroundColor(ThemeManager.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            AgreementTextBox()
            HStack {
                Text(loc.format("eula_accepted_version", ["version": "\(EULA.acceptedVersion)"]))
                    .font(theme.appFont(size: 11))
                    .foregroundColor(ThemeManager.tertiaryText)
                Spacer()
                Button(loc.t("done"), action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 18)
        .frame(minWidth: 420, minHeight: 400)
        .background(ThemeManager.background)
    }
}

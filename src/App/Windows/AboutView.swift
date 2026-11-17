import SwiftUI
import AppKit

final class AboutWindow: NSWindow {
    init(screen: NSScreen?) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = LocalizationManager.shared.t("menu_about")
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        backgroundColor = ThemeManager.windowBackgroundColor
        let view = NSHostingView(rootView: AboutView())
        contentView = view
        setContentSize(view.fittingSize)
        if let screen {
            let visibleFrame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visibleFrame.midX - frame.width / 2,
                                   y: visibleFrame.midY - frame.height / 2))
        } else {
            center()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelOperation(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct AboutView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    private var version: String {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return AppVersion.short
        }
        return "\(AppVersion.short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(loc.t("app_title"))
                    .font(theme.appFont(size: 22, weight: .semibold))
                    .foregroundColor(ThemeManager.primaryText)
                Text(loc.format("about_version", ["version": version]))
                    .font(theme.appFont(size: 13))
                    .foregroundColor(ThemeManager.secondaryText)
                    .textSelection(.enabled)
            }

            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com/ANNOnElysia/Tweetintosh")!) {
                    Label(loc.t("about_repository"), systemImage: "chevron.left.forwardslash.chevron.right")
                        .frame(width: 36, height: 36)
                }
                .help(loc.t("about_repository"))
                Link(destination: URL(string: "https://tweetintosh.cyronanno.com")!) {
                    Label(loc.t("about_website"), systemImage: "globe")
                        .frame(width: 36, height: 36)
                }
                .help(loc.t("about_website"))
            }
            .labelStyle(.iconOnly)
            .font(theme.appFont(size: 18, weight: .medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(ThemeManager.accent)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(width: 380)
        .background(ThemeManager.background)
    }
}

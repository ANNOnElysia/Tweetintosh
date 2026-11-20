import Foundation

extension Tweet {
    var sharingLink: String {
        let host = ThemeManager.shared.useFixupXLinks ? "fixupx.com" : "x.com"
        return "https://\(host)/\(author.screenName)/status/\(id)"
    }
}

//
//  SidebarChrome.swift
//  Tweetintosh
//
//  The geometry and timing shared by the sidebar, the top capsule and the page beside them.
//

import SwiftUI

// One timing for the sidebar, the top capsule and the page beside them, so the shapes and the layout move together.
// Apple Music on iPad settles both in about a quarter of a second with a spring, not a long ease: the droplet has
// travelled and the new row is highlighted before a 0.45 s curve would still be halfway there.
// Shared with NavigationManager, whose keyboard shortcut and automatic expansion toggle the same state.
enum SidebarMotion {
    static let toggle = Animation.spring(response: 0.28, dampingFraction: 0.90)
    // The selected tab's glass capsule on its own, which has less distance to cover than the sidebar.
    static let selection = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let content = Animation.spring(response: 0.24, dampingFraction: 0.88)
}

// The floating sidebar's column. The leading margin is wider than the window-edge margins so the system glass shadow
// has room on the left; the width shrinks by the same amount, keeping the right edge where it was so the timeline does
// not move. The trailing and bottom margins give the shadow room before it is cut off by the page and the window edge.
enum SidebarLayout {
    static let width: CGFloat = 208
    static let leadingMargin: CGFloat = 20
    static let trailingMargin: CGFloat = 32
    static let bottomMargin: CGFloat = 32
    static let columnWidth = leadingMargin + width + trailingMargin
}

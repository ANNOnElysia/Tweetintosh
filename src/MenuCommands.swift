//
//  MenuCommands.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The menu bar's commands beyond the app, edit and window basics: the accounts, New Post, the feeds, the size of post
//  text, going back, the Post menu that acts on the post open in front, and Help. The menu bar is where a Mac app shows what it can do and which keys do it,
//  so every command the app answers to by keyboard is listed here too.
//

import AppKit
import Combine

extension AppDelegate {
    // MARK: Building

    // File: a new post, then the commands for the post open in front
    func addFileCommands(to menu: NSMenu) {
        let loc = LocalizationManager.shared
        let newPost = NSMenuItem(title: loc.t("new_post"), action: #selector(menuNewPost), keyEquivalent: "n")
        newPost.target = self
        menu.insertItem(newPost, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)
    }

    // View: the three Home feeds, ticked when showing, under the existing ⌥Q / ⌥W / ⌥E
    func addFeedCommands(to menu: NSMenu, at index: Int) {
        let loc = LocalizationManager.shared
        let feeds: [(HomeFeedType, String, String)] = [
            (.forYou, "feed_for_you", "q"), (.following, "feed_following", "w"), (.bookmarks, "feed_bookmarks", "e")
        ]
        var position = index
        for (feed, key, letter) in feeds {
            let item = NSMenuItem(title: loc.t(key), action: #selector(menuSelectFeed(_:)), keyEquivalent: letter)
            item.keyEquivalentModifierMask = .option
            item.representedObject = feed.rawValue
            item.target = self
            menu.insertItem(item, at: position)
            position += 1
        }
        menu.insertItem(NSMenuItem.separator(), at: position)
    }

    // Tweetintosh: the signed-in accounts, ticked when active, on ⌃⌘1, ⌃⌘2… in order, then Add Account…. Rebuilt in
    // place whenever an account is added, removed or switched to.
    func addAccountCommands(to menu: NSMenu, at index: Int) {
        let placeholder = NSMenuItem.separator()
        placeholder.tag = Self.accountItemTag
        menu.insertItem(placeholder, at: index)
        let accounts = AccountManager.shared
        accountMenuObserver = accounts.$accounts.combineLatest(accounts.$activeId)
            // @Published announces a change before storing it, so read the accounts on the next turn
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak menu] _ in
                guard let self, let menu else { return }
                self.fillAccountCommands(in: menu)
            }
    }

    private static let accountItemTag = 7_302

    private func fillAccountCommands(in menu: NSMenu) {
        guard let start = menu.items.firstIndex(where: { $0.tag == Self.accountItemTag }) else { return }
        for item in menu.items.filter({ $0.tag == Self.accountItemTag }) { menu.removeItem(item) }
        let loc = LocalizationManager.shared
        var items: [NSMenuItem] = []
        for (number, account) in AccountManager.shared.accounts.enumerated() {
            let title = account.name.isEmpty ? "@\(account.screenName)" : "\(account.name) (@\(account.screenName))"
            let key = number < 9 ? String(number + 1) : ""
            let item = NSMenuItem(title: title, action: #selector(menuSwitchAccount(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.control, .command]
            item.representedObject = account.id
            items.append(item)
        }
        items.append(NSMenuItem(title: loc.t("menu_add_account"), action: #selector(menuAddAccount), keyEquivalent: ""))
        items.append(NSMenuItem.separator())
        for (offset, item) in items.enumerated() {
            item.tag = Self.accountItemTag
            item.target = self
            menu.insertItem(item, at: start + offset)
        }
    }

    // View: the size of post text, as in Safari and Mail. ⌘= reaches Bigger too, as it does there: on most
    // keyboards + is Shift-=.
    func addTextSizeCommands(to menu: NSMenu) {
        let loc = LocalizationManager.shared
        menu.addItem(NSMenuItem.separator())
        menu.addItem(command(loc.t("menu_text_bigger"), #selector(menuTextBigger), "+"))
        let equals = command(loc.t("menu_text_bigger"), #selector(menuTextBigger), "=")
        equals.isHidden = true
        equals.allowsKeyEquivalentWhenHidden = true
        menu.addItem(equals)
        menu.addItem(command(loc.t("menu_text_smaller"), #selector(menuTextSmaller), "-"))
        menu.addItem(command(loc.t("menu_text_actual_size"), #selector(menuTextActualSize), "0"))
    }

    // Tweetintosh: Check for Updates…, under About as in other Mac apps
    func addUpdateCommand(to menu: NSMenu) {
        let item = command(LocalizationManager.shared.t("menu_check_updates"), #selector(menuCheckForUpdates), "")
        // A build without a signing key can't verify an update, so it doesn't offer to look for one
        item.isHidden = !UpdateManager.shared.isAvailable
        menu.addItem(item)
    }

    // View: hide or show the pane beside Home, after the sidebar's own command
    func addPaneCommand(to menu: NSMenu) {
        let item = NSMenuItem(title: LocalizationManager.shared.t("menu_hide_pane"),
                              action: #selector(menuToggleDetailPane), keyEquivalent: "i")
        item.keyEquivalentModifierMask = [.command, .option]
        item.target = self
        menu.addItem(item)
    }

    // Navigate: back out of a page, your own profile, and the top of the timeline
    func addNavigationCommands(to menu: NSMenu) {
        let loc = LocalizationManager.shared
        menu.addItem(NSMenuItem.separator())
        let back = NSMenuItem(title: loc.t("menu_back"), action: #selector(menuGoBack), keyEquivalent: "[")
        back.target = self
        menu.addItem(back)
        let profile = NSMenuItem(title: loc.t("menu_my_profile"), action: #selector(menuOpenOwnProfile), keyEquivalent: "")
        profile.target = self
        menu.addItem(profile)
        // No ⌘↑: in a text field that moves the cursor to the start, and a menu would take it first
        let top = NSMenuItem(title: loc.t("menu_scroll_to_top"), action: #selector(menuScrollToTop), keyEquivalent: "")
        top.target = self
        menu.addItem(top)
    }

    // Post: what can be done to the post open in front. Titles say what a click would do now (Like or Unlike), and
    // the menu is dimmed when no post is open.
    func makePostMenu() -> NSMenuItem {
        let loc = LocalizationManager.shared
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: loc.t("menu_post"))
        // ⌘R already reloads the timeline, so Reply takes Shift
        menu.addItem(command(loc.t("reply"), #selector(menuReply), "R"))
        menu.addItem(command(loc.t("quote_tweet"), #selector(menuQuote), ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(command(loc.t("like"), #selector(menuLike), "l"))
        menu.addItem(command(loc.t("retweet"), #selector(menuRepost), ""))
        menu.addItem(command(loc.t("bookmark"), #selector(menuBookmark), "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(command(loc.t("copy_link"), #selector(menuCopyLink), "C"))
        menu.addItem(command(loc.t("open_in_browser"), #selector(menuOpenInBrowser), ""))
        menu.addItem(NSMenuItem.separator())
        // Dimmed unless the post is your own
        menu.addItem(command(loc.t("post_menu_delete"), #selector(menuDeletePost), ""))
        menuItem.submenu = menu
        return menuItem
    }

    // Help: macOS adds its search field, which finds any menu command by name
    func makeHelpMenu() -> NSMenuItem {
        let loc = LocalizationManager.shared
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: loc.t("menu_help"))
        menu.addItem(command(loc.t("menu_report_problem"), #selector(menuReportProblem), ""))
        menuItem.submenu = menu
        NSApp.helpMenu = menu
        return menuItem
    }

    private func command(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: The Post Open in Front

    // The post on the page in front, or in the pane beside Home, as it is now: the copy kept with the page can be
    // older than a like made on the page, and toggling from it would undo that like
    var focusedPost: Tweet? {
        let nav = NavigationManager.shared
        guard !nav.isShowingCompose, !nav.isReplyComposerOpen else { return nil }
        let opened: Tweet?
        if let entry = nav.overlayStack.last {
            guard case .tweet(let tweet) = entry.page else { return nil }
            opened = tweet
        } else if nav.currentTab == .home, DetailPane.shared.isOpen {
            opened = DetailPane.shared.stack.last?.tweet
        } else {
            opened = nil
        }
        guard let post = opened else { return nil }
        return TweetMutationHub.shared.copy(of: post.id) ?? post
    }

    // MARK: Actions

    @objc func menuCheckForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc func menuSwitchAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        switchAccount(to: id)
    }

    @objc func menuAddAccount() {
        startLoginFlow()
    }

    @objc func menuTextBigger() {
        let theme = ThemeManager.shared
        theme.postTextStep = min(theme.postTextStep + 1, ThemeManager.postTextScales.count - 1)
    }

    @objc func menuTextSmaller() {
        let theme = ThemeManager.shared
        theme.postTextStep = max(theme.postTextStep - 1, 0)
    }

    @objc func menuTextActualSize() {
        ThemeManager.shared.postTextStep = ThemeManager.actualPostTextStep
    }

    @objc func menuNewPost() {
        NavigationManager.shared.openComposer()
    }

    @objc func menuSelectFeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let feed = HomeFeedType(rawValue: raw) else { return }
        NavigationManager.shared.showTab(.home)
        TimelineViewModel.shared.selectFeed(feed)
    }

    @objc func menuToggleDetailPane() {
        NavigationManager.shared.toggleDetailPane()
    }

    @objc func menuGoBack() {
        let nav = NavigationManager.shared
        if nav.hasOverlay {
            nav.dismissTweetDetail()
        } else if nav.currentTab == .home && DetailPane.shared.isOpen {
            DetailPane.shared.goBack()
        }
    }

    @objc func menuOpenOwnProfile() {
        guard let account = AccountManager.shared.active else { return }
        NavigationManager.shared.openProfile(TweetUser(id: account.id, name: account.name, screenName: account.screenName,
                                                       avatarUrl: account.avatarUrl, isVerified: false))
    }

    @objc func menuScrollToTop() {
        TimelineScrollCoordinator.shared.scrollToTop()
    }

    @objc func menuReply() {
        guard let post = focusedPost else { return }
        NavigationManager.shared.openReply(to: post)
    }

    @objc func menuQuote() {
        guard let post = focusedPost else { return }
        NavigationManager.shared.openComposer(quoting: post)
    }

    @objc func menuLike() {
        guard let post = focusedPost else { return }
        TweetActions().like(post)
    }

    @objc func menuRepost() {
        guard let post = focusedPost else { return }
        TweetActions().repost(post)
    }

    @objc func menuBookmark() {
        guard let post = focusedPost else { return }
        TweetActions().bookmark(post)
    }

    @objc func menuCopyLink() {
        guard let post = focusedPost else { return }
        TweetActions().share(post)
    }

    @objc func menuOpenInBrowser() {
        guard let post = focusedPost,
              let url = URL(string: "https://x.com/\(post.author.screenName)/status/\(post.id)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func menuDeletePost() {
        guard let post = focusedPost, PostDeletion.isOwn(post) else { return }
        PostDeletion.confirm(post, copyingText: false)
    }

    @objc func menuReportProblem() {
        if let url = URL(string: "https://github.com/ANNOnElysia/Tweetintosh/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Validation

    // Answers for the items above; nil for any other item
    func validateCommand(_ item: NSMenuItem) -> Bool? {
        let loc = LocalizationManager.shared
        let nav = NavigationManager.shared
        switch item.action {
        case #selector(menuCheckForUpdates):
            // Dimmed while a check is already under way
            return UpdateManager.shared.canCheckForUpdates
        case #selector(menuSwitchAccount(_:)):
            item.state = (item.representedObject as? String) == AccountManager.shared.activeId ? .on : .off
            return loginController == nil
        case #selector(menuAddAccount):
            return loginController == nil
        case #selector(menuTextBigger):
            return ThemeManager.shared.postTextStep < ThemeManager.postTextScales.count - 1
        case #selector(menuTextSmaller):
            return ThemeManager.shared.postTextStep > 0
        case #selector(menuTextActualSize):
            return ThemeManager.shared.postTextStep != ThemeManager.actualPostTextStep
        case #selector(menuNewPost):
            return !nav.isShowingCompose && !nav.isReplyComposerOpen
        case #selector(menuSelectFeed(_:)):
            let feed = (item.representedObject as? String).flatMap(HomeFeedType.init(rawValue:))
            item.state = nav.currentTab == .home && TimelineViewModel.shared.selectedFeed == feed ? .on : .off
            return true
        case #selector(menuToggleDetailPane):
            let pane = DetailPane.shared
            item.title = loc.t(pane.isCollapsed ? "menu_show_pane" : "menu_hide_pane")
            return pane.fitsWindow && nav.currentTab == .home
        case #selector(menuGoBack):
            return nav.hasOverlay || (nav.currentTab == .home && DetailPane.shared.isOpen)
        case #selector(menuOpenOwnProfile):
            return AccountManager.shared.active != nil
        case #selector(menuScrollToTop):
            return nav.currentTab == .home && !nav.hasOverlay
        case #selector(menuLike):
            let post = focusedPost
            item.title = loc.t(post?.isFavorited == true ? "unlike" : "like")
            return post != nil
        case #selector(menuRepost):
            let post = focusedPost
            item.title = loc.t(post?.isRetweeted == true ? "undo_retweet" : "retweet")
            return post != nil
        case #selector(menuBookmark):
            let post = focusedPost
            item.title = loc.t(post?.isBookmarked == true ? "remove_bookmark" : "bookmark")
            return post != nil
        case #selector(menuReply), #selector(menuQuote), #selector(menuCopyLink), #selector(menuOpenInBrowser):
            return focusedPost != nil
        case #selector(menuDeletePost):
            return focusedPost.map(PostDeletion.isOwn) ?? false
        case #selector(menuReportProblem):
            return true
        default:
            return nil
        }
    }
}

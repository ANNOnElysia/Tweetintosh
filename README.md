# Tweetintosh

A native macOS client for X (Twitter), built with SwiftUI and AppKit.

Instead of running an embedded browser, Tweetintosh renders timelines, threads, and media through native Cocoa views and communicates directly with endpoints in Swift.

[English](#english) · [中文说明](#chinese) · [Build](#build)

---

<div id="english"></div>

## Overview

Tweetintosh focuses on utility, keyboard navigation, and desktop ergonomics that web wrappers cannot deliver.

### User Experience

- **Force Touch Peek Previews**: Deep press on a trackpad (or three-finger tap) to preview images, videos, external links, and user profiles in place without losing your scroll position. External link previews stay open for browsing until you press Esc.
- **Force Touch Repost**: Deep-press a post's repost button to repost or undo a repost immediately. A normal click still opens the repost and quote menu.
- **Native Article Reader**: Reads long-form X Articles in a distraction-free native reader view (formatted text, headings, code blocks, and media) instead of redirecting to browser tabs.
- **Dual-Pane Navigation**: Takes advantage of wide displays by pairing your timeline alongside selected posts, threads, and quote tweets.
- **Adaptive Sidebar**: The toggle follows an eased curve between the top bar and sidebar, carrying their shared glass surface with it. Respects the system Reduce Motion setting.
- **Translucent Settings Header**: Settings scroll beneath a fixed header that reaches the window’s top edge, with the same theme-aware fade as the notifications pane.
- **About Window**: A centered native window shows the app icon and version, with icon buttons to open the GitHub repository and website.
- **Inline Link Pointers**: URLs and @mentions show a pointing hand. Scrolling, resizing, and changing posts clear the previous text's hover state.
- **Stable Reading Position**: Background timeline polling never auto-scrolls or displaces the text you are reading. New items wait behind a top indicator until summoned.
- **Responsive Timeline**: The Home timeline prioritizes visible and nearby posts when measuring rows, and prepares media in the background. With the detail pane hidden, scrolling either blank margin also scrolls the timeline, with or without the sidebar.
- **Comment Media Preloading**: Post pages prepare comment avatars and media in the background and insert each new page of replies together. Scrolling uses the native speed without an added multiplier.
- **Compact Post Actions**: Narrow panes tighten action spacing before compressing counts, keeping reply, repost, like, and view counts on one line.
- **Soft Refresh Edges**: Home and Notifications smoothly open and close space above the first row while refreshing. Refreshed content on Home, Notifications, profiles and post pages appears without waiting for the indicator animation to finish.
- **Click Again to Refresh**: Click the selected Home or Notifications button in the top bar or sidebar to glide quickly to the top, then refresh its current feed. Respects Reduce Motion.
- **Multi-Account Switching**: Save multiple profiles and switch between them without re-authenticating.
- **Instant Launch & Offline Cache**: Recent timelines are stored locally so you can read previously loaded posts immediately upon launch, even in poor connectivity or airplane mode.
- **Transient Authentication**: WebKit is loaded only once on first run to capture your session cookies, then immediately released from memory.

---

<div id="chinese"></div>

## 概述

Tweetintosh 专注于桌面端的使用效率、快捷键导航以及原生系统集成，提供网页套壳应用无法具备的操作体验。

### 体验改进

- **触控板 Force Touch 快速预览**：在推文、图片、视频、用户头像或外链上用力重按（或三指轻点），即可就地浮现预览卡片，不打断浏览节奏。外链预览松开后仍可浏览，按 Esc 关闭。
- **重按快速转推**：重按推文的转推按钮即可直接转推或撤销转推，普通点击仍显示转推与引用菜单。
- **长文原生阅读模式**：在应用内直接排版阅读 X 的长文章（Articles），原生渲染标题、引用、代码块与图文，无需跳转浏览器。
- **桌面双栏浏览**：在大屏幕上左侧保留时间线上下文，右侧展开阅读当前讨论串与引用，减少来回前进后退。
- **自适应侧栏**：切换按钮沿缓入缓出的弧线在顶栏与侧栏之间移动，带动玻璃框变形，并遵循系统“减少动态效果”设置。
- **半透明设置顶栏**：设置内容从覆盖窗口上缘的固定顶栏下方滚过，使用与通知栏相同、随主题变化的渐隐背景。
- **关于窗口**：居中展示应用图标与版本，通过图标按钮在浏览器中打开 GitHub 仓库及官网。
- **正文链接光标**：URL 与 @提及显示手形光标；滚动、调整窗口大小或切换帖子时清除旧正文的悬浮状态。
- **阅读位置保护**：后台检测到新推文时仅在顶部显示更新计数，绝不会自动将时间线强制置顶移位。
- **流畅浏览时间线**：主页优先测量屏幕内及附近的推文，并在后台准备媒体内容。详情栏隐藏时，无论是否展开左侧栏，在时间线两侧留白处滚动也能滚动时间线。
- **评论媒体预加载**：详情页在后台提前缓存评论头像和媒体，每页评论一次性加入列表；滚动保持原生速度，不叠加倍率。
- **紧凑推文操作栏**：窄栏优先缩小按钮及图标与数字间距，再适度压缩计数文字，回复、转推、点赞及浏览数保持单行。
- **柔和刷新边缘**：主页与通知页在刷新时平滑展开、收起首行上方的空白区域。主页、通知、个人页与帖子详情的刷新结果不再等待指示器动画结束才显示。
- **再次点击刷新**：再次点击顶栏或侧栏中已选中的主页、通知按钮，先快速平滑返回页首，再刷新当前信息流，并遵循系统“减少动态效果”设置。
- **多账号快速切换**：支持保存多个 X 账号，随时一键切换身份。
- **即时启动与离线缓存**：推文快照持久化保存在本地，断网或飞行模式下打开即可浏览既有内容，网络连通时静默更新。
- **瞬态登录认证**：仅在初次登录时启动一次临时网页组件读取 Cookie 凭证，提取完毕后立即销毁该实例，日常运行不驻留网页运行时。

---

<div id="build"></div>

## Build & Run / 编译运行

### Requirements / 环境要求
- macOS 15.0 or later
- Swift command-line tools

### Build
```bash
git clone https://github.com/ANNOnElysia/Tweetintosh.git
cd Tweetintosh
./build.sh
open Tweetintosh.app
```

---

## Disclaimer / 免责声明

Tweetintosh is an independent, unofficial project. It is not affiliated with, endorsed by, or associated with X Corp. or Apple Inc.

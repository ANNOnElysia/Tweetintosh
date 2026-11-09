# Tweetintosh

A native macOS client for X (Twitter), built with SwiftUI and AppKit.

Instead of running an embedded browser, Tweetintosh renders timelines, threads, and media through native Cocoa views and communicates directly with endpoints in Swift.

[English](#english) · [中文说明](#chinese) · [Build](#build)

---

<div id="english"></div>

## Overview

Tweetintosh focuses on utility, keyboard navigation, and desktop ergonomics that web wrappers cannot deliver.

### User Experience

- **Force Touch Peek Previews**: Deep press on a trackpad (or three-finger tap) to preview images, videos, external links, and user profiles in place without losing your scroll position.
- **Native Article Reader**: Reads long-form X Articles in a distraction-free native reader view (formatted text, headings, code blocks, and media) instead of redirecting to browser tabs.
- **Dual-Pane Navigation**: Takes advantage of wide displays by pairing your timeline alongside selected posts, threads, and quote tweets.
- **Adaptive Sidebar**: The toggle follows an eased curve between the top bar and sidebar, carrying their shared glass surface with it. Respects the system Reduce Motion setting.
- **Translucent Settings Header**: Settings scroll beneath a fixed header that reaches the window’s top edge, with the same theme-aware fade as the notifications pane.
- **Stable Reading Position**: Background timeline polling never auto-scrolls or displaces the text you are reading. New items wait behind a top indicator until summoned.
- **Responsive Timeline**: The Home timeline prioritizes visible and nearby posts when measuring rows, and prepares media in the background. With the detail pane hidden, scrolling either blank margin also scrolls the timeline, with or without the sidebar.
- **Multi-Account Switching**: Save multiple profiles and switch between them without re-authenticating.
- **Instant Launch & Offline Cache**: Recent timelines are stored locally so you can read previously loaded posts immediately upon launch, even in poor connectivity or airplane mode.
- **Transient Authentication**: WebKit is loaded only once on first run to capture your session cookies, then immediately released from memory.

---

<div id="chinese"></div>

## 概述

Tweetintosh 专注于桌面端的使用效率、快捷键导航以及原生系统集成，提供网页套壳应用无法具备的操作体验。

### 体验改进

- **触控板 Force Touch 快速预览**：在推文、图片、视频、用户头像或外链上用力重按（或三指轻点），即可就地浮现预览卡片，松开即走，不打断浏览节奏。
- **长文原生阅读模式**：在应用内直接排版阅读 X 的长文章（Articles），原生渲染标题、引用、代码块与图文，无需跳转浏览器。
- **桌面双栏浏览**：在大屏幕上左侧保留时间线上下文，右侧展开阅读当前讨论串与引用，减少来回前进后退。
- **自适应侧栏**：切换按钮沿缓入缓出的弧线在顶栏与侧栏之间移动，带动玻璃框变形，并遵循系统“减少动态效果”设置。
- **半透明设置顶栏**：设置内容从覆盖窗口上缘的固定顶栏下方滚过，使用与通知栏相同、随主题变化的渐隐背景。
- **阅读位置保护**：后台检测到新推文时仅在顶部显示更新计数，绝不会自动将时间线强制置顶移位。
- **流畅浏览时间线**：主页优先测量屏幕内及附近的推文，并在后台准备媒体内容。详情栏隐藏时，无论是否展开左侧栏，在时间线两侧留白处滚动也能滚动时间线。
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

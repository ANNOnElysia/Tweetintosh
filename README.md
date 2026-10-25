# Tweetintosh v2 (Headless Data-driven Native macOS Client for X)

> 彻底废弃 WebView 直接渲染主界面的套壳方案，重构为 **“Headless 凭证捕获 + 内部 GraphQL API 同步 + SwiftUI 纯原生渲染”** 的真·原生 macOS 客户端。

---

## 🚀 核心架构与技术实现

### 1. 登录与身份凭证接管（Headless / 仅首次可见）
- **按需唤起**：若本地未找到有效凭证，唤起轻量登录窗口供用户扫码或输入密码。
- **CookieStore 监听**：通过 `WKHTTPCookieStoreObserver` 实时监听并提取 `auth_token` 与 `ct0`（CSRF Token）。
- **即时销毁**：凭证提取成功并持久化写入 Application Support 后，**即刻关闭并彻底释放销毁该 WebView 实例**，主程序不再驻留任何网页运行时，内存占用压至 **< 100MB**。
- **系统会话无感接管**：优先读取本地已有 WebKit 会话，若用户此前已登录则直接秒进，免除重复输入。

### 2. 内部私有 GraphQL API 逆向与链路模拟
- **模拟请求链路**：
  - 携带公开 Bearer Token：`Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA`
  - 动态注入 Headers：`x-csrf-token`、`cookie`、`x-twitter-active-user: yes`、`x-twitter-client-language: en`、Safari 桌面端 UA 等。
  - 请求端点对接：`HomeTimeline` GraphQL URT 协议。
- **分页与 Cursor**：
  - 自动提取 `cursor-top-...` 与 `cursor-bottom-...` 分页游标。

### 3. 创新交互：“View N posts” 浮动小胶囊
- **增量静默轮询**：后台定时检测新推文，检测到更新时不粗暴顶飞用户当前阅读位置。
- **原生悬浮胶囊**：在顶部呈现半透明微光胶囊（如 `↑ 35 new posts` / `↑ 35 条新推文`）。
- **弹性弹簧插入**：用户点击胶囊时，采用 `.animation(.spring(), value: ...)` 平滑将新数据注入列表头部。
- **触底无限滚动**：滑至底部通过 `cursor-bottom` 自动增量加载早前推文。

### 4. 0ms 本地秒开持久化缓存（TimelineCacheManager）
- 本地构建扁平 JSON 缓存，记录最近一批高质量推文快照。
- App 启动瞬间优先秒级呈现缓存内容，后台无感刷新增量，彻底消灭白屏与加载等待。

### 5. 高性能 120Hz 现代微动效（无系统灰菊花）
- **骨架屏扫光**：基于 `SwiftUI.TimelineView` 的 120Hz 高刷新率骨架屏（`shimmering`），推文占位高帧率流畅平滑。
- **极细弧光加载器**：放弃系统陈旧旋转灰菊花，采用 1.5px 纯矢量极细环形生长弧光（`GrowingArcIndicator`）与脉冲微波。

### 6. 多语言与排版热切换（Cmd + , Settings）
- **默认语言**：英语（English）。
- **支持 5 种界面语言动态切换**：
  - English
  - 日本語 (Japanese)
  - 한국어 (Korean)
  - 简体中文 (Simplified Chinese)
  - 繁體中文 (Traditional Chinese)
- **排版解耦**：
  - 支持 macOS 系统默认字体。
  - 支持日文明朝体（`Hiragino Mincho ProN`），行距与字间距自动优化为大屏杂志沉浸质感。
- **多图原生网格**：自适应呈现 1 张高清大图、2 栏并排、3 图拼图、4 格对称网格，支持内存/磁盘双重异步缓存。

---

## 📁 目录与工程结构

```
~/Documents/Antigravity/Tweetintosh/
├── Tweetintosh.app/                       # 可直接双击运行的独立原生 macOS 应用包
│   └── Contents/
│       ├── Info.plist             # 应用配置清单
│       ├── MacOS/Tweetintosh              # 纯 Swift 编译的原生二进制（~839 KB）
│       └── Resources/             # AppIcon 等打包资源
├── Package.swift                  # Swift Package Manager 工程规范文件
├── build.sh                       # 自动化 Release 编译、打包与 Ad-hoc 签名脚本
├── README.md                      # 技术说明与设计规范
└── src/                           # 纯原生 Swift 源代码
    ├── main.swift                 # AppKit 宿主窗口、菜单与生命周期入口
    ├── TimelineView.swift         # MainTimelineView 主界面、浮动胶囊与下拉刷新
    ├── TimelineViewModel.swift    # 状态控制器（增量轮询、分页、待推入队列）
    ├── TweetRowView.swift         # 推文行卡片、转推/蓝标/排版/互动栏
    ├── ImageGridView.swift        # 1-4 张配图网格与异步内存/磁盘图片加载器
    ├── ActivityIndicators.swift   # 120Hz GrowingArc 极细生长弧光加载微动效
    ├── ShimmerView.swift          # 120Hz TimelineView 骨架屏微光扫光
    ├── APIClient.swift            # 内部私有 GraphQL 协议请求与 JSON 解析层
    ├── Models.swift               # Tweet、User、Media、Cursor Codable 数据模型
    ├── AuthCredentials.swift      # 凭证加密持久化与系统会话检测
    ├── LoginWindowController.swift# Headless 首次登录浮窗与即时销毁控制器
    ├── Localization.swift         # 英/日/韩/简中/繁中 五国语言实时切换引擎
    ├── ThemeManager.swift         # 排版字族与 OLED 配色系统
    └── TimelineCacheManager.swift # 扁平本地推文持久化缓存
```

---

## ⌨️ 原生快捷键

- `Cmd + ,`：偏好设置（多语言切换、日文明朝体排版、清空缓存、退出登录）
- `Cmd + W`：关闭当前窗口
- `Cmd + Q`：退出程序
- `Cmd + Control + F`：进入/退出全屏
- `Cmd + Z` / `Cmd + Shift + Z`：撤销 / 重做
- `Cmd + X` / `Cmd + C` / `Cmd + V` / `Cmd + A`：标准剪贴板文本操作

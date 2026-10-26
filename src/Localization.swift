//
//  Localization.swift
//  Tweetintosh - Headless Data-driven Client
//

import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "Tweetintosh_AppLanguage")
        }
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "Tweetintosh_AppLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            // Intelligent System Locale Detection
            let matched = Locale.preferredLanguages.compactMap { pref -> AppLanguage? in
                if pref.hasPrefix("zh-Hans") || pref.hasPrefix("zh-CN") { return .simplifiedChinese }
                if pref.hasPrefix("zh-Hant") || pref.hasPrefix("zh-TW") || pref.hasPrefix("zh-HK") { return .traditionalChinese }
                if pref.hasPrefix("ja") { return .japanese }
                if pref.hasPrefix("ko") { return .korean }
                return nil
            }.first
            self.currentLanguage = matched ?? .simplifiedChinese
        }
    }
    
    // Translation dictionary, built once: t() is called many times per tweet row as rows scroll in, and
    // rebuilding this table on every call was a measurable per-row cost
    private static let table: [String: [AppLanguage: String]] = [
        "app_title": [
            .english: "Tweetintosh",
            .japanese: "Tweetintosh",
            .korean: "Tweetintosh",
            .simplifiedChinese: "Tweetintosh",
            .traditionalChinese: "Tweetintosh"
        ],
        "timeline": [
            .english: "Timeline",
            .japanese: "タイムライン",
            .korean: "타임라인",
            .simplifiedChinese: "时间线",
            .traditionalChinese: "時間線"
        ],
        "tab_home": [
            .english: "Home",
            .japanese: "ホーム",
            .korean: "홈",
            .simplifiedChinese: "主页",
            .traditionalChinese: "主頁"
        ],
        "tab_notifications": [
            .english: "Notifications",
            .japanese: "通知",
            .korean: "알림",
            .simplifiedChinese: "通知",
            .traditionalChinese: "通知"
        ],
        "tab_messages": [
            .english: "Messages",
            .japanese: "メッセージ",
            .korean: "쪽지",
            .simplifiedChinese: "私信",
            .traditionalChinese: "私訊"
        ],
        "tab_search": [
            .english: "Search",
            .japanese: "検索",
            .korean: "검색",
            .simplifiedChinese: "搜索",
            .traditionalChinese: "搜尋"
        ],
        "notif_filter_all": [
            .english: "All",
            .japanese: "すべて",
            .korean: "전체",
            .simplifiedChinese: "全部",
            .traditionalChinese: "全部"
        ],
        "notif_filter_likes_reposts": [
            .english: "Likes & Reposts",
            .japanese: "いいねとリポスト",
            .korean: "좋아요 및 재게시",
            .simplifiedChinese: "赞与转推",
            .traditionalChinese: "讚與轉推"
        ],
        "notif_filter_comments": [
            .english: "Comments",
            .japanese: "返信・コメント",
            .korean: "답글",
            .simplifiedChinese: "评论",
            .traditionalChinese: "留言"
        ],
        "notif_filter_mentions": [
            .english: "Mentions",
            .japanese: "メンション",
            .korean: "멘션",
            .simplifiedChinese: "提及",
            .traditionalChinese: "提及"
        ],
        "empty_notifications": [
            .english: "No notifications in this filter",
            .japanese: "このフィルターの通知はありません",
            .korean: "이 필터의 알림이 없습니다",
            .simplifiedChinese: "该筛选下暂无新通知",
            .traditionalChinese: "該篩選下暫無新通知"
        ],
        "search_placeholder": [
            .english: "Search…",
            .japanese: "検索…",
            .korean: "검색…",
            .simplifiedChinese: "搜索…",
            .traditionalChinese: "搜尋…"
        ],
        "new_posts_capsule": [
            .english: "↑ %@ new posts",
            .japanese: "↑ %@ 件の新しいポスト",
            .korean: "↑ 새 포스트 %@개",
            .simplifiedChinese: "↑ %@ 条新推文",
            .traditionalChinese: "↑ %@ 則新推文"
        ],
        "refreshing": [
            .english: "Updating timeline…",
            .japanese: "タイムラインを更新中…",
            .korean: "타임라인 업데이트 중…",
            .simplifiedChinese: "正在更新时间线…",
            .traditionalChinese: "正在更新時間線…"
        ],
        "pull_to_refresh": [
            .english: "Pull down to refresh",
            .japanese: "下に引いて更新",
            .korean: "당겨서 새로고침",
            .simplifiedChinese: "下拉即可刷新",
            .traditionalChinese: "下拉即可重新整理"
        ],
        "release_to_refresh": [
            .english: "Release to refresh",
            .japanese: "離して更新",
            .korean: "놓아서 새로고침",
            .simplifiedChinese: "释放立即刷新",
            .traditionalChinese: "釋放立即重新整理"
        ],
        "timeline_up_to_date": [
            .english: "Timeline is up to date",
            .japanese: "最新のポストです",
            .korean: "최신 상태입니다",
            .simplifiedChinese: "已是最新推文",
            .traditionalChinese: "已是最新推文"
        ],
        "loading_more": [
            .english: "Loading earlier posts…",
            .japanese: "過去のポストを読み込み中…",
            .korean: "이전 포스트 불러오는 중…",
            .simplifiedChinese: "加载更早推文…",
            .traditionalChinese: "載入更早推文…"
        ],
        "empty_timeline": [
            .english: "No posts found. Pull down to refresh.",
            .japanese: "ポストがありません。プルして更新してください。",
            .korean: "포스트가 없습니다. 당겨서 새로고침하세요.",
            .simplifiedChinese: "暂无推文，下拉以刷新。",
            .traditionalChinese: "暫無推文，下拉以重新整理。"
        ],
        "sign_in_required": [
            .english: "Authentication Required",
            .japanese: "ログインが必要です",
            .korean: "로그인이 필요합니다",
            .simplifiedChinese: "需要登录账户",
            .traditionalChinese: "需要登入帳號"
        ],
        "sign_in_button": [
            .english: "Sign in with X",
            .japanese: "X でログイン",
            .korean: "X 계정으로 로그인",
            .simplifiedChinese: "登录 X 账户",
            .traditionalChinese: "登入 X 帳號"
        ],
        "settings": [
            .english: "Settings",
            .japanese: "環境設定",
            .korean: "환경설정",
            .simplifiedChinese: "偏好设置",
            .traditionalChinese: "偏好設定"
        ],
        "language": [
            .english: "Interface Language",
            .japanese: "表示言語",
            .korean: "인터페이스 언어",
            .simplifiedChinese: "界面语言",
            .traditionalChinese: "介面語言"
        ],
        "typography": [
            .english: "Typography & Font",
            .japanese: "タイポグラフィとフォント",
            .korean: "타이포그래피 및 서체",
            .simplifiedChinese: "排版与字族",
            .traditionalChinese: "排版與字族"
        ],
        "font_system": [
            .english: "System",
            .japanese: "システム標準",
            .korean: "시스템 기본",
            .simplifiedChinese: "系统默认",
            .traditionalChinese: "系統預設"
        ],
        "font_mincho": [
            .english: "Hiragino Mincho",
            .japanese: "ヒラギノ明朝",
            .korean: "히라기노 명조",
            .simplifiedChinese: "日文明朝体",
            .traditionalChinese: "日文明朝體"
        ],
        "clear_cache": [
            .english: "Clear Local Cache",
            .japanese: "ローカルキャッシュを消去",
            .korean: "로컬 캐시 삭제",
            .simplifiedChinese: "清理本地推文缓存",
            .traditionalChinese: "清除本機推文快取"
        ],
        "accounts": [
            .english: "Accounts",
            .japanese: "アカウント",
            .korean: "계정",
            .simplifiedChinese: "账户",
            .traditionalChinese: "帳戶"
        ],
        "add_account": [
            .english: "Add account",
            .japanese: "アカウントを追加",
            .korean: "계정 추가",
            .simplifiedChinese: "添加账户",
            .traditionalChinese: "新增帳戶"
        ],
        "switch_account": [
            .english: "Switch to this account",
            .japanese: "このアカウントに切り替える",
            .korean: "이 계정으로 전환",
            .simplifiedChinese: "切换到此账户",
            .traditionalChinese: "切換到此帳戶"
        ],
        "account_signed_in": [
            .english: "Signed in",
            .japanese: "ログイン中",
            .korean: "로그인됨",
            .simplifiedChinese: "已登录",
            .traditionalChinese: "已登入"
        ],
        "attach_media": [
            .english: "Attach media",
            .japanese: "メディアを添付",
            .korean: "미디어 첨부",
            .simplifiedChinese: "添加媒体",
            .traditionalChinese: "新增媒體"
        ],
        "media_unsupported": [
            .english: "{name} isn't a supported format. Use JPG, PNG, GIF, WebP, MP4 or MOV.",
            .japanese: "{name} は対応していない形式です。JPG、PNG、GIF、WebP、MP4、MOV を使用してください。",
            .korean: "{name}은(는) 지원되지 않는 형식입니다. JPG, PNG, GIF, WebP, MP4, MOV를 사용하세요.",
            .simplifiedChinese: "{name} 不是支持的格式。请使用 JPG、PNG、GIF、WebP、MP4 或 MOV。",
            .traditionalChinese: "{name} 不是支援的格式。請使用 JPG、PNG、GIF、WebP、MP4 或 MOV。"
        ],
        "media_too_large": [
            .english: "{name} is too large (the limit is {limit}).",
            .japanese: "{name} は大きすぎます（上限 {limit}）。",
            .korean: "{name}이(가) 너무 큽니다(최대 {limit}).",
            .simplifiedChinese: "{name} 太大了（上限 {limit}）。",
            .traditionalChinese: "{name} 太大了（上限 {limit}）。"
        ],
        "media_too_many": [
            .english: "A post can have up to 4 photos.",
            .japanese: "1つのポストに添付できる写真は最大4枚です。",
            .korean: "게시물에는 사진을 최대 4장까지 첨부할 수 있습니다.",
            .simplifiedChinese: "一条帖子最多可添加 4 张照片。",
            .traditionalChinese: "一則貼文最多可新增 4 張照片。"
        ],
        "media_mixed": [
            .english: "A post can have up to 4 photos, or one GIF, or one video — not a mix.",
            .japanese: "1つのポストに添付できるのは、写真（最大4枚）、GIF 1つ、動画 1つのいずれかです。",
            .korean: "게시물에는 사진(최대 4장), GIF 1개, 동영상 1개 중 하나만 첨부할 수 있습니다.",
            .simplifiedChinese: "一条帖子可添加最多 4 张照片、1 个 GIF 或 1 个视频，不能混合。",
            .traditionalChinese: "一則貼文可新增最多 4 張照片、1 個 GIF 或 1 個影片，不能混合。"
        ],
        "media_unreadable": [
            .english: "Couldn't read {name}.",
            .japanese: "{name} を読み込めませんでした。",
            .korean: "{name}을(를) 읽을 수 없습니다.",
            .simplifiedChinese: "无法读取 {name}。",
            .traditionalChinese: "無法讀取 {name}。"
        ],
        "media_uploading": [
            .english: "Uploading media {current} of {total}…",
            .japanese: "メディアをアップロード中 {current}/{total}…",
            .korean: "미디어 업로드 중 {current}/{total}…",
            .simplifiedChinese: "正在上传媒体 {current}/{total}…",
            .traditionalChinese: "正在上傳媒體 {current}/{total}…"
        ],
        "sign_out": [
            .english: "Sign Out",
            .japanese: "ログアウト",
            .korean: "로그아웃",
            .simplifiedChinese: "退出登录",
            .traditionalChinese: "登出帳號"
        ],
        "reply": [
            .english: "Reply",
            .japanese: "返信",
            .korean: "답글",
            .simplifiedChinese: "回复",
            .traditionalChinese: "回覆"
        ],
        "retweet": [
            .english: "Repost",
            .japanese: "リポスト",
            .korean: "재게시",
            .simplifiedChinese: "转推",
            .traditionalChinese: "轉推"
        ],
        "undo_retweet": [
            .english: "Undo Repost",
            .japanese: "リポストを取り消す",
            .korean: "재게시 취소",
            .simplifiedChinese: "撤销转推",
            .traditionalChinese: "取消轉推"
        ],
        "quote_tweet": [
            .english: "Quote",
            .japanese: "引用",
            .korean: "인용",
            .simplifiedChinese: "引用推文",
            .traditionalChinese: "引用貼文"
        ],
        "new_post": [
            .english: "New Post",
            .japanese: "ポストする",
            .korean: "게시하기",
            .simplifiedChinese: "发推",
            .traditionalChinese: "發文"
        ],
        "post_action": [
            .english: "Post",
            .japanese: "ポスト",
            .korean: "게시",
            .simplifiedChinese: "发布",
            .traditionalChinese: "發布"
        ],
        "post_placeholder": [
            .english: "What is happening?!",
            .japanese: "いまどうしてる？",
            .korean: "무슨 일이 일어나고 있나요?",
            .simplifiedChinese: "有什么新鲜事？",
            .traditionalChinese: "發生了什麼事？"
        ],
        "quote_placeholder": [
            .english: "Add a comment...",
            .japanese: "コメントを追加...",
            .korean: "의견 추가하기...",
            .simplifiedChinese: "添加评论...",
            .traditionalChinese: "新增留言..."
        ],
        "like": [
            .english: "Like",
            .japanese: "いいね",
            .korean: "마음에 들어요",
            .simplifiedChinese: "喜欢",
            .traditionalChinese: "喜歡"
        ],
        "unlike": [
            .english: "Unlike",
            .japanese: "いいねを取り消す",
            .korean: "좋아요 취소",
            .simplifiedChinese: "取消喜欢",
            .traditionalChinese: "取消喜歡"
        ],
        "bookmark": [
            .english: "Bookmark",
            .japanese: "ブックマーク",
            .korean: "북마크",
            .simplifiedChinese: "添加书签",
            .traditionalChinese: "加入書籤"
        ],
        "bookmarked": [
            .english: "Bookmarked",
            .japanese: "ブックマーク済み",
            .korean: "북마크됨",
            .simplifiedChinese: "已加书签",
            .traditionalChinese: "已加書籤"
        ],
        "remove_bookmark": [
            .english: "Remove Bookmark",
            .japanese: "ブックマークを削除",
            .korean: "북마크 삭제",
            .simplifiedChinese: "移除书签",
            .traditionalChinese: "移除書籤"
        ],
        "replying_to": [
            .english: "Replying to {author}",
            .japanese: "{author}に返信中",
            .korean: "{author}님에게 답글 남기는 중",
            .simplifiedChinese: "回复给 {author}",
            .traditionalChinese: "回覆給 {author}"
        ],
        "reply_placeholder": [
            .english: "Post your reply...",
            .japanese: "返信をポスト...",
            .korean: "답글 게시하기...",
            .simplifiedChinese: "发布你的回复...",
            .traditionalChinese: "發布你的回覆..."
        ],
        "post_reply": [
            .english: "Reply",
            .japanese: "返信",
            .korean: "답글",
            .simplifiedChinese: "回复",
            .traditionalChinese: "回覆"
        ],
        "cancel": [
            .english: "Cancel",
            .japanese: "キャンセル",
            .korean: "취소",
            .simplifiedChinese: "取消",
            .traditionalChinese: "取消"
        ],
        "nav_post": [
            .english: "Post",
            .japanese: "ポスト",
            .korean: "게시물",
            .simplifiedChinese: "帖子",
            .traditionalChinese: "貼文"
        ],
        "nav_back": [
            .english: "Back",
            .japanese: "戻る",
            .korean: "뒤로",
            .simplifiedChinese: "返回",
            .traditionalChinese: "返回"
        ],
        "thread_replies": [
            .english: "Replies",
            .japanese: "返信",
            .korean: "답글",
            .simplifiedChinese: "回复",
            .traditionalChinese: "回覆"
        ],
        "no_replies_yet": [
            .english: "No replies yet. Be the first to reply!",
            .japanese: "返信はまだありません。最初の返信を投稿しましょう！",
            .korean: "아직 답글이 없습니다. 첫 번째 답글을 남겨보세요!",
            .simplifiedChinese: "暂无回复，发表第一条评论吧！",
            .traditionalChinese: "暫無回覆，發表第一則留言吧！"
        ],
        "copy_link": [
            .english: "Copy Link",
            .japanese: "リンクをコピー",
            .korean: "링크 복사",
            .simplifiedChinese: "复制链接",
            .traditionalChinese: "複製連結"
        ],
        "link_copied": [
            .english: "Link copied to clipboard",
            .japanese: "リンクをクリップボードにコピーしました",
            .korean: "링크가 클립보드에 복사되었습니다",
            .simplifiedChinese: "推文链接已复制到剪贴板",
            .traditionalChinese: "貼文連結已複製至剪貼簿"
        ],
        "views": [
            .english: "Views",
            .japanese: "件の表示",
            .korean: "회 조회",
            .simplifiedChinese: "次浏览",
            .traditionalChinese: "次瀏覽"
        ],
        "profile_tab_posts": [
            .english: "Posts",
            .japanese: "ポスト",
            .korean: "게시물",
            .simplifiedChinese: "帖子",
            .traditionalChinese: "貼文"
        ],
        "profile_tab_media": [
            .english: "Media",
            .japanese: "メディア",
            .korean: "미디어",
            .simplifiedChinese: "媒体",
            .traditionalChinese: "媒體"
        ],
        "profile_tab_replies": [
            .english: "Replies",
            .japanese: "返信",
            .korean: "답글",
            .simplifiedChinese: "回复",
            .traditionalChinese: "回覆"
        ],
        "profile_follow": [
            .english: "Follow",
            .japanese: "フォロー",
            .korean: "팔로우",
            .simplifiedChinese: "关注",
            .traditionalChinese: "跟隨"
        ],
        "profile_following_button": [
            .english: "Following",
            .japanese: "フォロー中",
            .korean: "팔로잉",
            .simplifiedChinese: "正在关注",
            .traditionalChinese: "跟隨中"
        ],
        "profile_unfollow": [
            .english: "Unfollow",
            .japanese: "フォロー解除",
            .korean: "언팔로우",
            .simplifiedChinese: "取消关注",
            .traditionalChinese: "取消跟隨"
        ],
        "profile_joined": [
            .english: "Joined {date}",
            .japanese: "{date}から利用しています",
            .korean: "가입일: {date}",
            .simplifiedChinese: "{date} 加入",
            .traditionalChinese: "{date} 加入"
        ],
        "profile_empty": [
            .english: "No posts yet",
            .japanese: "まだポストはありません",
            .korean: "아직 게시물이 없습니다",
            .simplifiedChinese: "还没有帖子",
            .traditionalChinese: "尚無貼文"
        ],
        "profile_load_failed": [
            .english: "Couldn't load these posts.",
            .japanese: "ポストを読み込めませんでした。",
            .korean: "게시물을 불러오지 못했습니다.",
            .simplifiedChinese: "无法加载这些帖子。",
            .traditionalChinese: "無法載入這些貼文。"
        ],
        "profile_retry": [
            .english: "Try again",
            .japanese: "再試行",
            .korean: "다시 시도",
            .simplifiedChinese: "重试",
            .traditionalChinese: "重試"
        ],
        "profile_protected": [
            .english: "These posts are protected",
            .japanese: "このアカウントのポストは非公開です",
            .korean: "비공개 게시물입니다",
            .simplifiedChinese: "这些帖子受保护",
            .traditionalChinese: "這些貼文受到保護"
        ],
        "engagement_blocked": [
            .english: "{name} has blocked you. You can't like, repost, bookmark, or reply to their posts.",
            .japanese: "{name}さんにブロックされています。このアカウントのポストにいいね、リポスト、ブックマーク、返信はできません。",
            .korean: "{name}님이 회원님을 차단했습니다. 이 계정의 게시물에는 좋아요, 리포스트, 북마크, 답글을 남길 수 없습니다.",
            .simplifiedChinese: "{name} 已屏蔽你，你无法对其帖子点赞、转发、收藏或回复。",
            .traditionalChinese: "{name} 已封鎖你，你無法對其貼文按讚、轉發、收藏或回覆。"
        ],
        "profile_blocked_follow": [
            .english: "{name} has blocked you. You can't follow this account.",
            .japanese: "{name}さんにブロックされているため、フォローできません。",
            .korean: "{name}님이 회원님을 차단해 팔로우할 수 없습니다.",
            .simplifiedChinese: "{name} 已屏蔽你，你无法关注此账号。",
            .traditionalChinese: "{name} 已封鎖你，你無法跟隨此帳號。"
        ],
        "engagement_blocked_generic": [
            .english: "This account has blocked you, so you can't do that.",
            .japanese: "このアカウントにブロックされているため、この操作はできません。",
            .korean: "이 계정에서 회원님을 차단해 이 작업을 할 수 없습니다.",
            .simplifiedChinese: "该账号已屏蔽你，你无法执行此操作。",
            .traditionalChinese: "該帳號已封鎖你，你無法執行此操作。"
        ],
        "search_tab_top": [
            .english: "Top",
            .japanese: "トップ",
            .korean: "인기",
            .simplifiedChinese: "热门",
            .traditionalChinese: "熱門"
        ],
        "search_tab_latest": [
            .english: "Latest",
            .japanese: "最新",
            .korean: "최신",
            .simplifiedChinese: "最新",
            .traditionalChinese: "最新"
        ],
        "search_tab_people": [
            .english: "People",
            .japanese: "ユーザー",
            .korean: "사용자",
            .simplifiedChinese: "用户",
            .traditionalChinese: "使用者"
        ],
        "search_no_results": [
            .english: "No results for “{query}”",
            .japanese: "「{query}」の検索結果はありません",
            .korean: "“{query}”에 대한 결과가 없습니다",
            .simplifiedChinese: "没有找到“{query}”的结果",
            .traditionalChinese: "找不到「{query}」的結果"
        ],
        "search_for_query": [
            .english: "Search for “{query}”",
            .japanese: "「{query}」を検索",
            .korean: "“{query}” 검색",
            .simplifiedChinese: "搜索“{query}”",
            .traditionalChinese: "搜尋「{query}」"
        ],
        "search_recent": [
            .english: "Recent",
            .japanese: "最近の検索",
            .korean: "최근 검색",
            .simplifiedChinese: "最近搜索",
            .traditionalChinese: "最近搜尋"
        ],
        "profile_show_more": [
            .english: "Show more",
            .japanese: "もっと見る",
            .korean: "더 보기",
            .simplifiedChinese: "展开",
            .traditionalChinese: "展開"
        ],
        "show_replies": [
            .english: "Show replies",
            .japanese: "返信を表示",
            .korean: "답글 표시",
            .simplifiedChinese: "显示回复",
            .traditionalChinese: "顯示回覆"
        ],
        "profile_show_less": [
            .english: "Show less",
            .japanese: "閉じる",
            .korean: "접기",
            .simplifiedChinese: "收起",
            .traditionalChinese: "收合"
        ],
        "profile_blocked": [
            .english: "Blocked",
            .japanese: "ブロックされています",
            .korean: "차단됨",
            .simplifiedChinese: "已被屏蔽",
            .traditionalChinese: "已被封鎖"
        ],
        "peek_following": [
            .english: "Following",
            .japanese: "フォロー中",
            .korean: "팔로잉",
            .simplifiedChinese: "正在关注",
            .traditionalChinese: "跟隨中"
        ],
        "peek_followers": [
            .english: "Followers",
            .japanese: "フォロワー",
            .korean: "팔로워",
            .simplifiedChinese: "关注者",
            .traditionalChinese: "跟隨者"
        ],
        "theme_colour": [
            .english: "Theme Colour",
            .japanese: "テーマカラー",
            .korean: "테마 색상",
            .simplifiedChinese: "主题配色",
            .traditionalChinese: "主題配色"
        ],
        "refresh_animation_color": [
            .english: "Theme Colour",
            .japanese: "テーマカラー",
            .korean: "테마 색상",
            .simplifiedChinese: "主题配色",
            .traditionalChinese: "主題配色"
        ],
        "color_blue": [
            .english: "Default Blue",
            .japanese: "デフォルトブルー",
            .korean: "기본 블루",
            .simplifiedChinese: "默认蓝色",
            .traditionalChinese: "預設藍色"
        ],
        "color_pink": [
            .english: "Pink Rose",
            .japanese: "ピンクローズ",
            .korean: "핑크 로즈",
            .simplifiedChinese: "粉红流光",
            .traditionalChinese: "粉紅流光"
        ],
        "color_green": [
            .english: "Aqua Green",
            .japanese: "アクアグリーン",
            .korean: "아쿠아 그린",
            .simplifiedChinese: "青碧翠绿",
            .traditionalChinese: "青碧翠綠"
        ],
        "color_gray": [
            .english: "Monochrome Gray",
            .japanese: "モノクローム・グレー",
            .korean: "모노크롬 그레이",
            .simplifiedChinese: "纯净黑白",
            .traditionalChinese: "純淨黑白"
        ],
        "color_orange_red": [
            .english: "Sunset Orange-Red",
            .japanese: "サンセットオレンジ・レッド",
            .korean: "선셋 오렌지-레드",
            .simplifiedChinese: "日落赤红",
            .traditionalChinese: "日落赤紅"
        ],
        "use_liquid_glass": [
            .english: "Use Liquid Glass",
            .japanese: "リキッドグラスを使用",
            .korean: "리퀴드 글래스 사용",
            .simplifiedChinese: "启用液态玻璃",
            .traditionalChinese: "啟用液態玻璃"
        ],
        "tint_colour": [
            .english: "Tint Colour",
            .japanese: "ティントカラー",
            .korean: "틴트 색상",
            .simplifiedChinese: "色调着色",
            .traditionalChinese: "色調著色"
        ],
        "time_just_now": [
            .english: "just now",
            .japanese: "今",
            .korean: "방금",
            .simplifiedChinese: "刚刚",
            .traditionalChinese: "剛剛"
        ],
        "tooltip_toggle_sidebar": [
            .english: "Toggle Sidebar (⌥`)",
            .japanese: "サイドバーの切り替え (⌥`)",
            .korean: "사이드바 전환 (⌥`)",
            .simplifiedChinese: "切换侧边栏 (⌥`)",
            .traditionalChinese: "切換側邊欄 (⌥`)"
        ],
        "tooltip_search": [
            .english: "Search (⌥S)",
            .japanese: "検索 (⌥S)",
            .korean: "검색 (⌥S)",
            .simplifiedChinese: "搜索 (⌥S)",
            .traditionalChinese: "搜尋 (⌥S)"
        ],
        "tooltip_close_search": [
            .english: "Close Search (Esc / ⌥S)",
            .japanese: "検索を閉じる (Esc / ⌥S)",
            .korean: "검색 닫기 (Esc / ⌥S)",
            .simplifiedChinese: "退出搜索 (Esc / ⌥S)",
            .traditionalChinese: "退出搜尋 (Esc / ⌥S)"
        ],
        "feed_for_you": [
            .english: "For You",
            .japanese: "おすすめ",
            .korean: "추천",
            .simplifiedChinese: "推荐",
            .traditionalChinese: "推薦"
        ],
        "feed_following": [
            .english: "Following",
            .japanese: "フォロー中",
            .korean: "팔로잉",
            .simplifiedChinese: "关注中",
            .traditionalChinese: "關注中"
        ],
        "feed_list": [
            .english: "Lists",
            .japanese: "リスト",
            .korean: "목록",
            .simplifiedChinese: "列表",
            .traditionalChinese: "清單"
        ],
        "select_list": [
            .english: "Select List",
            .japanese: "リストを選択",
            .korean: "목록 선택",
            .simplifiedChinese: "选择列表",
            .traditionalChinese: "選擇清單"
        ],
        "switch_list": [
            .english: "Switch",
            .japanese: "切替",
            .korean: "전환",
            .simplifiedChinese: "切换",
            .traditionalChinese: "切換"
        ],
        "add_custom_list": [
            .english: "Add Custom List...",
            .japanese: "カスタムリストを追加...",
            .korean: "사용자 지정 목록 추가...",
            .simplifiedChinese: "添加自定义列表...",
            .traditionalChinese: "新增自訂清單..."
        ],
        "current_list": [
            .english: "Current:",
            .japanese: "現在のリスト:",
            .korean: "현재:",
            .simplifiedChinese: "当前列表:",
            .traditionalChinese: "目前清單:"
        ],
        "manage_lists_on_x": [
            .english: "Manage Lists on X",
            .japanese: "Xでリストを管理",
            .korean: "X에서 목록 관리",
            .simplifiedChinese: "在 X 上管理列表",
            .traditionalChinese: "在 X 上管理清單"
        ],
        "refresh_lists": [
            .english: "Refresh Lists",
            .japanese: "リストを更新",
            .korean: "목록 새로고침",
            .simplifiedChinese: "刷新列表",
            .traditionalChinese: "重新整理清單"
        ],
        "list_tech": [
            .english: "Tech News",
            .japanese: "テクノロジー",
            .korean: "테크 뉴스",
            .simplifiedChinese: "科技资讯",
            .traditionalChinese: "科技資訊"
        ],
        "list_dev": [
            .english: "Developers",
            .japanese: "開発者",
            .korean: "개발자",
            .simplifiedChinese: "开发者社区",
            .traditionalChinese: "開發者社群"
        ],
        "list_design": [
            .english: "Design & UI",
            .japanese: "デザイン",
            .korean: "디자인",
            .simplifiedChinese: "设计灵感",
            .traditionalChinese: "設計靈感"
        ],
        "list_news": [
            .english: "Headlines",
            .japanese: "総合ニュース",
            .korean: "종합 뉴스",
            .simplifiedChinese: "综合新闻",
            .traditionalChinese: "綜合新聞"
        ],
        "list_acg": [
            .english: "ACG & Art",
            .japanese: "アニメ・アート",
            .korean: "애니메이션・아트",
            .simplifiedChinese: "动漫与艺术",
            .traditionalChinese: "動漫與藝術"
        ],
        // Notification Action Summaries (Likes, Follows, Reposts, Replies, Mentions)
        "notif_liked_single": [
            .english: "{actor} liked your post",
            .japanese: "{actor}さんがあなたの投稿をいいねしました",
            .korean: "{actor}님이 회원님의 게시물을 마음에 들어 합니다",
            .simplifiedChinese: "{actor} 赞了你的推文",
            .traditionalChinese: "{actor} 喜歡了你的貼文"
        ],
        "notif_liked_two": [
            .english: "{actor1} and {actor2} liked your post",
            .japanese: "{actor1}さんと{actor2}さんがあなたの投稿をいいねしました",
            .korean: "{actor1}님과 {actor2}님이 회원님의 게시물을 마음에 들어 합니다",
            .simplifiedChinese: "{actor1} 和 {actor2} 赞了你的推文",
            .traditionalChinese: "{actor1} 和 {actor2} 喜歡了你的貼文"
        ],
        "notif_liked_many": [
            .english: "{actor} and {count} others liked your post",
            .japanese: "{actor}さんと他{count}人があなたの投稿をいいねしました",
            .korean: "{actor}님 외 {count}명이 회원님의 게시물을 마음에 들어 합니다",
            .simplifiedChinese: "{actor} 等 {count} 人赞了你的推文",
            .traditionalChinese: "{actor} 等 {count} 人喜歡了你的貼文"
        ],
        "notif_followed_single": [
            .english: "{actor} followed you",
            .japanese: "{actor}さんにフォローされました",
            .korean: "{actor}님이 회원님을 팔로우했습니다",
            .simplifiedChinese: "{actor} 关注了你",
            .traditionalChinese: "{actor} 關注了你"
        ],
        "notif_followed_two": [
            .english: "{actor1} and {actor2} followed you",
            .japanese: "{actor1}さんと{actor2}さんにフォローされました",
            .korean: "{actor1}님과 {actor2}님이 회원님을 팔로우했습니다",
            .simplifiedChinese: "{actor1} 和 {actor2} 关注了你",
            .traditionalChinese: "{actor1} 和 {actor2} 關注了你"
        ],
        "notif_followed_many": [
            .english: "{actor} and {count} others followed you",
            .japanese: "{actor}さんと他{count}人にフォローされました",
            .korean: "{actor}님 외 {count}명이 회원님을 팔로우했습니다",
            .simplifiedChinese: "{actor} 等 {count} 人关注了你",
            .traditionalChinese: "{actor} 等 {count} 人關注了你"
        ],
        "notif_reposted_single": [
            .english: "{actor} reposted your post",
            .japanese: "{actor}さんがあなたの投稿をリポストしました",
            .korean: "{actor}님이 회원님의 게시물을 재게시했습니다",
            .simplifiedChinese: "{actor} 转发了你的推文",
            .traditionalChinese: "{actor} 轉發了你的貼文"
        ],
        "notif_reposted_two": [
            .english: "{actor1} and {actor2} reposted your post",
            .japanese: "{actor1}さんと{actor2}さんがあなたの投稿をリポストしました",
            .korean: "{actor1}님과 {actor2}님이 회원님의 게시물을 재게시했습니다",
            .simplifiedChinese: "{actor1} 和 {actor2} 转发了你的推文",
            .traditionalChinese: "{actor1} 和 {actor2} 轉發了你的貼文"
        ],
        "notif_reposted_many": [
            .english: "{actor} and {count} others reposted your post",
            .japanese: "{actor}さんと他{count}人があなたの投稿をリポストしました",
            .korean: "{actor}님 외 {count}명이 회원님의 게시물을 재게시했습니다",
            .simplifiedChinese: "{actor} 等 {count} 人转发了你的推文",
            .traditionalChinese: "{actor} 等 {count} 人轉發了你的貼文"
        ],
        "notif_replied_single": [
            .english: "{actor} replied to your post",
            .japanese: "{actor}さんがあなたの投稿に返信しました",
            .korean: "{actor}님이 회원님의 게시물에 답글을 남겼습니다",
            .simplifiedChinese: "{actor} 回复了你的推文",
            .traditionalChinese: "{actor} 回覆了你的貼文"
        ],
        "notif_replied_two": [
            .english: "{actor1} and {actor2} replied to your post",
            .japanese: "{actor1}さんと{actor2}さんがあなたの投稿に返信しました",
            .korean: "{actor1}님과 {actor2}님이 회원님의 게시물에 답글을 남겼습니다",
            .simplifiedChinese: "{actor1} 和 {actor2} 回复了你的推文",
            .traditionalChinese: "{actor1} 和 {actor2} 回覆了你的貼文"
        ],
        "notif_replied_many": [
            .english: "{actor} and {count} others replied to your post",
            .japanese: "{actor}さんと他{count}人があなたの投稿に返信しました",
            .korean: "{actor}님 외 {count}명이 회원님의 게시물에 답글을 남겼습니다",
            .simplifiedChinese: "{actor} 等 {count} 人回复了你的推文",
            .traditionalChinese: "{actor} 等 {count} 人回覆了你的貼文"
        ],
        "notif_recent_post": [
            .english: "Recent post from {actor}",
            .japanese: "{actor}さんからの最新のポスト",
            .korean: "{actor}님의 최근 게시물",
            .simplifiedChinese: "来自 {actor} 的最新帖子",
            .traditionalChinese: "來自 {actor} 的最新貼文"
        ],
        "notif_mentioned_single": [
            .english: "{actor} mentioned you in a post",
            .japanese: "{actor}さんが投稿であなたをメンションしました",
            .korean: "{actor}님이 게시물에서 회원님을 멘션했습니다",
            .simplifiedChinese: "{actor} 在推文中提及了你",
            .traditionalChinese: "{actor} 在貼文中提及了你"
        ],
        "new_posts_available": [
            .english: "{count} new posts",
            .japanese: "{count}件の新しい投稿",
            .korean: "{count}개의 새 게시물",
            .simplifiedChinese: "{count} 条新推文",
            .traditionalChinese: "{count} 則新貼文"
        ],
        "theme_appearance": [
            .english: "Appearance",
            .japanese: "外観テーマ",
            .korean: "화면 테마",
            .simplifiedChinese: "外观主题",
            .traditionalChinese: "外觀主題"
        ],
        "theme_dark": [
            .english: "Dark",
            .japanese: "ダーク",
            .korean: "다크",
            .simplifiedChinese: "深色",
            .traditionalChinese: "深色"
        ],
        "theme_rice_white": [
            .english: "Rice White",
            .japanese: "生成り色",
            .korean: "미색",
            .simplifiedChinese: "米白",
            .traditionalChinese: "米白"
        ],
        "theme_system": [
            .english: "System",
            .japanese: "システム",
            .korean: "시스템",
            .simplifiedChinese: "跟随系统",
            .traditionalChinese: "跟隨系統"
        ],
        "video_quality_highest": [
            .english: "Highest (Default)",
            .japanese: "最高画質 (デフォルト)",
            .korean: "최고 화질 (기본)",
            .simplifiedChinese: "最高画质 (默认)",
            .traditionalChinese: "最高畫質 (預設)"
        ],
        "video_quality_auto": [
            .english: "Auto (Adaptive)",
            .japanese: "自動 (適応型)",
            .korean: "자동 (적응형)",
            .simplifiedChinese: "自动 (自适应网络)",
            .traditionalChinese: "自動 (自適應網路)"
        ],
        "video_quality_1080p": [
            .english: "1080p Full HD",
            .japanese: "1080p フルHD",
            .korean: "1080p 풀HD",
            .simplifiedChinese: "1080p 全高清",
            .traditionalChinese: "1080p 全高畫質"
        ],
        "video_quality_720p": [
            .english: "720p HD",
            .japanese: "720p 高画質",
            .korean: "720p HD",
            .simplifiedChinese: "720p 高清",
            .traditionalChinese: "720p 高畫質"
        ],
        "video_quality_480p": [
            .english: "480p SD",
            .japanese: "480p 標準",
            .korean: "480p SD",
            .simplifiedChinese: "480p 标清",
            .traditionalChinese: "480p 標清"
        ],
        "video_quality_360p": [
            .english: "360p Fast",
            .japanese: "360p 低画質",
            .korean: "360p 일반",
            .simplifiedChinese: "360p 流畅",
            .traditionalChinese: "360p 流暢"
        ],
        "video_save_mp4": [
            .english: "Save MP4",
            .japanese: "MP4を保存",
            .korean: "MP4 저장",
            .simplifiedChinese: "一键保存 MP4",
            .traditionalChinese: "一鍵保存 MP4"
        ],
        "video_share_link": [
            .english: "Share Link",
            .japanese: "リンクを共有",
            .korean: "링크 공유",
            .simplifiedChinese: "分享链接",
            .traditionalChinese: "分享連結"
        ],
        "video_link_copied": [
            .english: "Tweet link copied to clipboard",
            .japanese: "ポストのリンクをコピーしました",
            .korean: "게시물 링크가 복사되었습니다",
            .simplifiedChinese: "推文链接已复制至剪贴板",
            .traditionalChinese: "貼文連結已複製至剪貼簿"
        ],
        "video_downloading": [
            .english: "Downloading highest quality video...",
            .japanese: "最高画質動画をダウンロード中...",
            .korean: "최고 화질 동영상을 다운로드하는 중...",
            .simplifiedChinese: "正在下载最高画质视频...",
            .traditionalChinese: "正在下載最高畫質影片..."
        ],
        "video_saved_success": [
            .english: "Video saved to Downloads",
            .japanese: "動画をダウンロードフォルダに保存しました",
            .korean: "동영상이 다운로드 폴더에 저장되었습니다",
            .simplifiedChinese: "视频已保存至 Downloads 目录",
            .traditionalChinese: "影片已保存至 Downloads 目錄"
        ],
        "video_download_failed": [
            .english: "Failed to download video",
            .japanese: "動画のダウンロードに失敗しました",
            .korean: "동영상 다운로드 실패",
            .simplifiedChinese: "下载视频失败",
            .traditionalChinese: "下載影片失敗"
        ],
        "video_quality_switched": [
            .english: "Quality switched to: {quality}",
            .japanese: "画質を切り替えました: {quality}",
            .korean: "화질이 변경되었습니다: {quality}",
            .simplifiedChinese: "画质已切换为: {quality}",
            .traditionalChinese: "畫質已切換為: {quality}"
        ],
        "copy_image": [
            .english: "Copy Image",
            .japanese: "画像をコピー",
            .korean: "이미지 복사",
            .simplifiedChinese: "复制图片",
            .traditionalChinese: "複製圖片"
        ],
        "copy_original_image": [
            .english: "Copy Original Image",
            .japanese: "原寸画像をコピー",
            .korean: "원본 이미지 복사",
            .simplifiedChinese: "复制原图",
            .traditionalChinese: "複製原圖"
        ],
        "save_image_as": [
            .english: "Save Image As...",
            .japanese: "画像を別名で保存...",
            .korean: "다른 이름으로 이미지 저장...",
            .simplifiedChinese: "保存图片...",
            .traditionalChinese: "儲存圖片..."
        ],
        "save_video_as": [
            .english: "Save Video As...",
            .japanese: "動画を別名で保存...",
            .korean: "다른 이름으로 동영상 저장...",
            .simplifiedChinese: "保存视频...",
            .traditionalChinese: "儲存影片..."
        ],
        "copy_media_link": [
            .english: "Copy Media Link",
            .japanese: "メディアのリンクをコピー",
            .korean: "미디어 링크 복사",
            .simplifiedChinese: "保存 URL",
            .traditionalChinese: "儲存 URL"
        ],
        "copy_video_link": [
            .english: "Copy Video Link",
            .japanese: "動画リンクをコピー",
            .korean: "동영상 링크 복사",
            .simplifiedChinese: "复制视频链接",
            .traditionalChinese: "複製影片連結"
        ],
        "image_copied": [
            .english: "Original image copied to clipboard",
            .japanese: "原寸画像をクリップボードにコピーしました",
            .korean: "원본 이미지가 클립보드에 복사되었습니다",
            .simplifiedChinese: "原图已复制到剪贴板",
            .traditionalChinese: "原圖已複製至剪貼簿"
        ],
        "image_saved": [
            .english: "Original image saved successfully",
            .japanese: "原寸画像を保存しました",
            .korean: "원본 이미지가 저장되었습니다",
            .simplifiedChinese: "原图已保存",
            .traditionalChinese: "原圖已儲存"
        ],
        "video_saved": [
            .english: "Video saved successfully",
            .japanese: "動画を保存しました",
            .korean: "동영상이 저장되었습니다",
            .simplifiedChinese: "视频已保存",
            .traditionalChinese: "影片已儲存"
        ],
        "media_link_copied": [
            .english: "Media URL copied to clipboard",
            .japanese: "メディアURLをコピーしました",
            .korean: "미디어 URL이 복사되었습니다",
            .simplifiedChinese: "媒体链接已复制到剪贴板",
            .traditionalChinese: "媒體連結已複製至剪貼簿"
        ],
        "fetching_original_image": [
            .english: "Fetching original image...",
            .japanese: "原寸画像を取得中...",
            .korean: "원본 이미지를 가져오는 중...",
            .simplifiedChinese: "正在获取原图...",
            .traditionalChinese: "正在取得原圖..."
        ],
        "downloading_media": [
            .english: "Downloading original media...",
            .japanese: "メディアをダウンロード中...",
            .korean: "미디어를 다운로드하는 중...",
            .simplifiedChinese: "正在下载媒体...",
            .traditionalChinese: "正在下載媒體..."
        ],
        "repost": [
            .english: "Repost",
            .japanese: "リポスト",
            .korean: "재게시",
            .simplifiedChinese: "转帖",
            .traditionalChinese: "轉貼"
        ],
        "share": [
            .english: "Share...",
            .japanese: "共有...",
            .korean: "공유...",
            .simplifiedChinese: "分享...",
            .traditionalChinese: "分享..."
        ],
        "content_settings": [
            .english: "Content & Filter",
            .japanese: "コンテンツとフィルター",
            .korean: "콘텐츠 및 필터",
            .simplifiedChinese: "内容与展示",
            .traditionalChinese: "內容與展示"
        ],
        "show_promoted_posts": [
            .english: "Show Promoted Posts",
            .japanese: "プロモーション（広告）を表示",
            .korean: "프로모션 게시물(광고) 표시",
            .simplifiedChinese: "显示推广推文（广告）",
            .traditionalChinese: "顯示推廣推文（廣告）"
        ],
        "show_promoted_posts_desc": [
            .english: "Include promoted ads in timeline and replies with an Ad badge. Disabled by default.",
            .japanese: "タイムラインと返信に広告バッジ付きでプロモーションを表示します（デフォルトは非表示）。",
            .korean: "타임라인과 답글에 광고 배지가 부착된 프로모션 게시물을 표시합니다(기본값은 숨김).",
            .simplifiedChinese: "在时间线与评论回复中展示推广内容并附带 Ad 角标，默认关闭。",
            .traditionalChinese: "在時間線與評論回覆中展示推廣內容並附帶 Ad 角標，預設關閉。"
        ],
        "ad_badge": [
            .english: "Ad",
            .japanese: "広告",
            .korean: "광고",
            .simplifiedChinese: "广告",
            .traditionalChinese: "廣告"
        ]
    ]
        
    func t(_ key: String) -> String {
        if let translations = Self.table[key], let text = translations[currentLanguage] {
            return text
        }
        return Self.table[key]?[.english] ?? key
    }
    
    func format(_ key: String, _ replacements: [String: String]) -> String {
        var str = t(key)
        for (k, v) in replacements {
            str = str.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return str
    }
    
    func formatReplyContext(mentions: [String]) -> String {
        guard !mentions.isEmpty else { return "" }
        switch currentLanguage {
        case .simplifiedChinese:
            if mentions.count == 1 {
                return "回复 \(mentions[0])"
            } else if mentions.count == 2 {
                return "回复 \(mentions[0]) 和 \(mentions[1])"
            } else {
                return "回复 \(mentions[0])、\(mentions[1]) 等"
            }
        case .traditionalChinese:
            if mentions.count == 1 {
                return "回覆 \(mentions[0])"
            } else if mentions.count == 2 {
                return "回覆 \(mentions[0]) 與 \(mentions[1])"
            } else {
                return "回覆 \(mentions[0])、\(mentions[1]) 等"
            }
        case .japanese:
            if mentions.count == 1 {
                return "返信先: \(mentions[0])さん"
            } else if mentions.count == 2 {
                return "返信先: \(mentions[0])さん、\(mentions[1])さん"
            } else {
                return "返信先: \(mentions[0])さん、他\(mentions.count - 1)人"
            }
        case .korean:
            if mentions.count == 1 {
                return "\(mentions[0])님에게 보내는 답글"
            } else {
                return "\(mentions.joined(separator: ", "))님에게 보내는 답글"
            }
        case .english:
            fallthrough
        default:
            if mentions.count == 1 {
                return "Replying to \(mentions[0])"
            } else if mentions.count == 2 {
                return "Replying to \(mentions[0]) and \(mentions[1])"
            } else {
                return "Replying to \(mentions[0]), \(mentions[1]) and \(mentions.count - 2) others"
            }
        }
    }
}

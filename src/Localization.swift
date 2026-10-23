//
//  Localization.swift
//  MaX - Headless Data-driven Client
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
        case .japanese: return "日本語 (Japanese)"
        case .korean: return "한국어 (Korean)"
        case .simplifiedChinese: return "简体中文 (Simplified Chinese)"
        case .traditionalChinese: return "繁體中文 (Traditional Chinese)"
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "MaX_AppLanguage")
        }
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "MaX_AppLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .english // Default language is English
        }
    }
    
    // Translation dictionary
    func t(_ key: String) -> String {
        let dict: [String: [AppLanguage: String]] = [
            "app_title": [
                .english: "MaX",
                .japanese: "MaX",
                .korean: "MaX",
                .simplifiedChinese: "MaX",
                .traditionalChinese: "MaX"
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
                .english: "macOS System Default",
                .japanese: "macOS システム標準",
                .korean: "macOS 시스템 기본",
                .simplifiedChinese: "macOS 系统默认",
                .traditionalChinese: "macOS 系統預設"
            ],
            "font_mincho": [
                .english: "Hiragino Mincho (Serif Magazine)",
                .japanese: "ヒラギノ明朝 (Hiragino Mincho)",
                .korean: "히라기노 명조 (Hiragino Mincho)",
                .simplifiedChinese: "日文明朝体 (Hiragino Mincho)",
                .traditionalChinese: "日文明朝體 (Hiragino Mincho)"
            ],
            "shimmer_effect": [
                .english: "120Hz ProMotion Skeleton Shimmer",
                .japanese: "120Hz 高速骨格シマー効果",
                .korean: "120Hz 고속 스켈레톤 쉬머 효과",
                .simplifiedChinese: "120Hz 高刷骨架屏微光扫光",
                .traditionalChinese: "120Hz 高刷骨架屏微光掃光"
            ],
            "clear_cache": [
                .english: "Clear Local Cache",
                .japanese: "ローカルキャッシュを消去",
                .korean: "로컬 캐시 삭제",
                .simplifiedChinese: "清理本地推文缓存",
                .traditionalChinese: "清除本機推文快取"
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
            "like": [
                .english: "Like",
                .japanese: "いいね",
                .korean: "마음에 들어요",
                .simplifiedChinese: "喜欢",
                .traditionalChinese: "喜歡"
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
                .simplifiedChinese: "启用液态玻璃 (Liquid Glass)",
                .traditionalChinese: "啟用液態玻璃 (Liquid Glass)"
            ],
            "tint_colour": [
                .english: "Tint Colour",
                .japanese: "ティントカラー (Tint)",
                .korean: "틴트 색상 (Tint)",
                .simplifiedChinese: "色调着色 (Tint Colour)",
                .traditionalChinese: "色調著色 (Tint Colour)"
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
                .simplifiedChinese: "为你推荐",
                .traditionalChinese: "為你推薦"
            ],
            "feed_following": [
                .english: "Following",
                .japanese: "フォロー中",
                .korean: "팔로잉",
                .simplifiedChinese: "正在关注",
                .traditionalChinese: "正在關注"
            ]
        ]
        
        if let translations = dict[key], let text = translations[currentLanguage] {
            return text
        }
        return dict[key]?[.english] ?? key
    }
}

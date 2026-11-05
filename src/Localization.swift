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
        "messages_search": [
            .english: "Search",
            .japanese: "検索",
            .korean: "검색",
            .simplifiedChinese: "搜索",
            .traditionalChinese: "搜尋"
        ],
        "messages_filter_all": [
            .english: "All Messages",
            .japanese: "すべてのメッセージ",
            .korean: "모든 메시지",
            .simplifiedChinese: "所有信息",
            .traditionalChinese: "所有訊息"
        ],
        "messages_filter_unread": [
            .english: "Unread",
            .japanese: "未読",
            .korean: "읽지 않음",
            .simplifiedChinese: "未读信息",
            .traditionalChinese: "未讀訊息"
        ],
        "messages_filter_known": [
            .english: "Known Senders",
            .japanese: "フォロー中",
            .korean: "아는 사람",
            .simplifiedChinese: "关注的人",
            .traditionalChinese: "關注的人"
        ],
        "messages_filter_requests": [
            .english: "Message Requests",
            .japanese: "メッセージリクエスト",
            .korean: "쪽지 요청",
            .simplifiedChinese: "陌生人请求",
            .traditionalChinese: "陌生人請求"
        ],
        "messages_edit": [
            .english: "Edit",
            .japanese: "編集",
            .korean: "편집",
            .simplifiedChinese: "编辑",
            .traditionalChinese: "編輯"
        ],
        "messages_done": [
            .english: "Done",
            .japanese: "完了",
            .korean: "완료",
            .simplifiedChinese: "完成",
            .traditionalChinese: "完成"
        ],
        "messages_pin": [
            .english: "Pin",
            .japanese: "ピン留め",
            .korean: "고정",
            .simplifiedChinese: "置顶",
            .traditionalChinese: "置頂"
        ],
        "messages_unpin": [
            .english: "Unpin",
            .japanese: "ピン留め解除",
            .korean: "고정 해제",
            .simplifiedChinese: "取消置顶",
            .traditionalChinese: "取消置頂"
        ],
        "messages_mark_read": [
            .english: "Mark as Read",
            .japanese: "既読にする",
            .korean: "읽음으로 표시",
            .simplifiedChinese: "标为已读",
            .traditionalChinese: "標為已讀"
        ],
        "messages_delete": [
            .english: "Delete",
            .japanese: "削除",
            .korean: "삭제",
            .simplifiedChinese: "删除",
            .traditionalChinese: "刪除"
        ],
        "messages_input_placeholder": [
            .english: "Message",
            .japanese: "メッセージ...",
            .korean: "메시지...",
            .simplifiedChinese: "发送私信...",
            .traditionalChinese: "發送私訊..."
        ],
        "messages_empty": [
            .english: "No Conversations",
            .japanese: "会話はありません",
            .korean: "대화가 없습니다",
            .simplifiedChinese: "暂无私信会话",
            .traditionalChinese: "暫無私訊對話"
        ],
        "messages_select_prompt": [
            .english: "Select a conversation",
            .japanese: "メッセージを選択",
            .korean: "대화를 선택하세요",
            .simplifiedChinese: "选择一个会话开始聊天",
            .traditionalChinese: "選擇一個對話開始聊天"
        ],
        "messages_menu_copy": [
            .english: "Copy",
            .japanese: "コピー",
            .korean: "복사",
            .simplifiedChinese: "复制",
            .traditionalChinese: "拷貝"
        ],
        "messages_menu_info": [
            .english: "Info",
            .japanese: "情報",
            .korean: "정보",
            .simplifiedChinese: "信息",
            .traditionalChinese: "資訊"
        ],
        "messages_copied": [
            .english: "Message copied",
            .japanese: "メッセージをコピーしました",
            .korean: "메시지를 복사했습니다",
            .simplifiedChinese: "已复制消息",
            .traditionalChinese: "已拷貝訊息"
        ],
        "messages_info_sent": [
            .english: "Sent",
            .japanese: "送信",
            .korean: "보냄",
            .simplifiedChinese: "已发送",
            .traditionalChinese: "已傳送"
        ],
        "messages_info_received": [
            .english: "Received",
            .japanese: "受信",
            .korean: "받음",
            .simplifiedChinese: "已接收",
            .traditionalChinese: "已接收"
        ],
        "messages_info_seen": [
            .english: "Seen",
            .japanese: "既読",
            .korean: "읽음",
            .simplifiedChinese: "已读",
            .traditionalChinese: "已讀"
        ],
        "messages_info_seen_by": [
            .english: "Seen by {name}",
            .japanese: "{name} が既読",
            .korean: "{name}님이 읽음",
            .simplifiedChinese: "{name} 已读",
            .traditionalChinese: "{name} 已讀"
        ],
        "messages_info_not_seen": [
            .english: "Not seen yet",
            .japanese: "未読",
            .korean: "아직 읽지 않음",
            .simplifiedChinese: "尚未读",
            .traditionalChinese: "尚未讀"
        ],
        "messages_info_reactions": [
            .english: "Reactions",
            .japanese: "リアクション",
            .korean: "반응",
            .simplifiedChinese: "回应",
            .traditionalChinese: "回應"
        ],
        "messages_send_needs_passcode": [
            .english: "Enter your passcode once more to send encrypted messages",
            .japanese: "暗号化メッセージを送信するには、パスコードをもう一度入力してください",
            .korean: "암호화된 메시지를 보내려면 암호를 한 번 더 입력하세요",
            .simplifiedChinese: "请再输入一次密码，以便发送加密消息",
            .traditionalChinese: "請再輸入一次密碼，以便傳送加密訊息"
        ],
        "messages_send_no_key": [
            .english: "This chat has no encryption key yet, so it can't be sent to from here",
            .japanese: "このチャットにはまだ暗号鍵がないため、ここから送信できません",
            .korean: "이 채팅에는 아직 암호화 키가 없어 여기서 보낼 수 없습니다",
            .simplifiedChinese: "此聊天尚无加密密钥，暂时无法从这里发送",
            .traditionalChinese: "此聊天尚無加密金鑰，暫時無法從這裡傳送"
        ],
        "messages_send_attachments_unsupported": [
            .english: "Attachments can't be sent in encrypted chats yet",
            .japanese: "暗号化チャットではまだ添付ファイルを送信できません",
            .korean: "암호화된 채팅에서는 아직 첨부 파일을 보낼 수 없습니다",
            .simplifiedChinese: "加密聊天暂不支持发送附件",
            .traditionalChinese: "加密聊天暫不支援傳送附件"
        ],
        "messages_send_failed": [
            .english: "Message not sent: {reason}",
            .japanese: "送信できませんでした: {reason}",
            .korean: "메시지를 보내지 못했습니다: {reason}",
            .simplifiedChinese: "消息未发送：{reason}",
            .traditionalChinese: "訊息未傳送：{reason}"
        ],
        "messages_sent_status": [
            .english: "Sent",
            .japanese: "送信済み",
            .korean: "보냄",
            .simplifiedChinese: "已发送",
            .traditionalChinese: "已傳送"
        ],
        "messages_info_edited": [
            .english: "Edited",
            .japanese: "編集済み",
            .korean: "수정됨",
            .simplifiedChinese: "已编辑",
            .traditionalChinese: "已編輯"
        ],
        "messages_menu_reply": [
            .english: "Reply",
            .japanese: "返信",
            .korean: "답장",
            .simplifiedChinese: "回复",
            .traditionalChinese: "回覆"
        ],
        "messages_menu_forward": [
            .english: "Forward",
            .japanese: "転送",
            .korean: "전달",
            .simplifiedChinese: "转发",
            .traditionalChinese: "轉寄"
        ],
        "messages_menu_delete": [
            .english: "Delete",
            .japanese: "削除",
            .korean: "삭제",
            .simplifiedChinese: "删除",
            .traditionalChinese: "刪除"
        ],
        "messages_delete_for_me": [
            .english: "Delete for Me",
            .japanese: "自分から削除",
            .korean: "나에게서 삭제",
            .simplifiedChinese: "为我删除",
            .traditionalChinese: "為我刪除"
        ],
        "messages_delete_for_everyone": [
            .english: "Delete for Everyone",
            .japanese: "全員から削除",
            .korean: "모두에게서 삭제",
            .simplifiedChinese: "为所有人删除",
            .traditionalChinese: "為所有人刪除"
        ],
        "messages_delete_failed": [
            .english: "Couldn't delete: {reason}",
            .japanese: "削除できませんでした: {reason}",
            .korean: "삭제하지 못했습니다: {reason}",
            .simplifiedChinese: "无法删除：{reason}",
            .traditionalChinese: "無法刪除：{reason}"
        ],
        "messages_replying_to": [
            .english: "Replying to {name}",
            .japanese: "{name} に返信",
            .korean: "{name}님에게 답장",
            .simplifiedChinese: "回复 {name}",
            .traditionalChinese: "回覆 {name}"
        ],
        "messages_forwarded_label": [
            .english: "Forwarded",
            .japanese: "転送済み",
            .korean: "전달됨",
            .simplifiedChinese: "已转发",
            .traditionalChinese: "已轉寄"
        ],
        "messages_forwarded_toast": [
            .english: "Forwarded to {name}",
            .japanese: "{name} に転送しました",
            .korean: "{name}님에게 전달했습니다",
            .simplifiedChinese: "已转发给 {name}",
            .traditionalChinese: "已轉寄給 {name}"
        ],
        "messages_forward_title": [
            .english: "Forward to…",
            .japanese: "転送先…",
            .korean: "전달할 대상…",
            .simplifiedChinese: "转发给…",
            .traditionalChinese: "轉寄給…"
        ],
        "messages_forward_empty": [
            .english: "No other encrypted chats",
            .japanese: "他に暗号化チャットがありません",
            .korean: "다른 암호화된 채팅이 없습니다",
            .simplifiedChinese: "没有其他加密聊天",
            .traditionalChinese: "沒有其他加密聊天"
        ],
        "messages_cancel": [
            .english: "Cancel",
            .japanese: "キャンセル",
            .korean: "취소",
            .simplifiedChinese: "取消",
            .traditionalChinese: "取消"
        ],
        "messages_reacted_snippet": [
            .english: "Reacted {emoji}",
            .japanese: "{emoji} でリアクションしました",
            .korean: "{emoji}(으)로 반응함",
            .simplifiedChinese: "回应了 {emoji}",
            .traditionalChinese: "回應了 {emoji}"
        ],
        "messages_seen": [
            .english: "Seen",
            .japanese: "既読",
            .korean: "읽음",
            .simplifiedChinese: "已读",
            .traditionalChinese: "已讀"
        ],
        "messages_pinned_section": [
            .english: "Pinned",
            .japanese: "ピン留め済み",
            .korean: "고정됨",
            .simplifiedChinese: "置顶会话",
            .traditionalChinese: "置頂對話"
        ],
        "messages_passcode_title": [
            .english: "Enter Passcode",
            .japanese: "パスコードを入力",
            .korean: "암호 입력",
            .simplifiedChinese: "输入私信密码",
            .traditionalChinese: "輸入私訊密碼"
        ],
        "messages_passcode_subtitle": [
            .english: "Enter your 4-digit passcode to decrypt recent messages and unlock X Chat.",
            .japanese: "最新のメッセージを復号し、X Chatのロックを解除するには4桁のパスコードを入力してください。",
            .korean: "최근 메시지를 복호화하고 X Chat 잠금을 해제하려면 4자리 암호를 입력하세요.",
            .simplifiedChinese: "输入你的 4 位数密码以解密最新私信并解锁 X Chat。",
            .traditionalChinese: "輸入你的 4 位數密碼以解密最新私訊並解鎖 X Chat。"
        ],
        "messages_passcode_unlock": [
            .english: "Unlock",
            .japanese: "ロック解除",
            .korean: "잠금 해제",
            .simplifiedChinese: "解锁",
            .traditionalChinese: "解鎖"
        ],
        "messages_passcode_cancel": [
            .english: "Cancel",
            .japanese: "キャンセル",
            .korean: "취소",
            .simplifiedChinese: "取消",
            .traditionalChinese: "取消"
        ],
        "messages_passcode_banner": [
            .english: "Enter 4-digit passcode to decrypt recent messages",
            .japanese: "4桁のパスコードを入力して最新メッセージを復号",
            .korean: "4자리 암호를 입력하여 최근 메시지 복호화",
            .simplifiedChinese: "输入 4 位数密码以解密最新消息",
            .traditionalChinese: "輸入 4 位數密碼以解密最新訊息"
        ],
        "messages_passcode_unlocked_toast": [
            .english: "X Chat unlocked",
            .japanese: "X Chatのロックを解除しました",
            .korean: "X Chat 잠금 해제됨",
            .simplifiedChinese: "私信已解密解锁",
            .traditionalChinese: "私訊已解密解鎖"
        ],
        "messages_encrypted_notice": [
            .english: "Encrypted Message",
            .japanese: "暗号化されたメッセージ",
            .korean: "암호화된 메시지",
            .simplifiedChinese: "加密消息",
            .traditionalChinese: "加密訊息"
        ],
        "messages_locked_header_btn": [
            .english: "Locked · Tap to Unlock",
            .japanese: "ロック中 · タップして解除",
            .korean: "잠김 · 탭하여 잠금 해제",
            .simplifiedChinese: "未解锁 · 点击输入密码",
            .traditionalChinese: "未解鎖 · 點擊輸入密碼"
        ],
        "messages_locked_card_title": [
            .english: "End-to-End Encrypted Conversation",
            .japanese: "エンドツーエンド暗号化チャット",
            .korean: "종단간 암호화된 대화",
            .simplifiedChinese: "端到端加密对话",
            .traditionalChinese: "端對端加密對話"
        ],
        "messages_locked_card_desc": [
            .english: "Messages in this conversation are protected by X's end-to-end encryption. Enter your 4-digit passcode to unlock and decrypt messages on this device.",
            .japanese: "この会話のメッセージはXのエンドツーエンド暗号化で保護されています。このデバイスで復号するには4桁のパスコードを入力してください。",
            .korean: "이 대화의 메시지는 X의 종단간 암호화로 보호됩니다. 이 기기에서 메시지를 복호화하려면 4자리 암호를 입력하세요.",
            .simplifiedChinese: "此对话受 X 端到端加密保护。输入你在 X 设置的 4 位密码以解锁并在本设备上解密历史消息。",
            .traditionalChinese: "此對話受 X 端對端加密保護。輸入你在 X 設定的 4 位密碼以解鎖並在本設備上解密歷史訊息。"
        ],
        "messages_locked_card_action": [
            .english: "Enter 4-Digit Passcode",
            .japanese: "4桁のパスコードを入力",
            .korean: "4자리 암호 입력",
            .simplifiedChinese: "输入 4 位密码解锁",
            .traditionalChinese: "輸入 4 位密碼解鎖"
        ],
        "messages_locked_bubble_hint": [
            .english: "Tap to enter passcode and decrypt",
            .japanese: "タップしてパスコードを入力し復号",
            .korean: "탭하여 암호 입력 및 복호화",
            .simplifiedChinese: "点击输入密码以解密",
            .traditionalChinese: "點擊輸入密碼以解密"
        ],
        "messages_locked_sidebar_hint": [
            .english: "Encrypted (Tap to Unlock)",
            .japanese: "暗号化（タップして解除）",
            .korean: "암호화됨 (탭하여 해제)",
            .simplifiedChinese: "加密对话 (点击解锁)",
            .traditionalChinese: "加密對話 (點擊解鎖)"
        ],
        "messages_verifying_passcode": [
            .english: "Verifying passcode and decrypting messages...",
            .japanese: "パスコードを検証してメッセージを復号中...",
            .korean: "암호를 확인하고 메시지를 복호화하는 중...",
            .simplifiedChinese: "正在验证密码并解密消息...",
            .traditionalChinese: "正在驗證密碼並解密訊息..."
        ],
        "messages_passcode_incorrect": [
            .english: "Incorrect passcode. Please try again.",
            .japanese: "パスコードが正しくありません。もう一度お試しください。",
            .korean: "암호가 올바르지 않습니다. 다시 시도해 주세요.",
            .simplifiedChinese: "密码错误，请重新输入。",
            .traditionalChinese: "密碼錯誤，請重新輸入。"
        ],
        "messages_passcode_error": [
            .english: "Unable to unlock with passcode.",
            .japanese: "パスコードによるロック解除に失敗しました。",
            .korean: "암호로 잠금을 해제할 수 없습니다.",
            .simplifiedChinese: "解锁失败，请重试。",
            .traditionalChinese: "解鎖失敗，請重試。"
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
        "notif_filter_priority": [
            .english: "Priority",
            .japanese: "優先",
            .korean: "우선",
            .simplifiedChinese: "优先",
            .traditionalChinese: "優先"
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
            .english: "Songti / Mincho",
            .japanese: "明朝体 / 宋体",
            .korean: "송조체 / 명조체",
            .simplifiedChinese: "宋体 / 明朝体",
            .traditionalChinese: "宋體 / 明朝體"
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
        "liked_by": [
            .english: "Liked by",
            .japanese: "いいねした人",
            .korean: "마음에 들어 한 사람",
            .simplifiedChinese: "点赞的人",
            .traditionalChinese: "按讚的人"
        ],
        "reposted_by": [
            .english: "Reposted by",
            .japanese: "リポストした人",
            .korean: "재게시한 사람",
            .simplifiedChinese: "转发的人",
            .traditionalChinese: "轉發的人"
        ],
        "users_load_failed": [
            .english: "Couldn't load this list. X only shows who liked or reposted your own posts.",
            .japanese: "このリストを読み込めませんでした。いいねやリポストしたユーザーは自分の投稿でのみ表示されます。",
            .korean: "이 목록을 불러올 수 없습니다. 마음에 들어 하거나 재게시한 사용자는 내 게시물에서만 표시됩니다.",
            .simplifiedChinese: "无法加载此列表。X 仅显示你自己帖子的点赞和转发用户。",
            .traditionalChinese: "無法載入此清單。X 僅顯示你自己貼文的按讚和轉發使用者。"
        ],
        "users_empty": [
            .english: "Nobody to show yet.",
            .japanese: "表示するユーザーはまだいません。",
            .korean: "아직 표시할 사용자가 없습니다.",
            .simplifiedChinese: "暂时没有可显示的用户。",
            .traditionalChinese: "暫時沒有可顯示的使用者。"
        ],
        "article_label": [
            .english: "Article",
            .japanese: "記事",
            .korean: "아티클",
            .simplifiedChinese: "文章",
            .traditionalChinese: "文章"
        ],
        "article_read_time": [
            .english: "{minutes} min read",
            .japanese: "読了 約{minutes}分",
            .korean: "읽는 시간 {minutes}분",
            .simplifiedChinese: "阅读约 {minutes} 分钟",
            .traditionalChinese: "閱讀約 {minutes} 分鐘"
        ],
        "article_load_failed": [
            .english: "Couldn't load this article.",
            .japanese: "この記事を読み込めませんでした。",
            .korean: "이 아티클을 불러올 수 없습니다.",
            .simplifiedChinese: "无法加载这篇文章。",
            .traditionalChinese: "無法載入這篇文章。"
        ],
        "article_embedded_post": [
            .english: "View the embedded post",
            .japanese: "埋め込まれたポストを見る",
            .korean: "삽입된 게시물 보기",
            .simplifiedChinese: "查看内嵌的帖子",
            .traditionalChinese: "查看內嵌的貼文"
        ],
        "messages_more_reactions": [
            .english: "More emoji",
            .japanese: "その他の絵文字",
            .korean: "이모지 더 보기",
            .simplifiedChinese: "更多表情",
            .traditionalChinese: "更多表情"
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
        "open_in_browser": [
            .english: "Open in Browser",
            .japanese: "ブラウザで開く",
            .korean: "브라우저에서 열기",
            .simplifiedChinese: "在浏览器中打开",
            .traditionalChinese: "在瀏覽器中開啟"
        ],
        "post_menu_mute": [
            .english: "Mute {handle}",
            .japanese: "{handle} をミュート",
            .korean: "{handle} 님 뮤트",
            .simplifiedChinese: "静音 {handle}",
            .traditionalChinese: "將 {handle} 設為靜音"
        ],
        "post_menu_block": [
            .english: "Block {handle}",
            .japanese: "{handle} をブロック",
            .korean: "{handle} 님 차단",
            .simplifiedChinese: "屏蔽 {handle}",
            .traditionalChinese: "封鎖 {handle}"
        ],
        "post_muted_toast": [
            .english: "Muted {handle}",
            .japanese: "{handle} をミュートしました",
            .korean: "{handle} 님을 뮤트했습니다",
            .simplifiedChinese: "已静音 {handle}",
            .traditionalChinese: "已將 {handle} 設為靜音"
        ],
        "post_blocked_toast": [
            .english: "Blocked {handle}",
            .japanese: "{handle} をブロックしました",
            .korean: "{handle} 님을 차단했습니다",
            .simplifiedChinese: "已屏蔽 {handle}",
            .traditionalChinese: "已封鎖 {handle}"
        ],
        "more_actions": [
            .english: "More",
            .japanese: "詳細",
            .korean: "더 보기",
            .simplifiedChinese: "更多操作",
            .traditionalChinese: "更多操作"
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
        "profile_more": [
            .english: "More",
            .japanese: "その他",
            .korean: "더 보기",
            .simplifiedChinese: "更多",
            .traditionalChinese: "更多"
        ],
        "profile_add_to_list": [
            .english: "Add to List",
            .japanese: "リストに追加",
            .korean: "리스트에 추가",
            .simplifiedChinese: "添加到列表",
            .traditionalChinese: "加入列表"
        ],
        "profile_lists_loading": [
            .english: "Loading…",
            .japanese: "読み込み中…",
            .korean: "불러오는 중…",
            .simplifiedChinese: "正在加载…",
            .traditionalChinese: "載入中…"
        ],
        "profile_lists_failed": [
            .english: "Couldn't load your lists",
            .japanese: "リストを読み込めませんでした",
            .korean: "리스트를 불러오지 못했습니다",
            .simplifiedChinese: "无法加载你的列表",
            .traditionalChinese: "無法載入你的列表"
        ],
        "profile_no_lists": [
            .english: "You have no lists",
            .japanese: "リストがありません",
            .korean: "리스트가 없습니다",
            .simplifiedChinese: "你还没有列表",
            .traditionalChinese: "你還沒有列表"
        ],
        "profile_menu_unmute": [
            .english: "Unmute {handle}",
            .japanese: "{handle} のミュートを解除",
            .korean: "{handle} 님 뮤트 해제",
            .simplifiedChinese: "取消静音 {handle}",
            .traditionalChinese: "解除 {handle} 的靜音"
        ],
        "profile_menu_unblock": [
            .english: "Unblock {handle}",
            .japanese: "{handle} のブロックを解除",
            .korean: "{handle} 님 차단 해제",
            .simplifiedChinese: "取消屏蔽 {handle}",
            .traditionalChinese: "解除封鎖 {handle}"
        ],
        "profile_unmuted_toast": [
            .english: "Unmuted {handle}",
            .japanese: "{handle} のミュートを解除しました",
            .korean: "{handle} 님 뮤트를 해제했습니다",
            .simplifiedChinese: "已取消静音 {handle}",
            .traditionalChinese: "已解除 {handle} 的靜音"
        ],
        "profile_unblocked_toast": [
            .english: "Unblocked {handle}",
            .japanese: "{handle} のブロックを解除しました",
            .korean: "{handle} 님 차단을 해제했습니다",
            .simplifiedChinese: "已取消屏蔽 {handle}",
            .traditionalChinese: "已解除封鎖 {handle}"
        ],
        "profile_added_to_list": [
            .english: "Added {handle} to {list}",
            .japanese: "{handle} を {list} に追加しました",
            .korean: "{handle} 님을 {list}에 추가했습니다",
            .simplifiedChinese: "已将 {handle} 添加到 {list}",
            .traditionalChinese: "已將 {handle} 加入 {list}"
        ],
        "profile_removed_from_list": [
            .english: "Removed {handle} from {list}",
            .japanese: "{handle} を {list} から削除しました",
            .korean: "{handle} 님을 {list}에서 삭제했습니다",
            .simplifiedChinese: "已将 {handle} 从 {list} 移除",
            .traditionalChinese: "已將 {handle} 從 {list} 移除"
        ],
        "profile_block_confirm": [
            .english: "Block",
            .japanese: "ブロック",
            .korean: "차단",
            .simplifiedChinese: "屏蔽",
            .traditionalChinese: "封鎖"
        ],
        "profile_block_message": [
            .english: "They will no longer be able to follow you or see your posts, and you will stop following them.",
            .japanese: "相手はあなたをフォローしたり、あなたのポストを見たりできなくなり、あなたのフォローも解除されます。",
            .korean: "상대방은 회원님을 팔로우하거나 게시물을 볼 수 없게 되며, 회원님의 팔로우도 해제됩니다.",
            .simplifiedChinese: "对方将无法关注你或查看你的帖子，你也会取消关注对方。",
            .traditionalChinese: "對方將無法跟隨你或查看你的貼文，你也會取消跟隨對方。"
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
        "theme_light": [
            .english: "Light",
            .japanese: "ライト",
            .korean: "라이트",
            .simplifiedChinese: "浅色",
            .traditionalChinese: "淺色"
        ],
        "theme_tone_mild": [
            .english: "Mild",
            .japanese: "マイルド",
            .korean: "마일드",
            .simplifiedChinese: "柔和",
            .traditionalChinese: "柔和"
        ],
        "theme_tone_minimalism": [
            .english: "Minimalism",
            .japanese: "ミニマリズム",
            .korean: "미니멀리즘",
            .simplifiedChinese: "极简",
            .traditionalChinese: "極簡"
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
        "autoplay_media": [
            .english: "Autoplay Videos and GIFs",
            .japanese: "動画とGIFを自動再生",
            .korean: "동영상 및 GIF 자동 재생",
            .simplifiedChinese: "自动播放视频和 GIF",
            .traditionalChinese: "自動播放影片和 GIF"
        ],
        "autoplay_media_desc": [
            .english: "Plays videos and GIFs on the timeline and post pages without sound. Click one to open it with sound.",
            .japanese: "タイムラインとポストページの動画とGIFを消音で再生します。クリックすると音声付きで開きます。",
            .korean: "타임라인과 게시물 페이지의 동영상과 GIF를 소리 없이 재생합니다. 클릭하면 소리와 함께 열립니다.",
            .simplifiedChinese: "在时间线和帖子页面上静音播放视频和 GIF。点击后可带声音打开。",
            .traditionalChinese: "在時間軸和貼文頁面上靜音播放影片和 GIF。點擊後可帶聲音開啟。"
        ],
        "messages_show_contacts": [
            .english: "Show Conversations",
            .japanese: "会話一覧を表示",
            .korean: "대화 목록 표시",
            .simplifiedChinese: "显示会话列表",
            .traditionalChinese: "顯示對話列表"
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
        ],
        // X's refusals, explained. The wording says what would actually help, because "344" on its own reads like
        // a bug in this app rather than a limit on the account.
        "error_rate_limited": [
            .english: "X has reached its limit for this action for now, so nothing was posted. The limit lifts by itself after a while; adding a phone number to the account raises it.",
            .japanese: "X 側でこの操作の上限に達したため、投稿されませんでした。しばらくすると自動的に解除されます。電話番号を登録すると上限が上がります。",
            .korean: "X에서 이 작업의 한도에 도달해 게시되지 않았습니다. 잠시 후 자동으로 풀리며, 전화번호를 등록하면 한도가 올라갑니다.",
            .simplifiedChinese: "X 说这个动作暂时到达上限了，所以没有发出去。过一段时间会自动解除；给账号绑定手机号可以抬高上限。",
            .traditionalChinese: "X 說這個動作暫時到達上限了，所以沒有發出去。過一段時間會自動解除；給帳號綁定手機號可以抬高上限。"
        ],
        "error_daily_limit": [
            .english: "The account has posted as much as it can today. Posts work again tomorrow.",
            .japanese: "本日の投稿上限に達しました。明日になればまた投稿できます。",
            .korean: "오늘 올릴 수 있는 만큼 게시했습니다. 내일 다시 게시할 수 있습니다.",
            .simplifiedChinese: "这个账号今天的发帖数已经到顶了，明天恢复。",
            .traditionalChinese: "這個帳號今天的發文數已經到頂了，明天恢復。"
        ],
        "error_automated": [
            .english: "X treated this as automated activity and refused it. Wait a few minutes before trying again, and avoid posting the same text or link repeatedly.",
            .japanese: "X に自動化された操作と判定され、送信できませんでした。数分待ってから送り直してください。同じ文面やリンクを続けて投稿するのは避けてください。",
            .korean: "X가 자동화된 활동으로 판단해 거부했습니다. 몇 분 뒤에 다시 시도하고, 같은 문구나 링크를 반복해서 올리는 것은 피하세요.",
            .simplifiedChinese: "X 把这次操作判定成自动化行为，拒绝了。等几分钟再发，并且别反复发同样的文字或链接。",
            .traditionalChinese: "X 把這次操作判定成自動化行為，拒絕了。等幾分鐘再發，並且別反覆發同樣的文字或連結。"
        ],
        "error_duplicate": [
            .english: "X already has this exact post, so it was not sent again. Change the text and try again.",
            .japanese: "同じ内容の投稿が既にあるため、送信されませんでした。文面を変えてください。",
            .korean: "같은 내용의 게시물이 이미 있어 보내지 않았습니다. 내용을 바꿔 다시 시도하세요.",
            .simplifiedChinese: "X 上已经有完全一样的内容了，所以没有再发。改一下文字再试。",
            .traditionalChinese: "X 上已經有完全一樣的內容了，所以沒有再發。改一下文字再試。"
        ],
        "error_too_long": [
            .english: "This is longer than a post can be. Shorten it and try again.",
            .japanese: "投稿できる長さを超えています。短くしてもう一度お試しください。",
            .korean: "게시할 수 있는 길이를 넘었습니다. 줄여서 다시 시도하세요.",
            .simplifiedChinese: "超过一条帖子的长度了，缩短一点再发。",
            .traditionalChinese: "超過一條貼文的長度了，縮短一點再發。"
        ],
        "error_session_expired": [
            .english: "The sign-in for this account has expired. Add the account again in Settings.",
            .japanese: "このアカウントのログインが切れています。設定からもう一度追加してください。",
            .korean: "이 계정의 로그인이 만료되었습니다. 설정에서 계정을 다시 추가하세요.",
            .simplifiedChinese: "这个账号的登录失效了，去设置里重新添加一次。",
            .traditionalChinese: "這個帳號的登入失效了，去設定裡重新加入一次。"
        ],
        "error_account_suspended": [
            .english: "X has suspended this account, so it cannot post.",
            .japanese: "このアカウントは X から凍結されているため投稿できません。",
            .korean: "이 계정은 X에서 정지되어 게시할 수 없습니다.",
            .simplifiedChinese: "这个账号被 X 封禁了，发不了。",
            .traditionalChinese: "這個帳號被 X 封鎖了，發不了。"
        ],
        "error_post_bounced": [
            .english: "X is holding this post back, so only you can see it. That usually clears after using the account normally for a while.",
            .japanese: "この投稿は X によって表示が制限されており、本人にしか見えません。通常どおりの利用を続けると解除されることが多いです。",
            .korean: "이 게시물은 X가 노출을 제한해 작성자만 볼 수 있습니다. 평소처럼 계정을 사용하다 보면 풀리는 경우가 많습니다.",
            .simplifiedChinese: "这条内容被 X 限流了，只有你自己能看到。正常用一段时间账号通常会恢复。",
            .traditionalChinese: "這則內容被 X 限流了，只有你自己看得到。正常用一段時間帳號通常會恢復。"
        ]
    ]
        
    func t(_ key: String) -> String {
        if let translations = Self.table[key], let text = translations[currentLanguage] {
            return text
        }
        return Self.table[key]?[.english] ?? key
    }
    
    /// The same lookup for a named language, for text that is built away from the main thread and must not race
    /// with a language chosen in Settings.
    func t(_ key: String, language: AppLanguage) -> String {
        return Self.table[key]?[language] ?? Self.table[key]?[.english] ?? key
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

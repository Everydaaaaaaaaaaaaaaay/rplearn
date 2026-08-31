import UIKit

/// 设置页的手动系统语音入口。它不会主动弹出，也不会要求用户下载语音。
/// iOS 未提供“朗读内容 › 声音 › 英语”的公开深链，因此复制搜索词后
/// 打开本 App 的系统设置页，由用户自行决定是否继续。
@MainActor
enum VoiceSettingsNavigation {
    static let searchTerm = "朗读内容"

    static func prepareToOpenSettings() -> URL? {
        UIPasteboard.general.string = searchTerm
        return URL(string: UIApplication.openSettingsURLString)
    }
}

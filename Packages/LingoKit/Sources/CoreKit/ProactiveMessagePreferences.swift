import Foundation

/// 角色主动联系的本地偏好。默认开启，用户可随时在设置中关闭。
public enum ProactiveMessagePreferences {
    public static func enabledKey(for accountID: UUID) -> String {
        "lingotrip.proactive-messages.enabled.\(accountID.uuidString.lowercased())"
    }

    public static func isEnabled(
        for accountID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let key = enabledKey(for: accountID)
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    public static func setEnabled(
        _ enabled: Bool,
        for accountID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: enabledKey(for: accountID))
    }

    public static func unreadCountKey(for accountID: UUID) -> String {
        "lingotrip.unread.count.\(accountID.uuidString.lowercased())"
    }
}

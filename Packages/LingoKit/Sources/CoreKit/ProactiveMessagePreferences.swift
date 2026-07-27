import Foundation

/// 角色主动联系的本地偏好。默认开启，用户可随时在设置中关闭。
public enum ProactiveMessagePreferences {
    public static let enabledKey = "lingotrip.proactive-messages.enabled"

    public static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
}

import CoreKit
import Foundation

/// 组合根：持有全部服务实例并向下注入。后续单元逐步填充。
@MainActor
final class AppEnvironment {
    let keychain = KeychainStore()

    init() {
        Log.app.info("AppEnvironment initialized")
    }
}

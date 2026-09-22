import DesignSystem
import SwiftUI

// 保持现有专项测试与我的页调用点稳定；实现由两个场景共享。
typealias MyPageSpatialMotion = DSSceneSpatialMotion
typealias MyPageSpatialScene<Content: View> = DSSceneSpatialScene<Content>

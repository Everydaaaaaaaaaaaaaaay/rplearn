import SwiftUI

public enum DSAnimation {
    public static let press = Animation.easeOut(duration: 0.1)
    public static let snappy = Animation.easeOut(duration: 0.2)
    public static let bouncy = Animation.spring(duration: 0.32, bounce: 0.16)
    public static let pop = Animation.spring(duration: 0.3, bounce: 0.2)
    public static let gentle = Animation.easeOut(duration: 0.18)
}

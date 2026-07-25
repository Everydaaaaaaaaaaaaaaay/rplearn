import SwiftUI

public enum DSAnimation {
    public static let press = Animation.easeOut(duration: 0.08)
    public static let snappy = Animation.easeOut(duration: 0.25)
    public static let bouncy = Animation.spring(duration: 0.35, bounce: 0.38)
    public static let pop = Animation.spring(duration: 0.28, bounce: 0.5)
    public static let gentle = Animation.easeOut(duration: 0.2)
}

import SwiftUI

/// A full-width paper bar, shared across scene and functional roots.
public struct DSBottomBar: View {
    private let selected: Int
    private let unreadCount: Int
    private let activityUnread: Bool
    private let navigate: (Int) -> Void
    private let titles = ["信息", "联系人", "活动", "我的"]
    private let symbols = ["bubble.left.and.bubble.right", "person.2", "figure.walk", "person.crop.circle"]

    public init(selected: Int, unreadCount: Int, activityUnread: Bool, navigate: @escaping (Int) -> Void) {
        self.selected = selected; self.unreadCount = unreadCount
        self.activityUnread = activityUnread; self.navigate = navigate
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4) { index in
                Button { navigate(index) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: symbols[index] + (index == 0 && selected == index ? ".fill" : ""))
                            .font(.system(size: 20, weight: selected == index ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if index == 0 && unreadCount > 0 {
                                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).background(Color.dsDanger, in: Capsule()).offset(x: 12, y: -6)
                                } else if index == 2 && activityUnread {
                                    Circle().fill(Color.dsDanger).frame(width: 6, height: 6).offset(x: 5, y: -2)
                                }
                            }
                        Text(titles[index]).font(.system(size: 11, weight: selected == index ? .semibold : .regular))
                    }.foregroundStyle(selected == index ? DSReadingPalette.ink : DSReadingPalette.secondary)
                        .frame(maxWidth: .infinity).frame(height: 55)
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            if selected == index { Capsule().fill(DSReadingPalette.gold).frame(width: 18, height: 2) }
                        }
                }.buttonStyle(DSReadingPressStyle())
                    .accessibilityLabel(titles[index])
                    .accessibilityIdentifier("mainTab." + ["messages", "contacts", "home", "me"][index])
                    .accessibilityAddTraits(selected == index ? .isSelected : [])
                    .accessibilityValue(index == 0 && unreadCount > 0 ? "\(unreadCount) 条未读信息" : index == 2 && activityUnread ? "有未读活动" : "")
            }
        }.padding(.top, 5).padding(.horizontal, 12)
            .background(DSReadingPalette.paper.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { DSReadingPalette.line.frame(height: 0.5) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("main.tabs")
    }
}

public struct DSTabBarHiddenPreference: PreferenceKey {
    public static let defaultValue = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

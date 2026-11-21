import SwiftUI
import UIKit

// Implementation baseline. These values and native components are the actual
// source of the screenshots, not an illustration of a later implementation.
enum UIStyle {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let canvas = adaptive(0xF1F1EA, 0x141D19)
    static let paper = adaptive(0xFAF6EA, 0x222D27)
    static let ink = adaptive(0x25352E, 0xF0EFE4)
    static let secondary = adaptive(0x687369, 0xB4BCAF)
    static let primary = adaptive(0x2C4338, 0xB6C6AA)
    static let onPrimary = adaptive(0xFFFDF3, 0x18271E)
    static let gold = Color(red: 0.74, green: 0.61, blue: 0.38)
    static let tint = adaptive(0x42685D, 0xAFC6B4)
    static let line = ink.opacity(0.12)
    static let margin: CGFloat = 20
    static let radius: CGFloat = 12
}

struct Asset: View {
    let name: String
    var contentMode: ContentMode = .fill
    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: nil),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else { Rectangle().fill(UIStyle.canvas) }
    }
}

struct Backdrop: View {
    let name: String
    var darkness: Double = 0.15
    var body: some View {
        GeometryReader { p in
            Asset(name: name).frame(width: p.size.width, height: p.size.height).clipped()
                .overlay(LinearGradient(colors: [.black.opacity(darkness + 0.24), .clear, .black.opacity(0.14)],
                                        startPoint: .top, endPoint: .bottom))
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct TopBar: View {
    let title: String
    var subtitle: String? = nil
    var onPhoto = false
    var back: (() -> Void)? = nil
    var trailing: [(String, String, () -> Void)] = []
    var body: some View {
        HStack(spacing: 4) {
            if let back {
                Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44) }.accessibilityLabel("返回")
            }
            VStack(alignment: .leading, spacing: 3) {
                if let subtitle { Text(subtitle).font(.caption2).tracking(1).opacity(0.75) }
                Text(title).font(.system(size: 18, weight: .semibold))
            }.padding(.leading, back == nil ? 8 : 0)
            Spacer(minLength: 0)
            ForEach(trailing.indices, id: \.self) { i in
                Button(action: trailing[i].2) {
                    Image(systemName: trailing[i].0).font(.system(size: 18, weight: .regular))
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(trailing[i].1)
            }
        }
        .foregroundStyle(onPhoto ? Color.white : UIStyle.ink)
        .padding(.horizontal, back == nil ? 12 : 6).frame(height: 54)
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct Paper<Content: View>: View {
    var floating = false
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding)
            .background(UIStyle.paper.opacity(floating ? 0.95 : 1), in: RoundedRectangle(cornerRadius: UIStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.radius).stroke(UIStyle.line.opacity(0.55), lineWidth: 0.5))
            .shadow(color: .black.opacity(floating ? 0.12 : 0), radius: 12, y: 5)
    }
}

struct MainAction: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var symbol = "arrow.right"
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.body.weight(.semibold))
                if !symbol.isEmpty { Image(systemName: symbol).font(.subheadline.weight(.medium)) }
            }.frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(UIStyle.onPrimary)
                .background(UIStyle.primary, in: RoundedRectangle(cornerRadius: UIStyle.radius))
        }.buttonStyle(PressStyle()).opacity(isEnabled ? 1 : 0.4)
    }
}

struct Avatar: View {
    var name = "oliver"
    var size: CGFloat = 46
    var body: some View {
        Asset(name: "avatar-\(name).png").frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().stroke(UIStyle.paper, lineWidth: 1.5)).accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline.weight(.semibold)).foregroundStyle(UIStyle.ink)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(UIStyle.secondary) }
        }
    }
}

struct SettingRow: View {
    let symbol: String
    let title: String
    var value: String? = nil
    var chevron = true
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .frame(width: 23).foregroundStyle(UIStyle.tint)
            Text(title).font(.body).foregroundStyle(UIStyle.ink)
            Spacer(minLength: 8)
            if let value { Text(value).font(.subheadline).foregroundStyle(UIStyle.secondary) }
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(UIStyle.secondary.opacity(0.7)) }
        }.frame(minHeight: 51).contentShape(Rectangle())
    }
}

struct Choice: View {
    let english: String
    let chinese: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(UIStyle.gold).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(english).font(.subheadline.weight(.medium)).foregroundStyle(UIStyle.ink)
                    Text(chinese).font(.caption).foregroundStyle(UIStyle.secondary)
                }
                Spacer(minLength: 0)
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(UIStyle.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(UIStyle.gold.opacity(0.45), lineWidth: 0.7))
        }.buttonStyle(PressStyle())
    }
}

struct FineDivider: View {
    var body: some View { Rectangle().fill(UIStyle.line).frame(height: 0.5) }
}

struct BottomTabs: View {
    let selected: Int
    let navigate: (Page) -> Void
    private let names = ["信息", "联系人", "活动", "我的"]
    private let symbols = ["bubble.left.and.bubble.right", "person.2", "figure.walk", "person.crop.circle"]
    private let pages: [Page] = [.messages, .contacts, .home, .me]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4) { i in
                Button { navigate(pages[i]) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: symbols[i] + (i == 0 && i == selected ? ".fill" : ""))
                            .font(.system(size: 20, weight: selected == i ? .semibold : .regular))
                        Text(names[i]).font(.system(size: 11, weight: selected == i ? .semibold : .regular))
                    }.foregroundStyle(selected == i ? UIStyle.ink : UIStyle.secondary)
                        .frame(maxWidth: .infinity).frame(height: 55)
                        .overlay(alignment: .top) {
                            if selected == i { Capsule().fill(UIStyle.gold).frame(width: 18, height: 2) }
                        }
                }.buttonStyle(PressStyle())
            }
        }.padding(.top, 5).padding(.horizontal, 12)
            .background(UIStyle.paper.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { FineDivider() }
    }
}

struct SearchField: View {
    let prompt: String
    @State private var text = ""
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.subheadline)
            TextField(prompt, text: $text).font(.subheadline)
        }.foregroundStyle(UIStyle.secondary).padding(.horizontal, 14).frame(height: 44)
            .background(UIStyle.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: UIStyle.radius))
    }
}

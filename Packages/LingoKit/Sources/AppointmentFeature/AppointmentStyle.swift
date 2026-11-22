import DesignSystem
import SwiftUI

enum AppointmentStyle {
    static let ink = Puff.Palette.ink
    static let canvas = Puff.Palette.page

    /// 约会地点对应的卡通场景类型：按约定标题和地点名里的关键词判断，认不出时画街道。
    static func placeKind(title: String, placeName: String) -> PuffPlaceScene.Kind {
        let text = "\(title) \(placeName)".lowercased()
        let rules: [(PuffPlaceScene.Kind, [String])] = [
            (.cafe, ["cafe", "café", "coffee", "tea", "bakery", "咖啡", "茶", "甜品", "面包"]),
            (.bookshop, ["book", "library", "书店", "图书", "书"]),
            (.market, ["market", "bazaar", "food hall", "市集", "市场", "集市", "美食"]),
            (.park, ["park", "garden", "hill", "lake", "river", "beach", "公园", "花园", "山", "湖", "河", "海滩", "散步"]),
            (.transport, ["station", "pier", "airport", "terminal", "车站", "码头", "机场", "地铁"]),
            (.community, ["community", "centre", "center", "gallery", "museum", "社区", "中心", "美术馆", "博物馆"])
        ]
        return rules.first { _, keywords in keywords.contains { text.contains($0) } }?.0 ?? .street
    }
}

struct AppointmentPage<Content: View>: View {
    let cityID: String
    let cityName: String
    var title = ""
    var backLabel = "返回"
    var onBack: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // 顶部是所在城市的卡通街景，代替原来的实景照片条。
            PuffCityScene(regionID: cityID, viewport: .west)
                .frame(height: 148)
                .clipped()
                .overlay(alignment: .bottom) {
                    HStack(spacing: 10) {
                        AppointmentBackButton(label: backLabel, onBack: onBack)
                        if !title.isEmpty {
                            Text(title)
                                .font(.puff(.subheadline, Puff.Weight.emphasis))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Puff.Palette.card, in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Puff.Palette.ink)
                    .padding(.horizontal, Puff.Space.m).padding(.bottom, 10)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Puff.Palette.page).foregroundStyle(Puff.Palette.ink).tint(PuffCandy.sky.deep)
        .fontDesign(.rounded)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct AppointmentSectionDivider: View {
    var body: some View {
        Rectangle().fill(Puff.Palette.line).frame(height: 1).padding(.vertical, 22)
    }
}

/// 圆形返回按钮：白色圆底，盖在卡通街景上也清楚。
struct AppointmentBackButton: View {
    var label = "返回"
    var onBack: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let onBack { onBack() } else { dismiss() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(Puff.Palette.ink)
                .frame(width: 40, height: 40)
                .background(Puff.Palette.card, in: Circle())
                .overlay { Circle().strokeBorder(Puff.Palette.line, lineWidth: 1) }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel(label)
        .accessibilityIdentifier("appointment.back")
    }
}

/// 约定页的主按钮：铺满宽度的实心糖果按钮。
struct AppointmentPrimaryButtonStyle: PrimitiveButtonStyle {
    var candy: PuffCandy = .sky

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.frame(maxWidth: .infinity)
        }
        .buttonStyle(PuffCandyButtonStyle(candy))
    }
}

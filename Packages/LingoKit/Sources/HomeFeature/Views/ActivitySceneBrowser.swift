import BackendKit
import DesignSystem
import SwiftUI

/// Shared destination picker for the activity entry and local scene review.
public struct ActivitySceneBrowser: View {
    let cityName: String
    let places: [BackendActivityPlace]
    let showsChrome: Bool
    let onBack: () -> Void
    let onChooseCity: (() -> Void)?
    let onJournal: (() -> Void)?
    let onSelect: (BackendActivityPlace) -> Void
    let resumeTitle: String?
    let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    private var place: BackendActivityPlace? {
        places.indices.contains(selection) ? places[selection] : places.first
    }

    public init(cityName: String, places: [BackendActivityPlace], showsChrome: Bool = true,
                onBack: @escaping () -> Void,
                onChooseCity: (() -> Void)? = nil, onJournal: (() -> Void)? = nil,
                onSelect: @escaping (BackendActivityPlace) -> Void,
                resumeTitle: String? = nil, onResume: @escaping () -> Void = {}) {
        self.cityName = cityName
        self.places = places
        self.showsChrome = showsChrome
        self.onBack = onBack
        self.onChooseCity = onChooseCity
        self.onJournal = onJournal
        self.onSelect = onSelect
        self.resumeTitle = resumeTitle
        self.onResume = onResume
    }

    /// 地点 ID 以城市 ID 开头，例如 `london-borough-market`。
    private func regionID(of place: BackendActivityPlace) -> String {
        String(place.id.split(separator: "-").first ?? "")
    }

    public var body: some View {
        ZStack {
            Puff.Palette.page.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, item in
                    PuffPlaceScene(
                        regionID: regionID(of: item),
                        kind: PuffPlaceScene.Kind(category: item.category),
                        placeID: item.id,
                        isActive: index == selection && showsChrome
                    )
                    .ignoresSafeArea()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .accessibilityIdentifier("activities.scene.pager")

            Group {
                if places.count > 1 {
                    HStack {
                        sceneArrow(forward: false)
                        Spacer()
                        sceneArrow(forward: true)
                    }
                    .padding(.horizontal, Puff.Space.s)
                    .offset(y: -60)
                }

                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 24)
                    if let place {
                        placeCard(place)
                            .padding(.horizontal, Puff.Space.m)
                            .padding(.bottom, Puff.Space.m)
                    } else {
                        PuffEmptyState("暂无可去的地点", mood: .curious)
                            .puffCard(radius: Puff.Radius.huge)
                            .padding(Puff.Space.m)
                        Spacer()
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            .opacity(showsChrome ? 1 : 0)
            .animation(Puff.Motion.resolve(Puff.Motion.gentle, reduceMotion: reduceMotion), value: showsChrome)
        }
        .tint(PuffCandy.sky.base)
        .onChange(of: places.map(\.id)) { _, _ in selection = 0 }
    }

    /// 底部白色厚卡片：地点名、页码圆点和出发按钮。
    private func placeCard(_ place: BackendActivityPlace) -> some View {
        VStack(spacing: Puff.Space.s) {
            if places.count > 1 {
                HStack(spacing: 6) {
                    ForEach(places.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? PuffCandy.sky.base : Puff.Palette.line)
                            .frame(width: index == selection ? 22 : 8, height: 8)
                    }
                }
                .animation(Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion), value: selection)
                .accessibilityHidden(true)
            }
            Text(place.titleZh)
                .font(.puff(.title, Puff.Weight.display))
                .foregroundStyle(Puff.Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityIdentifier("activities.scene.title.\(place.id)")
                .accessibilityValue("第 \(selection + 1) 个，共 \(places.count) 个场景")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: move(forward: true)
                    case .decrement: move(forward: false)
                    @unknown default: break
                    }
                }
            if let resumeTitle {
                PuffTag(resumeTitle, systemImage: "clock.arrow.circlepath", candy: .tangerine)
            }
            Button {
                if resumeTitle != nil { onResume() }
                else { onSelect(place) }
            } label: {
                Label(resumeTitle == nil ? "去这里逛逛" : "继续上次外出", systemImage: "figure.walk")
                    .frame(minWidth: 200, minHeight: 50)
            }
            .buttonStyle(PuffCandyButtonStyle(resumeTitle == nil ? .sky : .tangerine))
            .accessibilityLabel(resumeTitle == nil ? "去这里逛逛" : "继续上次外出")
            .accessibilityIdentifier(resumeTitle == nil
                ? "activities.place.\(place.id)" : "activities.resumePlaceOuting")
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Puff.Space.l)
        .padding(.vertical, Puff.Space.m)
        .frame(maxWidth: .infinity)
        .puffCard(radius: Puff.Radius.huge)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: Puff.Weight.icon, design: .rounded))
                    .foregroundStyle(Puff.Palette.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PuffCardButtonStyle(radius: 22, lipHeight: 3))
            .accessibilityLabel("返回首页").accessibilityIdentifier("activities.back")
            Spacer(minLength: 8)
            Group {
                if let onChooseCity {
                    Button(action: onChooseCity) {
                        HStack(spacing: 6) {
                            Text(cityName)
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: Puff.Weight.icon))
                        }
                        .padding(.horizontal, Puff.Space.m)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(PuffCardButtonStyle(radius: 22, lipHeight: 3))
                    .accessibilityIdentifier("sceneGallery.cities")
                } else {
                    Text(cityName)
                        .padding(.horizontal, Puff.Space.m)
                        .frame(minHeight: 44)
                        .puffCard(radius: 22, lipHeight: 3)
                }
            }
            .font(.puff(.subheadline, Puff.Weight.emphasis))
            .foregroundStyle(Puff.Palette.ink)
            Spacer(minLength: 8)
            if let onJournal {
                Menu {
                    Button("足迹", systemImage: "book.closed", action: onJournal)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: Puff.Weight.icon, design: .rounded))
                        .foregroundStyle(Puff.Palette.ink)
                        .frame(width: 44, height: 44)
                        .puffCard(radius: 22, lipHeight: 3)
                }
                .accessibilityLabel("更多").accessibilityIdentifier("activities.scene.more")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Puff.Space.m).padding(.top, 4)
    }

    private func sceneArrow(forward: Bool) -> some View {
        let enabled = forward ? selection < places.count - 1 : selection > 0
        return Button { move(forward: forward) } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 17, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(enabled ? PuffCandy.sky.deep : Puff.Palette.inkFaint)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PuffCardButtonStyle(radius: 22, lipHeight: 3))
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
        .accessibilityLabel(forward ? "下一个场景" : "上一个场景")
        .accessibilityIdentifier(forward ? "activities.scene.next" : "activities.scene.previous")
    }

    private func move(forward: Bool) {
        let next = selection + (forward ? 1 : -1)
        guard places.indices.contains(next) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1)) {
            selection = next
        }
    }
}

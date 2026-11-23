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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @State private var credits: BackendActivityPhoto?
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

    /// 当前地点用的是风格化实拍，需要能查看摄影署名与许可。
    private var hasPhoto: Bool {
        place.map { PuffPlaceScene.hasPhoto(placeID: $0.id) } ?? false
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
                        .background(alignment: .top) {
                            // 室内照片顶部常是细碎的天花板：垫一层与页面底色一致的淡渐变，状态栏和顶栏更清楚。
                            LinearGradient(colors: [Puff.Palette.page.opacity(0.7), Puff.Palette.page.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                                .padding(.bottom, -28)
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                        }
                    Spacer(minLength: 24)
                    if let place {
                        placeCard(place)
                            .padding(.horizontal, Puff.Space.m)
                            .padding(.bottom, Puff.Space.s)
                    } else {
                        PuffEmptyState("暂无可去的地点", pose: .point)
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
        .sheet(item: $credits) { ActivityPhotoCredits(photo: $0) }
    }

    /// 底部薄卡片：左边地点名和页码圆点，右边出发按钮，长名字在左栏内换行。
    /// 继续上次外出（标签较长）或无障碍大字号时上下排列。
    private func placeCard(_ place: BackendActivityPlace) -> some View {
        let stacked = resumeTitle != nil || dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Puff.Space.s))
            : AnyLayout(HStackLayout(spacing: Puff.Space.s))
        return layout {
            placeSummary(place)
                .frame(maxWidth: .infinity, alignment: .leading)
            visitButton(place)
                .frame(maxWidth: stacked ? .infinity : nil)
        }
        .padding(.leading, Puff.Space.m)
        .padding(.trailing, Puff.Space.s)
        .padding(.vertical, Puff.Space.s)
        .frame(maxWidth: 560)
        .puffCard(radius: Puff.Radius.large)
        .frame(maxWidth: .infinity)
    }

    private func placeSummary(_ place: BackendActivityPlace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(place.titleZh)
                .font(.puff(.title3, Puff.Weight.display))
                .foregroundStyle(Puff.Palette.ink)
                .lineLimit(2)
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
            } else if places.count > 1 {
                HStack(spacing: 5) {
                    ForEach(places.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? PuffCandy.sky.base : Puff.Palette.line)
                            .frame(width: index == selection ? 16 : 6, height: 6)
                    }
                }
                .animation(Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion), value: selection)
                .accessibilityHidden(true)
            }
        }
    }

    private func visitButton(_ place: BackendActivityPlace) -> some View {
        Button {
            if resumeTitle != nil { onResume() }
            else { onSelect(place) }
        } label: {
            Label(resumeTitle == nil ? "去逛逛" : "继续外出", systemImage: "figure.walk")
                .font(.puff(.body, Puff.Weight.emphasis))
                .lineLimit(1)
                .padding(.horizontal, Puff.Space.m)
                .frame(minHeight: 44)
        }
        .buttonStyle(PuffCandyButtonStyle(resumeTitle == nil ? .sky : .tangerine, radius: 22))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(resumeTitle == nil ? "去这里逛逛" : "继续上次外出")
        .accessibilityIdentifier(resumeTitle == nil
            ? "activities.place.\(place.id)" : "activities.resumePlaceOuting")
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
            if onJournal != nil || hasPhoto {
                Menu {
                    if hasPhoto, let place {
                        Button("照片信息", systemImage: "info.circle") { credits = place.photo }
                    }
                    if let onJournal {
                        Button("足迹", systemImage: "book.closed", action: onJournal)
                    }
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

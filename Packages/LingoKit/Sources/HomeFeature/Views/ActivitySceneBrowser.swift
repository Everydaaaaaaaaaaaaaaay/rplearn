import BackendKit
import DesignSystem
import SwiftUI

/// Shared destination picker for the activity entry and local scene review.
public struct ActivitySceneBrowser: View {
    let cityName: String
    let places: [BackendActivityPlace]
    let onBack: () -> Void
    let onChooseCity: (() -> Void)?
    let onJournal: (() -> Void)?
    let onSelect: (BackendActivityPlace) -> Void
    let resumeTitle: String?
    let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @State private var credits: BackendActivityPhoto?
    @State private var original: BackendActivityPhoto?
    private var place: BackendActivityPlace? {
        places.indices.contains(selection) ? places[selection] : places.first
    }

    public init(cityName: String, places: [BackendActivityPlace], onBack: @escaping () -> Void,
                onChooseCity: (() -> Void)? = nil, onJournal: (() -> Void)? = nil,
                onSelect: @escaping (BackendActivityPlace) -> Void,
                resumeTitle: String? = nil, onResume: @escaping () -> Void = {}) {
        self.cityName = cityName
        self.places = places
        self.onBack = onBack
        self.onChooseCity = onChooseCity
        self.onJournal = onJournal
        self.onSelect = onSelect
        self.resumeTitle = resumeTitle
        self.onResume = onResume
    }

    public var body: some View {
        ZStack {
            Color.dsTravelNavy.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, item in
                    ActivityPlacePhoto(photo: item.photo)
                        .ignoresSafeArea()
                        .accessibilityHidden(index != selection)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .accessibilityIdentifier("activities.scene.pager")

            LinearGradient(stops: [
                .init(color: .black.opacity(0.46), location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: .clear, location: 0.5),
                .init(color: .black.opacity(0.68), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)

            if places.count > 1 {
                HStack {
                    sceneArrow(forward: false)
                    Spacer()
                    sceneArrow(forward: true)
                }.padding(.horizontal, 12)
            }

            VStack(spacing: 0) {
                header
                Spacer(minLength: 24)
                if let place {
                    VStack(spacing: 12) {
                        Text(place.titleZh)
                            .font(.system(.largeTitle, design: .serif, weight: .regular))
                            .tracking(1.5).lineSpacing(8)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
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
                            Text(resumeTitle).font(.subheadline).multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 36).padding(.bottom, 32)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

                    Button {
                        if resumeTitle != nil { onResume() }
                        else { onSelect(place) }
                    } label: {
                        Text(resumeTitle == nil ? "去这里逛逛" : "继续上次外出")
                            .font(.body.weight(.medium)).tracking(2)
                            .padding(.horizontal, 32).padding(.vertical, 19)
                            .frame(minWidth: 230, minHeight: 58)
                            .foregroundStyle(.white)
                            .overlay { Capsule().strokeBorder(.white, lineWidth: 1) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(DSSceneEntranceButtonStyle())
                    .accessibilityIdentifier(resumeTitle == nil
                        ? "activities.place.\(place.id)" : "activities.resumePlaceOuting")
                    .padding(.horizontal, 28).padding(.bottom, 26)
                } else {
                    ContentUnavailableView("暂无可去的地点", systemImage: "mappin")
                    Spacer()
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .foregroundStyle(.white).tint(.white)
        .onChange(of: places.map(\.id)) { _, _ in selection = 0 }
        .sheet(item: $credits) {
            ActivityPhotoCredits(photo: $0)
                .foregroundStyle(Color.dsPaperInk).tint(Color.dsPaperInk)
        }
        .fullScreenCover(item: $original) { OriginalPhoto(photo: $0) }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .light))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }.accessibilityLabel("返回首页").accessibilityIdentifier("activities.back")
            Spacer(minLength: 8)
            if let onChooseCity {
                Button(action: onChooseCity) {
                    HStack(spacing: 8) {
                        Text(cityName).tracking(2)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .regular))
                            .opacity(0.8)
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("sceneGallery.cities")
            } else {
                Text(cityName).font(.subheadline).tracking(2)
            }
            Spacer(minLength: 8)
            Menu {
                if let place {
                    Button("照片信息", systemImage: "info.circle") { credits = place.photo }
                    Button("查看全图", systemImage: "arrow.up.left.and.arrow.down.right") { original = place.photo }
                }
                if let onJournal {
                    Button("足迹", systemImage: "book.closed", action: onJournal)
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("更多").accessibilityIdentifier("activities.scene.more")
        }
        .font(.subheadline.weight(.regular))
        .padding(.horizontal, 28).padding(.top, 4)
        .buttonStyle(DSSceneEntranceButtonStyle())
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
    }

    private func sceneArrow(forward: Bool) -> some View {
        let enabled = forward ? selection < places.count - 1 : selection > 0
        return Button { move(forward: forward) } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 20, weight: .light))
                .symbolEffect(.breathe, options: .repeating.speed(0.6),
                              isActive: enabled && !reduceMotion && scenePhase == .active
                                && credits == nil && original == nil)
                .opacity(enabled ? 0.9 : 0.25)
                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                .frame(width: 44, height: 64).contentShape(Rectangle())
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
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

    private struct OriginalPhoto: View {
        let photo: BackendActivityPhoto
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                ActivityPlacePhoto(photo: photo, contentMode: .fit).ignoresSafeArea()
            }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }.foregroundStyle(.white).padding(16)
                    .accessibilityLabel("关闭全图")
                    .accessibilityIdentifier("sceneGallery.original.close")
            }
        }
    }
}

import DesignSystem
import DomainKit
import SwiftUI
import UIKit

/// Immutable photo coordinates shared by the single master, light and hotspots.
struct ActivitySceneView: View {
    private static let photos: [String: UIImage] = Dictionary(uniqueKeysWithValues:
        Set(ActivitySceneID.allCases.map(\.poster)).sorted().compactMap { name in
            (asset(name, "png") ?? asset(name, "jpg"))
                .flatMap { UIImage(contentsOfFile: $0.path) }.map { (name, $0) }
        })
    let isVisible: Bool
    let showsInterface: Bool
    @Binding var scene: ActivitySceneID
    let cityName: String
    let completedCount: Int
    let onClose: () -> Void
    let onJournal: () -> Void
    let onSelect: (SceneActivity) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var actions = DSSceneActionCoordinator<String>()
    @State private var requestsMotion = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermal = ProcessInfo.processInfo.thermalState
    @State private var lightPlaying = false
    @State private var completedLoops = 0
    @State private var playbackSeconds = 0

    private var usesMotion: Bool {
        ActivityAmbientLightLayer.permitsMotion(requested: requestsMotion, reduceMotion: reduceMotion,
                                               lowPower: lowPower, thermal: thermal)
    }

    private var playbackDescription: String {
        guard usesMotion else { return "静态" }
        let status = lightPlaying && isVisible && scenePhase == .active ? "播放中" : "已暂停或准备中"
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "activities" {
            return "动态 · \(status) · 循环\(completedLoops) · 秒\(playbackSeconds)"
        }
        #endif
        return "环境光影 · \(status)"
    }

    var body: some View {
        GeometryReader { proxy in
            // Both layers and hotspots share one immutable photographic coordinate system.
            let scale = max(proxy.size.width / 852, proxy.size.height / 1847)
            let width = 852 * scale
            let height = 1847 * scale
            let origin = ActivitySceneLayout.origin(viewport: proxy.size, canvas: CGSize(width: width, height: height))
            let renderingScene = scene
            ZStack(alignment: .topLeading) {
                Color(red: 0.14, green: 0.13, blue: 0.09)
                ZStack(alignment: .topLeading) {
                    if let photo = Self.photos[scene.poster] {
                        Image(uiImage: photo).resizable().frame(width: width, height: height)
                    }
                    ActivityAmbientLightLayer(scene: scene,
                        playing: usesMotion && isVisible && scenePhase == .active,
                        onPlayback: { if scene == renderingScene { lightPlaying = $0 } },
                        onProgress: { loops, seconds in
                            if scene == renderingScene {
                                completedLoops = loops
                                playbackSeconds = seconds
                            }
                        })
                        .frame(width: width, height: height)
                        .opacity(usesMotion ? 1 : 0)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    if !typeSize.isAccessibilitySize && showsInterface {
                        ForEach(scene.actions) { activity in entrance(activity, scale: scale) }
                    }
                }
                .id(scene)
                .transition(.opacity)
                .frame(width: width, height: height, alignment: .topLeading)
                .offset(x: origin.x, y: origin.y)
                // Overscan belongs to the photo, not the interface's layout proposal.
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                LinearGradient(stops: [.init(color: .black.opacity(0.48), location: 0),
                                       .init(color: .black.opacity(0.42), location: 0.64),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: max(proxy.safeAreaInsets.top, 54) + 250)
                    .allowsHitTesting(false).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Button(action: onClose) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("返回首页").accessibilityIdentifier("activities.back")
                        Spacer()
                        Text(cityName.isEmpty ? "城市活动" : "\(cityName) · 城市活动").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(action: onJournal) { Image(systemName: "person.2").frame(width: 44, height: 44) }
                            .accessibilityLabel("相遇与足迹，已记录 \(completedCount) 项")
                            .accessibilityIdentifier("activities.journal")
                    }
                    ScrollViewReader { reader in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 28) {
                                ForEach(ActivitySceneID.allCases) { item in
                                    Button {
                                        switchScene(to: item)
                                    } label: {
                                        VStack(spacing: 8) {
                                            Text(item.title).font(.title3.weight(scene == item ? .semibold : .regular))
                                                .opacity(scene == item ? 1 : 0.72)
                                            Rectangle().fill(Color.dsHologramIvory.opacity(scene == item ? 1 : 0))
                                                .frame(height: 2)
                                        }.padding(.vertical, 6)
                                    }
                                    .id(item).buttonStyle(.plain)
                                    .accessibilityIdentifier("activities.tab.\(item.rawValue)")
                                    .accessibilityAddTraits(scene == item ? .isSelected : [])
                                }
                            }.padding(.horizontal, 4)
                        }
                        .accessibilityIdentifier("activities.sceneStrip")
                        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                            let all = ActivitySceneID.allCases
                            let index = all.firstIndex(of: scene)! + (value.translation.width < 0 ? 1 : -1)
                            if all.indices.contains(index) { switchScene(to: all[index]) }
                        })
                        .onChange(of: scene) { _, item in
                            withAnimation(DSSceneTransition.animation(reduceMotion: reduceMotion)) {
                                reader.scrollTo(item, anchor: .center)
                            }
                        }
                    }
                    HStack(alignment: .top) {
                        Text(scene.subtitle).font(.caption).padding(.top, 10)
                        Spacer(minLength: 6)
                        Button {
                            requestsMotion.toggle()
                        } label: {
                            Label(usesMotion ? "光影" : "静态", systemImage: usesMotion ? "pause.circle" : "play.circle")
                                .font(.caption).frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("activities.motion")
                        .accessibilityValue(playbackDescription)
                    }
                    if reduceMotion || lowPower || thermal == .serious || thermal == .critical {
                        Text("节能或减少动态效果 · 静态场景")
                            .font(.caption)
                    }
                }
                .foregroundStyle(Color.dsHologramIvory)
                .shadow(color: .black.opacity(0.35), radius: 0.7, y: 0.5)
                .padding(.horizontal, 24)
                .padding(.top, max(proxy.safeAreaInsets.top, 54) + 8)
                .opacity(showsInterface ? 1 : 0)
                .accessibilityHidden(!showsInterface)

                if typeSize.isAccessibilitySize && showsInterface {
                    VStack(spacing: 18) {
                        ForEach(scene.actions) { activity in
                            Button(activity.title) { onSelect(activity) }
                                .accessibilityIdentifier("activities.scene.\(activity.id)")
                        }
                    }
                    .font(.title2.bold()).buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Text("情景美术 · 非城市实拍 / 实时画面")
                    .font(.caption2)
                    // All v4 masters have dark wood at this disclosure anchor.
                    .foregroundStyle(Color.dsHologramIvory.opacity(0.9))
                    .shadow(color: .black.opacity(0.55), radius: 0.7, y: 0.5)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 24) + 78)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                    .opacity(showsInterface ? 1 : 0)
                    .accessibilityIdentifier("activities.disclosure")
                #if DEBUG
                if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "activities" {
                    Text(playbackDescription).font(.system(size: 1)).foregroundStyle(.clear)
                        .accessibilityIdentifier("activities.playbackStatus")
                        .accessibilityValue(playbackDescription)
                        .allowsHitTesting(false)
                }
                #endif
            }
            .clipped()
            .overlay(alignment: .leading) {
                Color.clear.frame(width: 28).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                        if value.translation.width > 56,
                           value.translation.width > abs(value.translation.height) * 1.25 { onClose() }
                    })
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .onDisappear { actions.cancel() }
        .onChange(of: isVisible) { _, visible in if !visible { actions.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermal = ProcessInfo.processInfo.thermalState
        }
    }

    private func switchScene(to item: ActivitySceneID) {
        guard scene != item else { return }
        actions.cancel()
        lightPlaying = false
        completedLoops = 0
        playbackSeconds = 0
        withAnimation(DSSceneTransition.animation(reduceMotion: reduceMotion)) { scene = item }
    }

    private func entrance(_ activity: SceneActivity, scale: CGFloat) -> some View {
        let id = activity.id, title = activity.title, symbol = activity.symbol, anchor = activity.anchor
        let bounds = anchor.entranceBounds
        return Button {
            actions.perform(for: id) { onSelect(activity) }
        } label: {
            DSHologramSurface(transform: DSHologramTransform(
                footprintOffset: CGSize(width: 1.5, height: 3),
                extrusionOffset: CGSize(width: 0.3, height: 0.7))) {
                VStack(alignment: .center, spacing: 8) {
                    DSHologramSymbol(systemName: symbol, size: 34)
                        .frame(width: 128, height: 40, alignment: .center)
                    ActivitySceneLabel(title: title)
                        .fixedSize().frame(width: 128, alignment: .center)
                }
                .frame(width: 128, height: 100)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.right.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsHologramIvory.opacity(0.9))
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .modifier(ActivityPlaneProjection(quad: anchor.localEntranceQuad(scale: scale)))
            .frame(width: bounds.width * scale, height: bounds.height * scale, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSSceneEntranceButtonStyle(keepsPressedAppearance: actions.pressedHotspot == id))
        .accessibilityLabel(title).accessibilityHint("开始这项情境行动")
        .accessibilityIdentifier("activities.scene.\(id)")
        .position(x: bounds.midX * scale, y: bounds.midY * scale)
    }

    static func asset(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ActivityScene")
    }
}

/// Compensate the shared text renderer's raster margin inside this calibrated
/// plane, without moving any existing Home/My labels or changing their material.
struct ActivitySceneLabel: View {
    let title: String
    var body: some View {
        DSHologramText(title, size: 22, weight: .bold, tint: .dsHologramIvory,
                       glowColor: .dsHologramGlow, alignment: .center)
            // Matches DSHologramTextRenderer.displayPadding; pixel regression
            // test below catches any future mismatch if that renderer changes.
            .offset(x: -12)
    }
}

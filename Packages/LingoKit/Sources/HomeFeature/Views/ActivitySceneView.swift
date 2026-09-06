import AVFoundation
import DesignSystem
import DomainKit
import SwiftUI
import UIKit

/// An isolated visual pilot. No changes to city progression or activity outcomes.
public struct ActivitySceneView: View {
    private static let poster = asset("activity-park-poster", "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    private static let table = asset("activity-table", "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    public let isVisible: Bool
    public let onClose: () -> Void
    public let onSelect: (Region.ActivityCategory) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var actions = DSSceneActionCoordinator<String>()
    @State private var requestsMotion = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermal = ProcessInfo.processInfo.thermalState
    @State private var playbackFailed = false
    @State private var videoPlaying = false
    @State private var completedLoops = 0

    public init(isVisible: Bool, onClose: @escaping () -> Void,
                onSelect: @escaping (Region.ActivityCategory) -> Void) {
        self.isVisible = isVisible
        self.onClose = onClose
        self.onSelect = onSelect
    }

    private var usesMotion: Bool {
        requestsMotion && !reduceMotion && !lowPower && thermal != .serious && thermal != .critical
            && !playbackFailed
    }

    private var playbackDescription: String {
        guard usesMotion else { return "静态" }
        let status = videoPlaying && isVisible && scenePhase == .active ? "播放中" : "已暂停或准备中"
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "activities" {
            return "动态 · \(status) · 循环\(completedLoops)"
        }
        #endif
        return "动态 · \(status)"
    }

    public var body: some View {
        GeometryReader { proxy in
            // Both layers and hotspots share one immutable photographic coordinate system.
            let scale = max(proxy.size.width / 852, proxy.size.height / 1847)
            let width = 852 * scale
            let height = 1847 * scale
            ZStack(alignment: .topLeading) {
                Color(red: 0.14, green: 0.13, blue: 0.09)
                ZStack(alignment: .topLeading) {
                    if let photo = Self.poster {
                        Image(uiImage: photo).resizable().frame(width: width, height: 1108 * scale)
                    }
                    ParkLoopLayer(playing: usesMotion && isVisible && scenePhase == .active,
                                  onFailure: { playbackFailed = true },
                                  onPlayback: { videoPlaying = $0 }, onLoop: { completedLoops = $0 })
                        .frame(width: width, height: 1108 * scale)
                        .opacity(usesMotion ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    if let photo = Self.table {
                        Image(uiImage: photo).resizable()
                            .frame(width: width, height: 789 * scale)
                            .offset(y: 1058 * scale)
                    }
                    if !typeSize.isAccessibilitySize {
                        entrance("walk", title: "城市漫步", symbol: "map", category: .outdoors,
                                 x: 0.28, y: 0.711, rotation: -12, tilt: 18, width: width, height: height)
                        entrance("coffee", title: "街角小聚", symbol: "cup.and.saucer", category: .food,
                                 x: 0.805, y: 0.632, rotation: 3, tilt: 9, width: width, height: height)
                        entrance("culture", title: "文化发现", symbol: "book.closed", category: .culture,
                                 x: 0.728, y: 0.829, rotation: 13, tilt: 15, width: width, height: height)
                    }
                }
                .frame(width: width, height: height)
                .offset(x: (proxy.size.width - width) / 2, y: (proxy.size.height - height) / 2)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Button(action: onClose) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("关闭场景样板")
                        Spacer()
                        Text("城市活动").font(.headline)
                        Spacer()
                        Button {
                            requestsMotion.toggle()
                        } label: {
                            Label(usesMotion ? "动态" : "静态", systemImage: usesMotion ? "pause.circle" : "play.circle")
                                .font(.subheadline).frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("activities.motion")
                        .accessibilityValue(playbackDescription)
                    }
                    Text("公园里的午后").font(.subheadline)
                    if reduceMotion || lowPower || thermal == .serious || thermal == .critical || playbackFailed {
                        Text(playbackFailed ? "视频暂不可用 · 静态场景" : "节能或减少动态效果 · 静态场景")
                            .font(.caption)
                    }
                }
                .foregroundStyle(Color.dsHologramIvory)
                .shadow(color: .black.opacity(0.65), radius: 1.2, y: 1)
                .padding(.horizontal, 24)
                .padding(.top, max(proxy.safeAreaInsets.top, 54) + 8)

                if typeSize.isAccessibilitySize {
                    VStack(spacing: 18) {
                        Button("城市漫步") { onSelect(.outdoors) }
                        Button("街角小聚") { onSelect(.food) }
                        Button("文化发现") { onSelect(.culture) }
                    }
                    .font(.title2.bold()).buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Text("场景样板 · 非当前城市实景")
                    .font(.caption2).foregroundStyle(Color.dsHologramIvory.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 24) + 12)
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

    private func entrance(_ id: String, title: String, symbol: String, category: Region.ActivityCategory,
                          x: CGFloat, y: CGFloat, rotation: Double, tilt: Double,
                          width: CGFloat, height: CGFloat) -> some View {
        Button {
            actions.perform(for: id) { onSelect(category) }
        } label: {
            DSHologramSurface(transform: DSHologramTransform(rotationZ: rotation, tiltX: tilt)) {
                VStack(spacing: 8) {
                    DSHologramSymbol(systemName: symbol, size: 34)
                    DSHologramText(title, size: 22, weight: .bold, tint: .dsHologramIvory,
                                   glowColor: .dsHologramGlow, alignment: .center)
                }
            }
            .frame(width: 128, height: 100).contentShape(Rectangle())
        }
        .buttonStyle(DSSceneEntranceButtonStyle(keepsPressedAppearance: actions.pressedHotspot == id))
        .accessibilityLabel(title).accessibilityHint("查看当前城市的相关活动")
        .accessibilityIdentifier("activities.scene.\(id)")
        .position(x: x * width, y: y * height)
    }

    static func asset(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ActivityScene")
    }
}

/// AVFoundation decodes one small silent video; no SwiftUI timer or per-frame state writes.
private struct ParkLoopLayer: UIViewRepresentable {
    let playing: Bool
    let onFailure: () -> Void
    let onPlayback: (Bool) -> Void
    let onLoop: (Int) -> Void

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var observation: NSKeyValueObservation?
        var playbackObservation: NSKeyValueObservation?
        var loopObservation: NSKeyValueObservation?
        func stop() {
            player.pause()
            observation = nil
            playbackObservation = nil
            loopObservation = nil
            looper?.disableLooping()
            looper = nil
            player.removeAllItems()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspectFill
        let coordinator = context.coordinator
        coordinator.player.isMuted = true
        coordinator.player.preventsDisplaySleepDuringVideoPlayback = false
        coordinator.playbackObservation = coordinator.player.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            let running = player.timeControlStatus == .playing
            Task { @MainActor in onPlayback(running) }
        }
        view.playerLayer.player = coordinator.player
        if let url = ActivitySceneView.asset("activity-park-loop", "mp4") {
            let item = AVPlayerItem(url: url)
            coordinator.looper = AVPlayerLooper(player: coordinator.player, templateItem: item)
            coordinator.loopObservation = coordinator.looper?.observe(\.loopCount, options: [.new]) { looper, _ in
                let count = looper.loopCount
                Task { @MainActor in onLoop(count) }
            }
            coordinator.observation = coordinator.looper?.observe(\.status, options: [.new]) { looper, _ in
                if looper.status == .failed { Task { @MainActor in onFailure() } }
            }
        } else {
            Task { @MainActor in onFailure() }
        }
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        if playing { context.coordinator.player.play() } else { context.coordinator.player.pause() }
    }

    static func dismantleUIView(_ view: Surface, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }
}

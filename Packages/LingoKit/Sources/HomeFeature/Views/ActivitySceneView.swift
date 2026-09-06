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
    @State private var quietInterval = false

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
        let status = quietInterval ? "自然空场" : videoPlaying && isVisible && scenePhase == .active ? "播放中" : "已暂停或准备中"
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
                                  onPlayback: { videoPlaying = $0 }, onLoop: { completedLoops = $0 },
                                  onQuiet: { quietInterval = $0 })
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
                                 anchor: .map, scale: scale)
                        entrance("coffee", title: "街角小聚", symbol: "cup.and.saucer", category: .food,
                                 anchor: .cup, scale: scale)
                        entrance("culture", title: "文化发现", symbol: "book.closed", category: .culture,
                                 anchor: .journal, scale: scale)
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
                          anchor: ActivitySceneAnchor, scale: CGFloat) -> some View {
        let bounds = anchor.bounds
        return Button {
            actions.perform(for: id) { onSelect(category) }
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
            }
            .modifier(ActivityPlaneProjection(quad: anchor.localQuad(scale: scale)))
            .frame(width: bounds.width * scale, height: bounds.height * scale, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSSceneEntranceButtonStyle(keepsPressedAppearance: actions.pressedHotspot == id))
        .accessibilityLabel(title).accessibilityHint("查看当前城市的相关活动")
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

/// AVFoundation decodes one small silent video; no SwiftUI timer or per-frame state writes.
private struct ParkLoopLayer: UIViewRepresentable {
    let playing: Bool
    let onFailure: () -> Void
    let onPlayback: (Bool) -> Void
    let onLoop: (Int) -> Void
    let onQuiet: (Bool) -> Void

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor final class Coordinator {
        let player = AVPlayer()
        var observation: NSKeyValueObservation?
        var playbackObservation: NSKeyValueObservation?
        var endObservation: NSObjectProtocol?
        var failureObservation: NSObjectProtocol?
        var wakeTask: Task<Void, Never>?
        var enabled = false
        var waiting = false
        var seeking = false
        var remainingDelay: TimeInterval = 0
        var waitStart: ContinuousClock.Instant?
        var passes = 0
        var cadence = ActivityAmbientCadence()
        var random = SystemRandomNumberGenerator()
        var onQuiet: (Bool) -> Void = { _ in }
        var onLoop: (Int) -> Void = { _ in }

        func setPlaying(_ value: Bool) {
            guard enabled != value else { return }
            enabled = value
            if value {
                if waiting { scheduleWake() } else if !seeking { player.play() }
            } else {
                player.pause()
                if let waitStart {
                    let elapsed = waitStart.duration(to: .now).components
                    remainingDelay = max(0, remainingDelay - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18)
                }
                waitStart = nil
                wakeTask?.cancel()
                wakeTask = nil
            }
        }

        func finishedPass() {
            guard !waiting else { return }
            passes += 1
            onLoop(passes)
            waiting = true
            onQuiet(true)
            remainingDelay = cadence.nextDelay(using: &random)
            #if DEBUG
            // Explicit UI-test acceleration; normal debug/phone launches use real cadence.
            if ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_CADENCE"] == "accelerated" {
                remainingDelay = 2
            }
            #endif
            if enabled { scheduleWake() }
        }

        func scheduleWake() {
            guard wakeTask == nil, waiting, enabled else { return }
            waitStart = .now
            let delay = remainingDelay
            wakeTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.enabled, !Task.isCancelled else { return }
                self.wakeTask = nil
                self.waitStart = nil
                self.remainingDelay = 0
                self.waiting = false
                self.seeking = true
                // Hold the final empty frame until an exact seek has completed.
                self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                    Task { @MainActor in
                        guard let self else { return }
                        self.seeking = false
                        guard finished else { return }
                        self.onQuiet(false)
                        if self.enabled { self.player.play() }
                    }
                }
            }
        }

        func stop() {
            setPlaying(false)
            wakeTask?.cancel()
            player.pause()
            observation = nil
            playbackObservation = nil
            if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
            if let failureObservation { NotificationCenter.default.removeObserver(failureObservation) }
            endObservation = nil
            failureObservation = nil
            player.currentItem?.cancelPendingSeeks()
            player.replaceCurrentItem(with: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspectFill
        let coordinator = context.coordinator
        coordinator.onQuiet = onQuiet
        coordinator.onLoop = onLoop
        coordinator.player.isMuted = true
        coordinator.player.actionAtItemEnd = .pause
        coordinator.player.preventsDisplaySleepDuringVideoPlayback = false
        coordinator.playbackObservation = coordinator.player.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            let running = player.timeControlStatus == .playing
            Task { @MainActor in onPlayback(running) }
        }
        view.playerLayer.player = coordinator.player
        if let url = ActivitySceneView.asset("activity-park-loop", "mp4") {
            let item = AVPlayerItem(url: url)
            coordinator.player.replaceCurrentItem(with: item)
            coordinator.endObservation = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak coordinator] _ in
                Task { @MainActor in coordinator?.finishedPass() }
            }
            coordinator.failureObservation = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
            ) { _ in Task { @MainActor in onFailure() } }
            coordinator.observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                if item.status == .failed { Task { @MainActor in onFailure() } }
            }
        } else {
            Task { @MainActor in onFailure() }
        }
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        context.coordinator.setPlaying(playing)
    }

    static func dismantleUIView(_ view: Surface, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }
}

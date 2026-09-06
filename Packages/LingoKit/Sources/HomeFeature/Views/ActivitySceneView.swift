import AVFoundation
import DesignSystem
import DomainKit
import SwiftUI
import UIKit

/// Immutable photo coordinates shared by foreground, video and object hotspots.
struct ActivitySceneView: View {
    private static let photos: [String: UIImage] = Dictionary(uniqueKeysWithValues:
        ActivitySceneID.allCases.flatMap { [$0.poster, $0.table] }.compactMap { name in
            asset(name, "jpg").flatMap { UIImage(contentsOfFile: $0.path) }.map { (name, $0) }
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
    @State private var playbackFailed = false
    @State private var videoPlaying = false
    @State private var completedLoops = 0
    @State private var quietInterval = false

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

    var body: some View {
        GeometryReader { proxy in
            // Both layers and hotspots share one immutable photographic coordinate system.
            let scale = max(proxy.size.width / 852, proxy.size.height / 1847)
            let width = 852 * scale
            let height = 1847 * scale
            let renderingScene = scene
            ZStack(alignment: .topLeading) {
                Color(red: 0.14, green: 0.13, blue: 0.09)
                ZStack(alignment: .topLeading) {
                    if let photo = Self.photos[scene.poster] {
                        Image(uiImage: photo).resizable().frame(width: width, height: scene.videoHeight * scale)
                    }
                    SceneMotionLayer(scene: scene, playing: usesMotion && isVisible && scenePhase == .active,
                                  onFailure: { if scene == renderingScene { playbackFailed = true } },
                                  onPlayback: { if scene == renderingScene { videoPlaying = $0 } },
                                  onLoop: { if scene == renderingScene { completedLoops = $0 } },
                                  onQuiet: { if scene == renderingScene { quietInterval = $0 } })
                        .id(scene)
                        .frame(width: width, height: scene.videoHeight * scale)
                        .opacity(usesMotion ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    if let photo = Self.photos[scene.table] {
                        Image(uiImage: photo).resizable()
                            .frame(width: width, height: (1847 - scene.tableTop) * scale)
                            .offset(y: scene.tableTop * scale)
                    }
                    if !typeSize.isAccessibilitySize && showsInterface {
                        ForEach(scene.actions) { activity in entrance(activity, scale: scale) }
                    }
                }
                .id(scene)
                .transition(.opacity)
                .frame(width: width, height: height, alignment: .topLeading)
                .offset(x: (proxy.size.width - width) / 2, y: (proxy.size.height - height) / 2)
                LinearGradient(colors: [.black.opacity(0.48), .black.opacity(0.24), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: max(proxy.safeAreaInsets.top, 54) + 220)
                    .allowsHitTesting(false).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Button(action: onClose) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("返回首页").accessibilityIdentifier("activities.back")
                        Spacer()
                        Text(cityName.isEmpty ? "城市活动" : "\(cityName) · 城市活动").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(action: onJournal) { Image(systemName: "book.closed").frame(width: 44, height: 44) }
                            .accessibilityLabel("行动足迹，已完成 \(completedCount) 项")
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
                            Label(usesMotion ? "动态" : "静态", systemImage: usesMotion ? "pause.circle" : "play.circle")
                                .font(.caption).frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("activities.motion")
                        .accessibilityValue(playbackDescription)
                    }
                    if reduceMotion || lowPower || thermal == .serious || thermal == .critical || playbackFailed {
                        Text(playbackFailed ? "视频暂不可用 · 静态场景" : "节能或减少动态效果 · 静态场景")
                            .font(.caption)
                    }
                }
                .foregroundStyle(Color.dsHologramIvory)
                .shadow(color: .black.opacity(0.35), radius: 0.7, y: 0.5)
                .padding(.horizontal, 24)
                .padding(.top, max(proxy.safeAreaInsets.top, 54) + 8)
                .opacity(showsInterface ? 1 : 0)

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
                    .font(.caption2).foregroundStyle(Color.dsHologramIvory.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 24) + 78)
                    .opacity(showsInterface ? 1 : 0)
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
        playbackFailed = false
        videoPlaying = false
        completedLoops = 0
        quietInterval = false
        withAnimation(DSSceneTransition.animation(reduceMotion: reduceMotion)) { scene = item }
    }

    private func entrance(_ activity: SceneActivity, scale: CGFloat) -> some View {
        let id = activity.id, title = activity.title, symbol = activity.symbol, anchor = activity.anchor
        let bounds = anchor.bounds
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
            }
            .modifier(ActivityPlaneProjection(quad: anchor.localQuad(scale: scale)))
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

/// AVFoundation decodes one small silent video; no SwiftUI timer or per-frame state writes.
private struct SceneMotionLayer: UIViewRepresentable {
    let scene: ActivitySceneID
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
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var looperObservation: NSKeyValueObservation?
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
            looper?.disableLooping()
            looperObservation = nil
            looper = nil
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
        if let url = ActivitySceneView.asset("activity-\(scene.rawValue)-loop", "mp4") {
            let item = AVPlayerItem(url: url)
            if scene == .pond {
                coordinator.player.actionAtItemEnd = .advance
                // AVPlayerLooper queues the next decode before the boundary;
                // unlike a notification + seek, it does not pause at the seam.
                coordinator.looper = AVPlayerLooper(player: coordinator.player, templateItem: item)
                coordinator.looperObservation = coordinator.looper?.observe(\.status, options: [.new]) { looper, _ in
                    if looper.status == .failed { Task { @MainActor in onFailure() } }
                }
            } else {
                coordinator.player.replaceCurrentItem(with: item)
                coordinator.endObservation = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
                ) { [weak coordinator] _ in
                    Task { @MainActor in coordinator?.finishedPass() }
                }
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

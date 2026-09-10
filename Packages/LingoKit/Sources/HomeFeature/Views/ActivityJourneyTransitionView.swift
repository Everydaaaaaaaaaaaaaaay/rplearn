import AVFoundation
import DesignSystem
import SwiftUI
import UIKit

struct ActivityJourneyTransitionView: View {
    let deadline: Date
    let now: Date
    let cityID: String
    let cityName: String
    let isVisible: Bool
    let error: String?
    let onRetry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var remaining: Int { max(0, min(15, Int(ceil(deadline.timeIntervalSince(now))))) }

    private var displayedCity: String {
        if reduceMotion { return "目的地 · " + cityName }
        guard remaining > 0,
              let manifest = JourneyMovieManifest.installed,
              let last = manifest.cities.firstIndex(of: cityID) else { return cityName }
        let second = min(14, max(0, Int(15 - deadline.timeIntervalSince(now))))
        let id = manifest.cities[(last + 1 + second) % 15]
        return manifest.names?[id] ?? ""
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.22, blue: 0.23),
                    Color(red: 0.30, green: 0.37, blue: 0.35), Color(red: 0.13, green: 0.19, blue: 0.20)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                JourneyMovieSurface(deadline: deadline, cityID: cityID,
                    playing: isVisible && !reduceMotion && remaining > 0)
                LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.25)],
                    startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    Spacer()
                    if remaining > 0 {
                        if reduceTransparency {
                            Text(String(format: "%02d", remaining))
                                .font(.system(size: 126, weight: .light, design: .rounded)).monospacedDigit()
                                .foregroundStyle(.white).frame(height: 158)
                        } else {
                            JourneyGlassNumber(number: remaining).frame(width: 250, height: 158)
                        }
                        Text("给相遇一点时间").font(.subheadline.weight(.regular)).tracking(4)
                            .padding(.top, 24)
                    } else {
                        Image(systemName: error == nil ? "sparkle" : "cloud")
                            .font(.system(size: 36, weight: .ultraLight)).padding(.bottom, 28)
                        Text(error == nil ? "相遇正在途中" : "旅途暂时停了一下")
                            .font(.title2.weight(.light)).tracking(2)
                        Text(error == nil ? "你可以先去别处看看，准备好后会留在这里。" : "这次行动还在，稍后可以从这里继续。")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center).lineSpacing(5).padding(.top, 18)
                        if error != nil {
                            Button("继续这次行动", action: onRetry)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 24).frame(minHeight: 48)
                                .background(.ultraThinMaterial, in: Capsule()).padding(.top, 28)
                                .accessibilityIdentifier("activities.journey.retry")
                        }
                    }
                    Spacer()
                    Text(displayedCity).font(.caption).tracking(3).padding(.bottom, 22)
                }
                .padding(.horizontal, 32)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .foregroundStyle(.white)
            }
            .clipped()
        }
        .background(Color(red: 0.12, green: 0.22, blue: 0.23).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(remaining > 0 ? "给相遇一点时间，剩余\(remaining)秒" : error == nil ? "行动结果准备中" : "行动暂未完成")
        .accessibilityIdentifier("activities.journey")
    }
}

/// Native live backdrop sampling inside the digit mask, with a fine reflective rim.
/// No screenshot readback, per-frame CPU color extraction or second video decoder.
private struct JourneyGlassNumber: UIViewRepresentable {
    let number: Int
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) { view.setNumber(number) }
    final class Surface: UIView {
        private let glass: UIVisualEffectView
        private let maskLabel = UILabel()
        private let rim = UILabel()
        private var number: Int?
        override init(frame: CGRect) {
            if #available(iOS 26, *) { glass = UIVisualEffectView(effect: UIGlassEffect(style: .clear)) }
            else { glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight)) }
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            let font = UIFont.monospacedDigitSystemFont(ofSize: 126, weight: .light)
            for label in [maskLabel, rim] { label.font = font; label.textAlignment = .center }
            maskLabel.textColor = .black
            glass.mask = maskLabel
            addSubview(glass); addSubview(rim)
            rim.layer.shadowColor = UIColor.black.cgColor
            rim.layer.shadowOpacity = 0.16
            rim.layer.shadowRadius = 1
            rim.layer.shadowOffset = CGSize(width: 0, height: 1)
            accessibilityElementsHidden = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            glass.frame = bounds; maskLabel.frame = glass.bounds; rim.frame = bounds
        }
        func setNumber(_ value: Int) {
            guard value != number else { return }
            number = value
            let text = String(format: "%02d", value)
            maskLabel.text = text
            rim.attributedText = NSAttributedString(string: text, attributes: [
                .font: rim.font as Any, .foregroundColor: UIColor.white.withAlphaComponent(0.13),
                .strokeColor: UIColor.white.withAlphaComponent(0.72), .strokeWidth: -0.65])
        }
    }
}

/// Movie manifest is installed only after source/visual acceptance. Missing media
/// degrades the presentation, never blocks the independently running action.
private struct JourneyMovieManifest: Decodable {
    let movie: String
    let cities: [String]
    let names: [String: String]?
    static let installed: Self? = {
        guard let url = Bundle.main.url(forResource: "encounter-journey", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.cities.count == 15, Set(value.cities).count == 15,
              Bundle.main.url(forResource: value.movie, withExtension: "mp4") != nil else { return nil }
        return value
    }()
}
private struct JourneyMovieSurface: UIViewRepresentable {
    let deadline: Date
    let cityID: String
    let playing: Bool
    func makeUIView(context: Context) -> Surface { Surface(deadline: deadline, cityID: cityID) }
    func updateUIView(_ surface: Surface, context: Context) { surface.setPlaying(playing) }
    static func dismantleUIView(_ surface: Surface, coordinator: ()) { surface.stop() }

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private let player = AVPlayer()
        private var preparation: Task<Void, Never>?
        private let deadline: Date
        private var requested = false
        private var ready = false
        private var active = false
        init(deadline: Date, cityID: String) {
            self.deadline = deadline
            super.init(frame: .zero)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            playerLayer.player = player; playerLayer.videoGravity = .resizeAspectFill
            preparation = Task { [weak self] in
                guard let self,
                      let manifest = JourneyMovieManifest.installed,
                      let last = manifest.cities.firstIndex(of: cityID),
                      let url = Bundle.main.url(forResource: manifest.movie, withExtension: "mp4") else { return }
                do {
                    let asset = AVURLAsset(url: url)
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                    let composition = AVMutableComposition()
                    guard let output = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
                    let start = last + 1
                    let tail = 15 - start
                    if tail > 0 {
                        try output.insertTimeRange(CMTimeRange(start: CMTime(seconds: Double(start), preferredTimescale: 60),
                            duration: CMTime(seconds: Double(tail), preferredTimescale: 60)), of: track, at: .zero)
                    }
                    try output.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: Double(start), preferredTimescale: 60)),
                        of: track, at: CMTime(seconds: Double(tail), preferredTimescale: 60))
                    try Task.checkCancellation()
                    player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
                    ready = true
                    // A still of the destination remains available for reduced motion.
                    if !requested {
                        player.seek(to: CMTime(seconds: 14, preferredTimescale: 60),
                            toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
                    }
                    synchronize()
                } catch { /* Keep the quiet fallback; action state is unaffected. */ }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); synchronize() }
        func setPlaying(_ value: Bool) {
            guard value != requested else { return }
            requested = value
            synchronize()
        }
        private func synchronize() {
            let shouldPlay = requested && window != nil && ready
            guard shouldPlay != active else { return }
            active = shouldPlay
            player.pause()
            if shouldPlay {
                let elapsed = min(15 - 1.0 / 60, max(0, 15 - deadline.timeIntervalSinceNow))
                player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 60), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] done in
                    Task { @MainActor in
                        guard let self, done, self.active else { return }
                        self.player.play()
                    }
                }
            }
        }
        func stop() { preparation?.cancel(); preparation = nil; player.pause(); player.replaceCurrentItem(with: nil) }
    }
}

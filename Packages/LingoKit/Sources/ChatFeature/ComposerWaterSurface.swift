import CoreMotion
import Observation
import SwiftUI

@MainActor @Observable
final class ComposerTilt {
    var x: Double = 0
    var y: Double = 0
    private static let manager = CMMotionManager()
    private static var owner: UUID?
    private let id = UUID()
    private var manager: CMMotionManager { Self.manager }
    func start() {
        guard manager.isDeviceMotionAvailable, Self.owner != id else { return }
        manager.stopDeviceMotionUpdates()
        Self.owner = id
        // Raw device motion, not activity recognition or historical fitness data.
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let x = max(-1, min(1, motion.gravity.x + motion.userAcceleration.x * 0.25))
            let y = max(-1, min(1, motion.gravity.y + 0.6 + motion.userAcceleration.y * 0.15))
            Task { @MainActor [weak self] in
                guard let self, Self.owner == self.id, self.manager.isDeviceMotionActive else { return }
                self.x += (x - self.x) * 0.2
                self.y += (y - self.y) * 0.2
            }
        }
    }
    func stop() {
        if Self.owner == id { manager.stopDeviceMotionUpdates(); Self.owner = nil }
        x = 0; y = 0
    }
}

private struct Waterline: Shape {
    var tilt: CGFloat
    var lift: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(tilt, lift) }
        set { tilt = newValue.first; lift = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        let level = r.height * 0.23 + lift
        return Path { p in
            p.move(to: CGPoint(x: 0, y: level + tilt))
            p.addCurve(to: CGPoint(x: r.width, y: level - tilt),
                control1: CGPoint(x: r.width * 0.33, y: level + tilt - 9),
                control2: CGPoint(x: r.width * 0.7, y: level - tilt + 9))
            p.addLine(to: CGPoint(x: r.width, y: r.height))
            p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath()
        }
    }
}

private struct ComposerReveal: Shape {
    var progress: CGFloat
    var bottomInset: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let radius = hypot(rect.width, rect.height) * max(0, progress)
        let center = CGPoint(x: rect.width - 68, y: rect.height - bottomInset - 30)
        return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2))
    }
}

struct ComposerWaterSurface: View {
    let expanded: Bool
    let bottomInset: CGFloat
    @State private var tilt = ComposerTilt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    private let blue = Color(red: 0.23, green: 0.66, blue: 0.95)
    private let purple = Color(red: 0.55, green: 0.44, blue: 0.94)
    private let shape = UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)

    var body: some View {
        ZStack {
            surface(blue)
            surface(purple)
                .mask {
                    if reduceMotion { Rectangle().opacity(expanded ? 1 : 0) }
                    else { ComposerReveal(progress: expanded ? 1 : 0, bottomInset: bottomInset) }
                }
        }
        .clipShape(shape)
        // A shallow illuminated lip, limited to the upper edge rather than
        // outlining the whole rectangle down to the home indicator.
        .overlay(alignment: .top) {
            ZStack {
                shape.strokeBorder((expanded ? purple : blue).opacity(0.22), lineWidth: 1)
                shape.inset(by: 2).strokeBorder(
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.20 : 0.95),
                                            .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                shape.inset(by: 6).strokeBorder((expanded ? purple : blue).opacity(0.08), lineWidth: 1)
            }
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 32)
                    Spacer(minLength: 0)
                }
            }
        }
        .shadow(color: (expanded ? purple : blue).opacity(0.10), radius: 9, y: -3)
        .animation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.55, dampingFraction: 0.92), value: expanded)
        .task(id: scenePhase == .active && !reduceMotion) {
            if scenePhase == .active && !reduceMotion { tilt.start() } else { tilt.stop() }
        }
        .onDisappear { tilt.stop() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func surface(_ color: Color) -> some View {
        ZStack {
            Rectangle().fill(scheme == .dark ? Color(white: 0.12) : Color(white: 0.99))
            Waterline(tilt: reduceMotion ? 0 : tilt.x * 16, lift: reduceMotion ? 0 : tilt.y * 8)
                .fill(LinearGradient(colors: [color.opacity(scheme == .dark ? 0.23 : 0.17),
                                             color.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .blur(radius: 5)
                .animation(.easeOut(duration: 0.20), value: tilt.x)
                .animation(.easeOut(duration: 0.20), value: tilt.y)
            if !reduceTransparency {
                Rectangle().fill(.ultraThinMaterial).opacity(0.15)
            }
        }
    }
}

struct ComposerModeSwitch: View {
    @Binding var mode: ComposerTranslationModel.Mode
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ComposerTranslationModel.Mode.allCases, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.95)) { mode = item }
                } label: {
                    Text(item.rawValue).font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == item ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if mode == item {
                                Capsule().fill(Color(red: 0.53, green: 0.40, blue: 0.94))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3).frame(width: 170)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.purple.opacity(0.12), lineWidth: 1))
    }
}

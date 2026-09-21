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
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let x = max(-1, min(1, motion.gravity.x + motion.userAcceleration.x * 0.25))
            let y = max(-1, min(1, motion.gravity.y + 0.6 + motion.userAcceleration.y * 0.15))
            Task { @MainActor [weak self] in
                guard let self, Self.owner == self.id, self.manager.isDeviceMotionActive else { return }
                if abs(x - self.x) > 0.008 { self.x = x }
                if abs(y - self.y) > 0.008 { self.y = y }
            }
        }
    }
    func stop() {
        if Self.owner == id { manager.stopDeviceMotionUpdates(); Self.owner = nil }
        x = 0; y = 0
    }
}

struct ComposerWaterSurface: View {
    let expanded: Bool
    let bottomInset: CGFloat
    @State private var tilt = ComposerTilt()
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    private let blue = Color(red: 0.23, green: 0.66, blue: 0.95)
    private let purple = Color(red: 0.55, green: 0.44, blue: 0.94)
    private let shape = UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)

    var body: some View {
        ComposerLiquidRenderer(tilt: SIMD2(tilt.x, tilt.y), purple: expanded,
            dark: scheme == .dark, active: visible && scenePhase == .active,
            reduceMotion: reduceMotion, opaque: reduceTransparency, bottomInset: bottomInset)
        .background(scheme == .dark ? Color(white: 0.10) : Color(white: 0.99))
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
        .onAppear { visible = true }
        .task(id: visible && scenePhase == .active && !reduceMotion) {
            if visible && scenePhase == .active && !reduceMotion { tilt.start() } else { tilt.stop() }
        }
        .onDisappear { visible = false; tilt.stop() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

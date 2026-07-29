import CoreKit
import SwiftUI

/// 可复用的全屏航程转场。业务层提供抵达内容，组件统一负责飞行阶段、减弱动态效果与完成时机。
public struct DSFlightTransitionView<ArrivalContent: View>: View {
    private let fromName: String
    private let toName: String
    private let statusText: String
    private let statusIcon: String
    private let autoCompletionDelay: Duration?
    private let holdsOnArrival: Bool
    private let celebratesOnArrival: Bool
    private let onComplete: @MainActor () -> Void
    private let arrivalContent: () -> ArrivalContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var stage = DSFlightStage.preparing
    @State private var showsArrival = false
    @State private var didComplete = false
    @State private var celebrationTrigger = 0

    public init(
        fromName: String,
        toName: String,
        statusText: String,
        statusIcon: String = "arrow.left.arrow.right",
        autoCompletionDelay: Duration? = nil,
        holdsOnArrival: Bool = false,
        celebratesOnArrival: Bool = false,
        onComplete: @escaping @MainActor () -> Void,
        @ViewBuilder arrivalContent: @escaping () -> ArrivalContent
    ) {
        self.fromName = fromName
        self.toName = toName
        self.statusText = statusText
        self.statusIcon = statusIcon
        self.autoCompletionDelay = autoCompletionDelay
        self.holdsOnArrival = holdsOnArrival
        self.celebratesOnArrival = celebratesOnArrival
        self.onComplete = onComplete
        self.arrivalContent = arrivalContent
    }

    public var body: some View {
        ZStack {
            DSFlightBackdrop(progress: progress)

            if showsArrival {
                arrivalContent()
                    .celebration(
                        celebratesOnArrival,
                        tint: .white,
                        trigger: celebrationTrigger
                    )
                    .transition(
                        .opacity.combined(
                            with: reduceMotion ? .identity : .scale(scale: 0.97)
                        )
                    )
            } else {
                flightContent
                    .transition(.opacity)
            }
        }
        .task { await runAnimation() }
        .interactiveDismissDisabled()
    }

    private var flightContent: some View {
        VStack(spacing: 0) {
            flightToolbar
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)

            Spacer(minLength: DSSpacing.lg)

            DSFlightRouteCard(
                fromName: fromName,
                toName: toName,
                statusText: statusText,
                statusIcon: statusIcon,
                stage: stage,
                progress: progress
            )
            .padding(.horizontal, DSSpacing.md)

            Spacer(minLength: DSSpacing.xl)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("从\(fromName)飞往\(toName)")
    }

    private var flightToolbar: some View {
        HStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.dsBrandCoral)

                Text("\(AppBrand.mascotName)领航")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
            }
            .padding(.horizontal, DSSpacing.sm)
            .frame(minHeight: 40)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                skipFlight()
            } label: {
                Text("跳过")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .padding(.horizontal, DSSpacing.md)
                    .frame(minHeight: 40)
                    .background(.white.opacity(0.14), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint("直接查看抵达结果")
        }
    }

    @MainActor
    private func runAnimation() async {
        if holdsOnArrival {
            progress = 1
            presentArrival(animated: false, feedback: false)
            return
        }

        if reduceMotion {
            progress = 1
            stage = .approaching
            presentArrival(animated: true)
            await completeAfterDelayIfNeeded()
            return
        }

        Haptics.impact(.light)
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)) {
            progress = 0.14
        }
        try? await Task.sleep(for: .milliseconds(380))
        guard canContinueAnimation else { return }

        stage = .cruising
        withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 1.4)) {
            progress = 0.82
        }
        try? await Task.sleep(for: .milliseconds(1_400))
        guard canContinueAnimation else { return }

        stage = .approaching
        Haptics.selection()
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.46)) {
            progress = 1
        }
        try? await Task.sleep(for: .milliseconds(460))
        guard canContinueAnimation else { return }

        presentArrival(animated: true)
        await completeAfterDelayIfNeeded()
    }

    @MainActor
    private func skipFlight() {
        guard !showsArrival else { return }

        progress = 1
        stage = .approaching
        presentArrival(animated: true)

        Task { @MainActor in
            await completeAfterDelayIfNeeded()
        }
    }

    @MainActor
    private func presentArrival(animated: Bool, feedback: Bool = true) {
        guard !showsArrival else { return }

        withAnimation(animated ? DSAnimation.scene : nil) {
            showsArrival = true
        }
        if feedback {
            Haptics.notify(.success)
        }
        if celebratesOnArrival {
            celebrationTrigger += 1
        }
    }

    @MainActor
    private func completeAfterDelayIfNeeded() async {
        guard let autoCompletionDelay else { return }

        try? await Task.sleep(for: autoCompletionDelay)
        guard !Task.isCancelled, !didComplete else { return }
        didComplete = true
        onComplete()
    }

    private var canContinueAnimation: Bool {
        !Task.isCancelled && !showsArrival
    }
}

private enum DSFlightStage {
    case preparing
    case cruising
    case approaching

    var title: String {
        switch self {
        case .preparing: "正在确认航线"
        case .cruising: "云上巡航中"
        case .approaching: "准备抵达目的地"
        }
    }

    var icon: String {
        switch self {
        case .preparing: "map.fill"
        case .cruising: "wind"
        case .approaching: "location.fill"
        }
    }
}

private struct DSFlightRouteCard: View {
    let fromName: String
    let toName: String
    let statusText: String
    let statusIcon: String
    let stage: DSFlightStage
    let progress: CGFloat

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                cityLabel(
                    caption: "出发",
                    name: fromName,
                    icon: "airplane.departure",
                    alignment: .leading,
                    opacity: 1 - progress * 0.42
                )

                Spacer(minLength: DSSpacing.xs)

                Image(systemName: "arrow.right")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, DSSpacing.md)
                    .accessibilityHidden(true)

                Spacer(minLength: DSSpacing.xs)

                cityLabel(
                    caption: "抵达",
                    name: toName,
                    icon: "airplane.arrival",
                    alignment: .trailing,
                    opacity: 0.58 + progress * 0.42
                )
            }

            DSFlightRoute(progress: progress)
                .frame(height: 206)

            VStack(spacing: DSSpacing.xs) {
                Label(stage.title, systemImage: stage.icon)
                    .font(.system(.headline, design: .rounded, weight: .black))

                Label(statusText, systemImage: statusIcon)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.lg)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: DSRadius.hero))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.hero)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.dsBrandInk.opacity(0.16), radius: 24, y: 14)
    }

    private func cityLabel(
        caption: String,
        name: String,
        icon: String,
        alignment: HorizontalAlignment,
        opacity: CGFloat
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Label(caption, systemImage: icon)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))

            Text(name)
                .font(.system(.title3, design: .rounded, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: 118, alignment: alignment == .leading ? .leading : .trailing)
        .opacity(opacity)
    }
}

private struct DSFlightRoute: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let start = CGPoint(x: 54, y: geometry.size.height * 0.76)
            let end = CGPoint(x: geometry.size.width - 54, y: geometry.size.height * 0.76)
            let control = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.02)
            let planePoint = DSFlightPathMath.point(
                progress: progress,
                start: start,
                control: control,
                end: end
            )
            let planeAngle = DSFlightPathMath.angle(
                progress: progress,
                start: start,
                control: control,
                end: end
            )

            ZStack {
                DSFlightArc(start: start, control: control, end: end)
                    .stroke(
                        .white.opacity(0.2),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 9])
                    )

                DSFlightArc(start: start, control: control, end: end)
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.62), .white],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )

                ForEach(0..<4, id: \.self) { index in
                    let trailProgress = max(0, progress - CGFloat(index + 1) * 0.035)
                    Circle()
                        .fill(.white.opacity(0.68 - Double(index) * 0.12))
                        .frame(width: CGFloat(6 - index), height: CGFloat(6 - index))
                        .position(
                            DSFlightPathMath.point(
                                progress: trailProgress,
                                start: start,
                                control: control,
                                end: end
                            )
                        )
                        .opacity(progress > CGFloat(index + 1) * 0.035 ? 1 : 0)
                }

                DSFlightEndpoint(icon: "circle.fill", isActive: true)
                    .position(start)

                DSFlightEndpoint(
                    icon: "location.fill",
                    isActive: progress > 0.86
                )
                .position(end)

                DSFlightCrew(planeAngle: planeAngle)
                    .position(planePoint)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct DSFlightCrew: View {
    let planeAngle: Angle

    var body: some View {
        HStack(spacing: -12) {
            BrandMascotView(pose: .guide, size: 58)

            Image(systemName: "airplane")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.white)
                .rotationEffect(planeAngle)
                .shadow(color: Color.dsBrandInk.opacity(0.24), radius: 7, y: 4)
        }
        .frame(width: 94, height: 70)
    }
}

private struct DSFlightEndpoint: View {
    let icon: String
    let isActive: Bool

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 42, height: 42)
                    .transition(.opacity)
            }

            Circle()
                .fill(isActive ? .white : .white.opacity(0.26))
                .frame(width: 28, height: 28)

            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(isActive ? Color.dsBrandCoral : .white.opacity(0.8))
        }
        .animation(DSAnimation.scene, value: isActive)
        .accessibilityHidden(true)
    }
}

private struct DSFlightBackdrop: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.dsSkyDeep, Color.dsSky, Color.dsCyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.white.opacity(0.26), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 320
            )

            Circle()
                .fill(Color.dsBrandCoral.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -170, y: 300)

            DSFlightCloudLayers(progress: progress)
        }
        .ignoresSafeArea()
    }
}

private struct DSFlightCloudLayers: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                cloud(
                    width: 150,
                    opacity: 0.12,
                    x: geometry.size.width * 0.18 - progress * 54,
                    y: geometry.size.height * 0.18
                )
                cloud(
                    width: 220,
                    opacity: 0.1,
                    x: geometry.size.width * 0.86 - progress * 92,
                    y: geometry.size.height * 0.34
                )
                cloud(
                    width: 290,
                    opacity: 0.14,
                    x: geometry.size.width * 0.08 - progress * 128,
                    y: geometry.size.height * 0.76
                )
                cloud(
                    width: 190,
                    opacity: 0.12,
                    x: geometry.size.width * 0.92 - progress * 76,
                    y: geometry.size.height * 0.9
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func cloud(
        width: CGFloat,
        opacity: Double,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        DSFlightCloudPuff()
            .frame(width: width, height: width * 0.42)
            .foregroundStyle(.white)
            .compositingGroup()
            .opacity(opacity)
            .blur(radius: 3)
            .position(x: x, y: y)
    }
}

private struct DSFlightCloudPuff: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .bottom) {
                Capsule()
                    .frame(width: width, height: height * 0.52)
                Circle()
                    .frame(width: height * 0.8, height: height * 0.8)
                    .offset(x: -width * 0.2)
                Circle()
                    .frame(width: height, height: height)
                    .offset(x: width * 0.1)
            }
        }
    }
}

private enum DSFlightPathMath {
    static func point(
        progress: CGFloat,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint
    ) -> CGPoint {
        let progress = min(max(progress, 0), 1)
        let oneMinus = 1 - progress
        return CGPoint(
            x: oneMinus * oneMinus * start.x
                + 2 * oneMinus * progress * control.x
                + progress * progress * end.x,
            y: oneMinus * oneMinus * start.y
                + 2 * oneMinus * progress * control.y
                + progress * progress * end.y
        )
    }

    static func angle(
        progress: CGFloat,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint
    ) -> Angle {
        let progress = min(max(progress, 0), 1)
        let oneMinus = 1 - progress
        let dx = 2 * oneMinus * (control.x - start.x)
            + 2 * progress * (end.x - control.x)
        let dy = 2 * oneMinus * (control.y - start.y)
            + 2 * progress * (end.y - control.y)
        return .radians(atan2(dy, dx))
    }
}

private struct DSFlightArc: Shape {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

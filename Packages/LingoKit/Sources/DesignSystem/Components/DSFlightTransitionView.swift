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
    @State private var showsArrival = false
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
            LinearGradient(
                colors: [Color.dsSkyDeep, Color.dsSky, Color.dsCyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            DSFlightMovingClouds(progress: progress)

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
    }

    private var flightContent: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer()

            HStack {
                cityLabel(
                    fromName,
                    icon: "airplane.departure",
                    opacity: 1 - progress * 0.65
                )
                Spacer()
                cityLabel(
                    toName,
                    icon: "airplane.arrival",
                    opacity: 0.35 + progress * 0.65
                )
            }
            .padding(.horizontal, DSSpacing.xl)

            GeometryReader { geometry in
                let start = CGPoint(x: 36, y: geometry.size.height * 0.7)
                let end = CGPoint(x: geometry.size.width - 36, y: geometry.size.height * 0.7)
                let control = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.04)

                ZStack {
                    DSFlightArc(start: start, control: control, end: end)
                        .trim(from: 0, to: progress)
                        .stroke(
                            .white.opacity(0.8),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 9])
                        )

                    Image(systemName: "airplane")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .position(
                            quadraticPoint(
                                t: progress,
                                start: start,
                                control: control,
                                end: end
                            )
                        )
                        .rotationEffect(.degrees(-12 + Double(progress) * 24))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 230)

            Label(statusText, systemImage: statusIcon)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.dsSkyDeep)
                .padding(.horizontal, DSSpacing.lg)
                .frame(minHeight: 44)
                .background(.white.opacity(0.94), in: Capsule())
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.lg)

            Spacer()
        }
    }

    private func cityLabel(_ name: String, icon: String, opacity: CGFloat) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .opacity(opacity)
    }

    private func runAnimation() async {
        if holdsOnArrival {
            progress = 1
            showsArrival = true
            if celebratesOnArrival {
                celebrationTrigger += 1
            }
            return
        }

        Haptics.impact(.medium)

        if reduceMotion {
            progress = 1
            withAnimation(.easeOut(duration: 0.2)) {
                showsArrival = true
            }
        } else {
            withAnimation(.easeInOut(duration: 1.65)) {
                progress = 1
            }
            try? await Task.sleep(for: .milliseconds(1_650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                showsArrival = true
            }
        }

        Haptics.notify(.success)
        if celebratesOnArrival {
            celebrationTrigger += 1
        }

        guard let autoCompletionDelay else { return }
        try? await Task.sleep(for: autoCompletionDelay)
        guard !Task.isCancelled else { return }
        onComplete()
    }

    private func quadraticPoint(
        t: CGFloat,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint
    ) -> CGPoint {
        let oneMinus = 1 - t
        return CGPoint(
            x: oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * end.x,
            y: oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * end.y
        )
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

private struct DSFlightMovingClouds: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Image(systemName: "cloud.fill")
                    .font(.system(size: CGFloat(58 + index * 13)))
                    .foregroundStyle(.white.opacity(0.12 + Double(index % 2) * 0.07))
                    .offset(
                        x: CGFloat(index * 88 - 230) - progress * CGFloat(80 + index * 18),
                        y: CGFloat(index * 120 - 310)
                    )
                    .accessibilityHidden(true)
            }
        }
    }
}

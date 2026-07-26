import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

struct FlightPresentation: Identifiable {
    let id = UUID()
    let fromRegionID: String
    let toRegionID: String
    let fromName: String
    let toName: String
    let ticketStub: TicketStubDTO?

    var isFirstArrival: Bool { ticketStub != nil }
}

struct FlightTransitionOverlay: View {
    let presentation: FlightPresentation
    let regionCatalog: RegionCatalog
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var showArrival = false
    @State private var celebrationTrigger = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.dsSkyDeep, Color.dsSky, Color.dsCyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            MovingClouds(progress: progress)

            if showArrival {
                arrivalContent
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
                    presentation.fromName,
                    icon: "airplane.departure",
                    opacity: 1 - progress * 0.65
                )
                Spacer()
                cityLabel(
                    presentation.toName,
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
                    FlightArc(start: start, control: control, end: end)
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
                }
            }
            .frame(height: 230)

            Label(
                presentation.isFirstArrival
                    ? "正在签发首次抵达纪念票根"
                    : "自由往返 · 不产生新票根",
                systemImage: presentation.isFirstArrival ? "rosette" : "arrow.left.arrow.right"
            )
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.dsSkyDeep)
            .padding(.horizontal, DSSpacing.lg)
            .frame(height: 44)
            .background(.white.opacity(0.94), in: Capsule())

            Spacer()
        }
    }

    @ViewBuilder
    private var arrivalContent: some View {
        if let stub = presentation.ticketStub {
            VStack(spacing: DSSpacing.md) {
                Spacer()

                VStack(spacing: 3) {
                    Text("城市收藏 +1")
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.78))
                    Text("首次抵达 \(presentation.toName)")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)

                TicketStubCard(
                    stub: stub,
                    regionCatalog: regionCatalog,
                    mode: .arrival
                )
                .padding(.horizontal, DSSpacing.lg)

                Label("唯一票根已收入票根夹", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.white)

                Button(action: onComplete) {
                    Text("收下票根")
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsSkyDeep)
                .background(.white, in: Capsule())
                .padding(.horizontal, DSSpacing.xl)
                .accessibilityHint("关闭抵达仪式并返回地图")

                Spacer()
            }
            .celebration(true, tint: .white, trigger: celebrationTrigger)
        } else {
            VStack(spacing: DSSpacing.md) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.white)
                Text("欢迎回到 \(presentation.toName)")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .multilineTextAlignment(.center)
                Text("已解锁城市可以自由往返\n这次不会重复生成票根")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .foregroundStyle(.white)
        }
    }

    private func cityLabel(_ name: String, icon: String, opacity: CGFloat) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
            Text(name).font(.headline)
        }
        .foregroundStyle(.white)
        .opacity(opacity)
    }

    private func runAnimation() async {
        if holdsArrivalForUITest {
            progress = 1
            showArrival = true
            if presentation.isFirstArrival {
                celebrationTrigger += 1
            }
            return
        }

        if reduceMotion {
            progress = 1
            withAnimation(.easeOut(duration: 0.2)) {
                showArrival = true
            }
            if presentation.isFirstArrival {
                celebrationTrigger += 1
            }
            guard !presentation.isFirstArrival else { return }
            try? await Task.sleep(for: .milliseconds(700))
            onComplete()
            return
        }

        withAnimation(.easeInOut(duration: 1.65)) {
            progress = 1
        }
        try? await Task.sleep(for: .milliseconds(1_650))
        withAnimation(.easeOut(duration: 0.24)) {
            showArrival = true
        }
        if presentation.isFirstArrival {
            celebrationTrigger += 1
        }
        guard !presentation.isFirstArrival else { return }
        try? await Task.sleep(for: .milliseconds(850))
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

    private var holdsArrivalForUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["UI_TEST_FLIGHT_HOLD"] == "1"
        #else
        false
        #endif
    }
}

private struct FlightArc: Shape {
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

private struct MovingClouds: View {
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
            }
        }
    }
}

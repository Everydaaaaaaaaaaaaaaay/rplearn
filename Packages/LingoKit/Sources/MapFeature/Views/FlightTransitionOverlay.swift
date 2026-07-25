import DesignSystem
import SwiftUI

struct FlightPresentation: Identifiable {
    let id = UUID()
    let fromRegionID: String
    let toRegionID: String
    let fromName: String
    let toName: String
    let serialNumber: String
}

struct FlightTransitionOverlay: View {
    let presentation: FlightPresentation
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

            VStack(spacing: DSSpacing.xl) {
                Spacer()
                HStack {
                    cityLabel(presentation.fromName, icon: "airplane.departure", opacity: 1 - progress * 0.65)
                    Spacer()
                    cityLabel(presentation.toName, icon: "airplane.arrival", opacity: 0.35 + progress * 0.65)
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
                            .position(quadraticPoint(t: progress, start: start, control: control, end: end))
                            .rotationEffect(.degrees(-12 + Double(progress) * 24))
                    }
                }
                .frame(height: 210)

                if showArrival {
                    VStack(spacing: DSSpacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                        Text("已抵达 \(presentation.toName)！")
                            .font(.largeTitle.bold())
                        Text("票根 \(presentation.serialNumber) 已收入票根夹")
                            .font(.subheadline)
                            .opacity(0.86)
                    }
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
                    .celebration(true, tint: .white, trigger: celebrationTrigger)
                } else {
                    VStack(spacing: DSSpacing.xs) {
                        Image(systemName: "ticket.fill")
                            .font(.title)
                        Text("LingoTrip Boarding Pass")
                            .font(.headline)
                        Text("\(presentation.fromName)  →  \(presentation.toName)")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.dsSkyDeep)
                    .padding(DSSpacing.lg)
                    .background(.white, in: RoundedRectangle(cornerRadius: DSRadius.card))
                    .rotationEffect(.degrees(-3 + Double(progress) * 6))
                    .offset(y: -progress * 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer()
            }
        }
        .task { await runAnimation() }
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
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) {
                progress = 1
                showArrival = true
            }
            celebrationTrigger += 1
            try? await Task.sleep(for: .milliseconds(550))
            onComplete()
            return
        }

        withAnimation(.easeInOut(duration: 1.75)) {
            progress = 1
        }
        try? await Task.sleep(for: .milliseconds(1_750))
        withAnimation(DSAnimation.pop) {
            showArrival = true
        }
        celebrationTrigger += 1
        try? await Task.sleep(for: .milliseconds(850))
        onComplete()
    }

    private func quadraticPoint(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let oneMinus = 1 - t
        return CGPoint(
            x: oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * end.x,
            y: oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * end.y
        )
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

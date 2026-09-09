import DesignSystem
import SwiftUI

/// 剧情目录共用的封面数据。业务页负责计算权限与进度，封面流只负责舞台呈现。
struct StoryCoverItem: Identifiable {
    let id: String
    let artworkName: String
    let sequenceText: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let statusText: String
    let statusIcon: String
    let accent: Color
    let isEnabled: Bool
    let isCompleted: Bool
    let isDimmed: Bool
}

/// 横向封面流：让主线与城市短篇共享同一套舞台、手势与无障碍行为。
struct StoryCoverFlow: View {
    let items: [StoryCoverItem]
    let preferredItemID: String?
    let accessibilityIdentifier: String
    let onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedID: String?
    @State private var hasEntered = false

    private var selectedIndex: Int {
        guard let selectedID,
              let index = items.firstIndex(where: { $0.id == selectedID })
        else { return 0 }
        return index
    }

    private var selectedItem: StoryCoverItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    private var itemIDs: [String] {
        items.map(\.id)
    }

    var body: some View {
        GeometryReader { proxy in
            let coverWidth = min(max(proxy.size.width * 0.68, 238), 326)
            let coverHeight = min(coverWidth * 1.43, max(260, proxy.size.height - 154))

            ZStack {
                StoryTheaterBackdrop(
                    accent: selectedItem?.accent ?? .dsFoilGold,
                    spotlightVisible: hasEntered,
                    reduceTransparency: reduceTransparency
                )

                VStack(spacing: 0) {
                    stageCounter
                        .padding(.top, 10)

                    Spacer(minLength: 8)

                    ZStack(alignment: .bottom) {
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        (selectedItem?.accent ?? .dsFoilGold).opacity(0.24),
                                        .clear,
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: coverWidth * 0.68
                                )
                            )
                            .frame(width: coverWidth * 1.5, height: 44)
                            .blur(radius: reduceTransparency ? 0 : 9)
                            .offset(y: 18)
                            .animation(reduceMotion ? nil : DSAnimation.scene, value: selectedID)
                            .accessibilityHidden(true)

                        coverScroll(
                            width: coverWidth,
                            height: coverHeight,
                            containerWidth: proxy.size.width
                        )
                    }
                    .frame(height: coverHeight + 64)

                    Spacer(minLength: 18)

                    stageStatus
                        .padding(.bottom, 18)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            synchronizeSelection()
            guard !hasEntered else { return }
            if reduceMotion {
                hasEntered = true
            } else {
                withAnimation(.easeOut(duration: 0.72)) {
                    hasEntered = true
                }
            }
        }
        .onChange(of: itemIDs) { _, _ in
            synchronizeSelection()
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private var stageCounter: some View {
        VStack(spacing: 7) {
            Capsule()
                .fill(Color(red: 0.95, green: 0.83, blue: 0.59).opacity(0.86))
                .frame(width: 42, height: 4)
                .shadow(color: Color(red: 1, green: 0.84, blue: 0.57).opacity(0.7), radius: 8)
                .accessibilityHidden(true)

            Text("第 \(padded(selectedIndex + 1)) 场  ·  共 \(padded(items.count)) 场")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.58))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : DSAnimation.snappy, value: selectedIndex)
                .accessibilityLabel("第 \(selectedIndex + 1) 场，共 \(items.count) 场")
        }
        .opacity(hasEntered ? 1 : 0)
    }

    private func coverScroll(width: CGFloat, height: CGFloat, containerWidth: CGFloat) -> some View {
        let shouldReduceMotion = reduceMotion
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    cover(item, width: width, height: height)
                        .id(item.id)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.84)
                                .rotation3DEffect(
                                    .degrees(shouldReduceMotion ? 0 : Double(phase.value) * -10),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.62
                                )
                                .offset(y: shouldReduceMotion || phase.isIdentity ? 0 : 24)
                                .opacity(shouldReduceMotion || phase.isIdentity ? 1 : 0.64)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, max(16, (containerWidth - width) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .opacity(hasEntered ? 1 : 0)
        .scaleEffect(hasEntered || reduceMotion ? 1 : 0.96)
        .offset(y: hasEntered || reduceMotion ? 0 : 20)
    }

    @ViewBuilder
    private func cover(_ item: StoryCoverItem, width: CGFloat, height: CGFloat) -> some View {
        if item.isEnabled {
            Button {
                onOpen(item.id)
            } label: {
                StoryPoster(item: item, width: width, height: height)
            }
            .buttonStyle(.pressableCard)
            .accessibilityIdentifier("story.chapter.\(item.id)")
            .accessibilityLabel("\(item.eyebrow)，\(item.title)，\(item.statusText)")
            .accessibilityHint("开展这一场剧情")
        } else {
            StoryPoster(item: item, width: width, height: height)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("story.chapter.\(item.id)")
                .accessibilityLabel("\(item.eyebrow)，\(item.title)，\(item.statusText)")
        }
    }

    private var stageStatus: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 38, height: 0.5)

            if let selectedItem {
                Image(systemName: selectedItem.statusIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(selectedItem.statusText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.5)
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 38, height: 0.5)
        }
        .foregroundStyle(.white.opacity(0.64))
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: selectedID)
        .opacity(hasEntered ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func synchronizeSelection() {
        guard !items.isEmpty else {
            selectedID = nil
            return
        }
        if let selectedID, itemIDs.contains(selectedID) { return }
        selectedID = preferredItemID.flatMap { itemIDs.contains($0) ? $0 : nil } ?? items[0].id
    }

    private func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

private struct StoryPoster: View {
    let item: StoryCoverItem
    let width: CGFloat
    let height: CGFloat

    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 29

    var body: some View {
        ZStack {
            Image(item.artworkName)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .saturation(item.isDimmed ? 0.18 : 0.9)
                .contrast(1.05)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.26), location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .black.opacity(0.18), location: 0.55),
                    .init(color: .black.opacity(0.94), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: height)

            if item.isDimmed {
                Color.black.opacity(0.28)
                    .frame(width: width, height: height)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(item.sequenceText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.86))

                    Spacer(minLength: 8)

                    Image(systemName: item.statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isDimmed ? .white.opacity(0.68) : item.accent)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.34), in: Circle())
                }

                Spacer(minLength: 20)

                Rectangle()
                    .fill(item.accent)
                    .frame(width: 28, height: 2)
                    .padding(.bottom, 11)

                Text(item.eyebrow)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(item.accent.opacity(item.isDimmed ? 0.66 : 1))
                    .lineLimit(1)

                Text(item.title)
                    .font(.system(size: titleSize, weight: .semibold, design: .serif))
                    .tracking(-0.7)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 6)

                Text(item.subtitle)
                    .font(.system(.footnote, design: .serif, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .padding(.top, 9)
            }
            .padding(20)
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .clipped()
        .background(Color(red: 0.035, green: 0.031, blue: 0.033))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.32), item.accent.opacity(0.28), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.74), radius: 24, y: 16)
        .shadow(color: item.accent.opacity(item.isDimmed ? 0 : 0.16), radius: 18, y: 8)
        .opacity(item.isDimmed ? 0.72 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

struct StoryTheaterBackdrop: View {
    let accent: Color
    let spotlightVisible: Bool
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.006, green: 0.006, blue: 0.008)

                Canvas { context, size in
                    drawCurtain(in: &context, size: size, leading: true)
                    drawCurtain(in: &context, size: size, leading: false)
                }
                .opacity(reduceTransparency ? 0.78 : 1)

                StorySpotlightShape()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 1, green: 0.88, blue: 0.66).opacity(0.18), location: 0),
                                .init(color: accent.opacity(0.055), location: 0.54),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: min(proxy.size.width * 1.18, 640), height: proxy.size.height * 0.84)
                    .blur(radius: reduceTransparency ? 0 : 12)
                    .offset(y: -34)
                    .blendMode(.screen)
                    .opacity(spotlightVisible ? 1 : 0)

                RadialGradient(
                    colors: [accent.opacity(0.11), .clear],
                    center: UnitPoint(x: 0.5, y: 0.54),
                    startRadius: 0,
                    endRadius: min(proxy.size.width, proxy.size.height) * 0.48
                )
                .blendMode(.screen)
                .opacity(spotlightVisible ? 1 : 0)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.16), .black.opacity(0.74)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawCurtain(in context: inout GraphicsContext, size: CGSize, leading: Bool) {
        let width = size.width * 0.31
        let outerX = leading ? 0.0 : size.width
        let innerTopX = leading ? width : size.width - width
        let innerBottomX = leading ? width * 0.72 : size.width - width * 0.72

        var curtain = Path()
        curtain.move(to: CGPoint(x: outerX, y: 0))
        curtain.addLine(to: CGPoint(x: innerTopX, y: 0))
        curtain.addCurve(
            to: CGPoint(x: innerBottomX, y: size.height),
            control1: CGPoint(x: leading ? width * 0.91 : size.width - width * 0.91, y: size.height * 0.3),
            control2: CGPoint(x: leading ? width * 0.65 : size.width - width * 0.65, y: size.height * 0.72)
        )
        curtain.addLine(to: CGPoint(x: outerX, y: size.height))
        curtain.closeSubpath()

        let start = CGPoint(x: leading ? 0 : size.width, y: 0)
        let end = CGPoint(x: leading ? width : size.width - width, y: 0)
        context.fill(
            curtain,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.025, green: 0.012, blue: 0.018),
                    Color(red: 0.11, green: 0.025, blue: 0.047),
                    Color(red: 0.028, green: 0.01, blue: 0.017),
                ]),
                startPoint: start,
                endPoint: end
            )
        )

        for fold in 1...5 {
            let fraction = CGFloat(fold) / 6
            let topX = leading ? width * fraction : size.width - width * fraction
            let bottomInset = width * (0.1 + fraction * 0.54)
            let bottomX = leading ? bottomInset : size.width - bottomInset
            var foldPath = Path()
            foldPath.move(to: CGPoint(x: topX, y: 0))
            foldPath.addCurve(
                to: CGPoint(x: bottomX, y: size.height),
                control1: CGPoint(x: topX, y: size.height * 0.34),
                control2: CGPoint(x: bottomX, y: size.height * 0.7)
            )
            context.stroke(
                foldPath,
                with: .color(.white.opacity(fold.isMultiple(of: 2) ? 0.035 : 0.018)),
                lineWidth: 1
            )
        }
    }
}

private struct StorySpotlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 16, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 16, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

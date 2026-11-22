import CoreKit
import DesignSystem
import DomainKit
import SwiftUI

/// 剧情目录共用的封面数据。业务页负责计算权限与进度，封面流只负责呈现。
struct StoryCoverItem: Identifiable {
    let id: String
    /// 封面上的卡通城市街景。
    let regionID: String
    let sequenceText: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let statusText: String
    let statusIcon: String
    let candy: PuffCandy
    let isEnabled: Bool
    let isCompleted: Bool
    let isDimmed: Bool
}

/// 横向封面流：主线与城市短篇共用的白底卡片流，封面上半是章节城市的卡通街景。
struct StoryCoverFlow: View {
    let items: [StoryCoverItem]
    let preferredItemID: String?
    let accessibilityIdentifier: String
    let onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            let coverWidth = min(max(proxy.size.width * 0.7, 238), 330)
            let coverHeight = min(coverWidth * 1.4, max(300, proxy.size.height - 120))

            VStack(spacing: 0) {
                stageCounter
                    .padding(.top, 10)
                Spacer(minLength: 8)
                coverScroll(
                    width: coverWidth,
                    height: coverHeight,
                    containerWidth: proxy.size.width
                )
                .frame(height: coverHeight + 24)
                Spacer(minLength: 18)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background { PuffPageBackdrop() }
        .task(id: selectedItem?.isEnabled == true ? selectedItem?.id : nil, priority: .utility) {
            guard let item = selectedItem, item.isEnabled else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            let readingID = DepartureStoryIdentity.readingEditions(for: item.id).last ?? item.id
            await DownloadableContent.prefetchOpening(readingID)
        }
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
        Text("第 \(padded(selectedIndex + 1)) 场 · 共 \(padded(items.count)) 场")
            .font(.puff(.caption, Puff.Weight.label))
            .foregroundStyle(Puff.Palette.inkSoft)
            .monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Puff.Palette.cloud, in: Capsule())
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : Puff.Motion.bouncy, value: selectedIndex)
            .accessibilityLabel("第 \(selectedIndex + 1) 场，共 \(items.count) 场")
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
                                .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.88)
                                .rotationEffect(.degrees(shouldReduceMotion ? 0 : Double(phase.value) * 4))
                                .offset(y: shouldReduceMotion || phase.isIdentity ? 0 : 18)
                                .opacity(shouldReduceMotion || phase.isIdentity ? 1 : 0.7)
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
        let isSelected = item.id == selectedID
        if item.isEnabled {
            Button {
                onOpen(item.id)
            } label: {
                StoryPoster(item: item, width: width, height: height, isSelected: isSelected)
            }
            .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.huge))
            .accessibilityIdentifier("story.chapter.\(item.id)")
            .accessibilityLabel("\(item.eyebrow)，\(item.title)，\(item.statusText)")
            .accessibilityHint("开展这一场剧情")
        } else {
            StoryPoster(item: item, width: width, height: height, isSelected: isSelected)
                .puffCard(radius: Puff.Radius.huge)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("story.chapter.\(item.id)")
                .accessibilityLabel("\(item.eyebrow)，\(item.title)，\(item.statusText)")
        }
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

/// 白色厚卡片封面：上半是章节城市的卡通街景，下半是城市、标题和状态。未解锁的章节街景褪色。
private struct StoryPoster: View {
    let item: StoryCoverItem
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PuffCityScene(regionID: item.regionID, viewport: .west, isActive: isSelected && !item.isDimmed)
                .frame(height: height * 0.5)
                .saturation(item.isDimmed ? 0.12 : 1)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text(item.sequenceText)
                        .font(.puff(.caption, Puff.Weight.emphasis))
                        .monospacedDigit()
                        .foregroundStyle(Puff.Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Puff.Palette.card, in: Capsule())
                        .padding(10)
                }
                .padding([.horizontal, .top], 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.eyebrow)
                    .font(.puff(.subheadline, Puff.Weight.emphasis))
                    .foregroundStyle(item.isDimmed ? Puff.Palette.inkFaint : item.candy.deep)
                    .lineLimit(1)
                Text(item.title)
                    .font(.puff(.title2, Puff.Weight.title))
                    .foregroundStyle(Puff.Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(item.subtitle)
                    .font(.puff(.footnote, Puff.Weight.body))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .lineLimit(2)
                Spacer(minLength: 0)
                PuffTag(item.statusText, systemImage: item.statusIcon,
                        candy: item.isDimmed ? .grape : item.isCompleted ? .mint : item.candy)
            }
            .multilineTextAlignment(.leading)
            .padding(Puff.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, height: height)
        .opacity(item.isDimmed ? 0.78 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Puff.Radius.huge, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

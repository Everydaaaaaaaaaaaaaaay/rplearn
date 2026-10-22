import BackendKit
import DesignSystem
import SwiftUI

/// Kept outside the per-question ScrollView so reading and answering have
/// independent positions. Changing a question never recreates this reader.
struct LearningReadingPane: View {
    let plan: LearningReadingPlan
    let question: LearningQuestion
    let pictures: LearningImageModel
    let height: CGFloat
    let keyboardFocused: Bool
    let dismissKeyboard: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedID: String?
    @State private var assignedSectionID: String?
    @State private var positions: [String: CGFloat] = [:]
    @State private var expanded = true
    @State private var showsReader = false
    @State private var showsOriginal = false
    @State private var showsInstructions = false

    private var section: LearningReadingPlan.Section? {
        plan.sections.first { $0.id == selectedID } ?? plan.sections.first
    }
    private var canPreview: Bool { !typeSize.isAccessibilitySize && verticalSizeClass != .compact }
    private var showsImages: Bool { selectedID == "images" }
    private var selectionKey: String { showsImages ? "images" : (section?.id ?? "whole") }
    private var title: String { showsImages ? "题目图片" : (section?.title ?? "阅读材料") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    dismissKeyboard()
                    if canPreview { expanded.toggle() } else { showsReader = true }
                } label: {
                    Label(expanded && canPreview ? "收起材料" : "阅读材料", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("learning.material.toggle")
                Spacer(minLength: 0)
                if plan.sections.count > 1 || showsImages {
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !plan.introduction.isEmpty {
                    Button {
                        dismissKeyboard(); showsOriginal = false; showsInstructions = true; showsReader = true
                    } label: {
                        Image(systemName: "info.circle").frame(width: 44, height: 44)
                    }.accessibilityLabel("查看作答说明")
                }
                Button {
                    dismissKeyboard(); showsOriginal = false; showsInstructions = false; showsReader = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }.accessibilityLabel("展开阅读材料")
                    .accessibilityIdentifier("learning.material.expand")
            }
            if expanded && canPreview {
                sectionPicker
                RememberedReadingScroll(location: "inline." + selectionKey, offsets: $positions) {
                    readingContent(fullScreen: false)
                        .padding(.vertical, 10)
                }
                .id(selectionKey)
                .frame(height: height)
                .accessibilityIdentifier("learning.material.reader")
                .overlay(alignment: .bottom) { Divider().accessibilityHidden(true) }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 728).frame(maxWidth: .infinity)
        .background(Color.dsSurface)
        .onChange(of: question.id, initial: true) { _, _ in
            // Explicit article ownership advances the reader. Cross-text questions
            // retain the article the learner chose, without guessing an answer.
            if let preferred = plan.preferredSectionID, preferred != assignedSectionID {
                selectedID = preferred
                expanded = true
            } else if selectedID == nil { selectedID = plan.sections.first?.id }
            assignedSectionID = plan.preferredSectionID
        }
        .onChange(of: keyboardFocused) { _, focused in if focused { expanded = false } }
        .sheet(isPresented: $showsReader, onDismiss: { showsOriginal = false }) {
            NavigationStack {
                VStack(spacing: 0) {
                    if !showsOriginal { sectionPicker.padding(.horizontal, 20) }
                    RememberedReadingScroll(location: "expanded." + (showsOriginal ? "original" : selectionKey), offsets: $positions) {
                        VStack(alignment: .leading, spacing: 18) {
                            if !showsOriginal && !plan.introduction.isEmpty {
                                DisclosureGroup("作答说明", isExpanded: $showsInstructions) {
                                    Text(plan.introduction).font(.body).lineSpacing(6).textSelection(.enabled)
                                }
                            }
                            readingContent(fullScreen: true)
                        }.padding(24).frame(maxWidth: 728).frame(maxWidth: .infinity)
                    }.id(showsOriginal ? "original" : selectionKey)
                }
                .background(Color.dsBackground)
                .navigationTitle(showsOriginal ? "完整材料" : title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(showsOriginal ? "分篇阅读" : "完整材料") { showsOriginal.toggle() }
                            .accessibilityIdentifier("learning.material.original")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("返回答题") { showsReader = false }
                            .accessibilityIdentifier("learning.material.done")
                    }
                }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder private var sectionPicker: some View {
        if plan.sections.count > 1 || !(question.materialImages ?? []).isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(plan.sections) { item in
                        Button { selectedID = item.id } label: {
                            Text(item.id == "whole" ? "正文" : (item.id.hasPrefix("candidate.") ? item.title : item.id)).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(!showsImages && section?.id == item.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityLabel(item.title)
                            .accessibilityAddTraits(!showsImages && section?.id == item.id ? [.isSelected] : [])
                            .accessibilityIdentifier("learning.material.section.\(item.id)")
                    }
                    if let assets = question.materialImages, !assets.isEmpty {
                        Button { selectedID = "images" } label: {
                            Label("图片 · \(assets.count)", systemImage: "photo")
                                .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                                .background(showsImages ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityLabel("查看题目图片，共 \(assets.count) 张")
                            .accessibilityAddTraits(showsImages ? [.isSelected] : [])
                            .accessibilityIdentifier("learning.material.images")
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func readingContent(fullScreen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let section, !showsImages, !showsOriginal, plan.sections.count > 1 {
                Text(section.title).font(.headline).accessibilityAddTraits(.isHeader)
            }
            if !showsImages || showsOriginal {
                LearningGroupMaterial(text: showsOriginal ? plan.originalText : (section?.text ?? plan.originalText))
            }
            if (showsImages || showsOriginal), let assets = question.materialImages, !assets.isEmpty {
                Text("题目图片 · \(assets.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                // The legacy payload has no image-to-article ownership. Keep every
                // required figure available, rather than infer from its caption.
                ForEach(Array(assets.enumerated()), id: \.element.assetId) { index, asset in
                    if let image = pictures.images[asset.assetId] {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: fullScreen ? nil : 180)
                            .accessibilityLabel(asset.label)
                        Text("图片 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A stable content key owns the offset, including while another article is on
/// screen. Unlike visible-item IDs, an explicit offset survives replacing the
/// entire article and does not depend on which nested paragraph was visible.
private struct RememberedReadingScroll<Content: View>: View {
    let location: String
    @Binding var offsets: [String: CGFloat]
    let initialOffset: CGFloat
    let content: Content
    @State private var position: ScrollPosition

    init(location: String, offsets: Binding<[String: CGFloat]>, @ViewBuilder content: () -> Content) {
        self.location = location
        _offsets = offsets
        initialOffset = offsets.wrappedValue[location] ?? 0
        _position = State(initialValue: ScrollPosition(y: initialOffset))
        self.content = content()
    }

    var body: some View {
        ScrollView { content }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                offsets[location] = offset
            }
            .onAppear { position.scrollTo(y: initialOffset) }
    }
}

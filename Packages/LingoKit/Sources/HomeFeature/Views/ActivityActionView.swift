import DesignSystem
import SwiftUI

/// Lightweight authored interaction over the unchanged scene. No network wait,
/// implied player voice, currency side effects or invented NPC relationships.
struct ActivityActionView: View {
    let activity: SceneActivity
    let isVisible: Bool
    let onBack: () -> Void
    let onComplete: ([Int], UUID) throws -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runID = UUID()
    @State private var hasStarted = false
    @State private var stepIndex = 0
    @State private var selections: [Int] = []
    @State private var selected: Int?
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var contentHeight: CGFloat = 0
    @AccessibilityFocusState private var focusHeading: Bool

    private var atSummary: Bool { stepIndex == activity.steps.count }
    private var ink: Color { Color(red: 0.10, green: 0.18, blue: 0.17) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.24).ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44)
                        }.accessibilityLabel("返回场景").accessibilityIdentifier("activities.action.back")
                        Text(activity.title).font(.headline)
                        Spacer()
                        Text(atSummary ? "回望" : hasStarted ? "\(stepIndex + 1) / \(activity.steps.count)" : "情境练习")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.dsHologramIvory)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    Spacer(minLength: 12)
                    ScrollView {
                        panelContent
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if abs(contentHeight - height) > 0.5 { contentHeight = height }
                            }
                    }
                    .id("\(hasStarted)-\(stepIndex)")
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(contentHeight > 0 ? contentHeight : proxy.size.height * 0.70,
                                       proxy.size.height * 0.70))
                    .background(panelBackground)
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, max(proxy.safeAreaInsets.top, 54) + 8)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 24) + 82)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(ink)
        .animation(DSSceneTransition.animation(reduceMotion: reduceMotion), value: stepIndex)
        .animation(DSSceneTransition.animation(reduceMotion: reduceMotion), value: hasStarted)
        .onChange(of: stepIndex) { _, _ in focusHeading = true }
        .onChange(of: hasStarted) { _, _ in focusHeading = true }
        .allowsHitTesting(isVisible)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            content.id("\(hasStarted)-\(stepIndex)").transition(.opacity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(red: 0.98, green: 0.965, blue: 0.91).opacity(0.94))
    }

    @ViewBuilder private var content: some View {
        if !hasStarted {
            Label(activity.scene.title, systemImage: activity.symbol).font(.caption.weight(.semibold))
            Text(activity.title).font(.largeTitle.weight(.semibold)).accessibilityFocused($focusHeading)
            Text(activity.introduction).font(.body).lineSpacing(5)
            Text("两次选择 · 随时可以退出 · 不消耗金币")
                .font(.caption).foregroundStyle(ink.opacity(0.65))
            primary("开始这一刻", id: "activities.action.start") { hasStarted = true }
        } else if atSummary {
            Text(saved ? "这一刻，已记下" : "这一刻，你的选择")
                .font(.title2.weight(.semibold)).accessibilityFocused($focusHeading)
            Text(activity.closing).font(.body).lineSpacing(4)
            Divider()
            ForEach(Array(selections.enumerated()), id: \.offset) { index, choiceIndex in
                let step = activity.steps[index]
                let choice = step.choices[choiceIndex]
                VStack(alignment: .leading, spacing: 7) {
                    Text(step.question).font(.caption).foregroundStyle(ink.opacity(0.65))
                    Text(choice.english).font(.system(.body, design: .serif).weight(.medium))
                    Text(choice.chinese).font(.subheadline)
                }
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            if saved {
                Text("已保存到本机的行动足迹").font(.caption).accessibilityIdentifier("activities.action.saved")
                primary("回到场景", id: "activities.action.return", action: onBack)
            } else {
                primary("完成并记录", id: "activities.action.finish") {
                    guard !saved else { return }
                    do {
                        try onComplete(selections, runID)
                        errorMessage = nil
                        saved = true
                    } catch {
                        errorMessage = "未能保存，原有记录未改动。你可以重试，或返回场景。"
                    }
                }
            }
        } else {
            let step = activity.steps[stepIndex]
            Text(step.context).font(.subheadline).foregroundStyle(ink.opacity(0.75)).lineSpacing(4)
            Text(step.question).font(.title2.weight(.semibold)).accessibilityFocused($focusHeading)
            ForEach(Array(step.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    guard selected == nil else { return }
                    selected = index
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(choice.english).font(.body.weight(.medium))
                            Spacer(minLength: 4)
                            Image(systemName: selected == index ? "checkmark.circle.fill" : "circle")
                        }
                        Text(choice.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.7))
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ink.opacity(selected == index ? 0.13 : 0.045), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activities.choice.\(index)")
                .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
            if let selected {
                Text(step.choices[selected].response).font(.subheadline).lineSpacing(4)
                    .accessibilityIdentifier("activities.action.feedback")
                primary(stepIndex + 1 == activity.steps.count ? "回看这一刻" : "继续", id: "activities.action.next") {
                    guard self.selected == selected, selections.count == stepIndex else { return }
                    selections.append(selected)
                    self.selected = nil
                    stepIndex += 1
                }
            }
        }
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.headline).padding(18).frame(maxWidth: .infinity)
                .foregroundStyle(Color.dsHologramIvory)
                .background(ink, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
        .accessibilityIdentifier(id)
    }
}

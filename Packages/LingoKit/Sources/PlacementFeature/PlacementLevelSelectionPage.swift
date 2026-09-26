import CoreKit
import DesignSystem
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

struct DifficultyLevelSelectionPage: View {
    @Binding var selection: DifficultyLevel
    let currentLevel: DifficultyLevel
    let recommendedLevel: DifficultyLevel?
    let onDone: () -> Void

    private let groups: [(String, [DifficultyLevel])] = [
        ("启蒙", [.kindergarten]),
        ("小学", [.primary1, .primary2, .primary3, .primary4, .primary5, .primary6]),
        ("初中", [.junior1, .junior2, .junior3]),
        ("高中", [.senior1, .senior2, .senior3]),
        ("大学与进阶", [.undergraduate, .postgraduate, .advanced]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("选择适合你的对话难度")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.dsPaperInk)
                        .shadow(color: Color.dsBrandCream.opacity(0.98), radius: 5)
                        .shadow(color: Color.white.opacity(0.72), radius: 1)
                    Text("选择后会先说明切换的影响，确认才会生效。")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: Color.dsBrandCream.opacity(0.98), radius: 5)
                        .shadow(color: Color.dsBrandCream.opacity(0.88), radius: 2)
                }

                ForEach(groups, id: \.0) { title, levels in
                    levelGroup(title: title, levels: levels)
                }
            }
            .frame(maxWidth: 560)
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .placementScrollEdgeBlend()
        .placementBottomBar {
            DSWorkbenchPaperSheet(radius: 22, padding: DSSpacing.sm) {
                VStack(spacing: 4) {
                    Text("已选择：\(selection.displayName)")
                        .font(.caption)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                    Button("完成") { onDone() }
                        .buttonStyle(.dsWorkbenchAction)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.xs)
        }
    }

    private func levelGroup(title: String, levels: [DifficultyLevel]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.dsPaperInkSecondary)
                .padding(.leading, DSSpacing.xs)

            VStack(spacing: 4) {
                ForEach(levels, id: \.rawValue) { level in
                    levelRow(level)
                }
            }
            .placementPaperPanel(padding: 4)
        }
    }

    private func levelRow(_ level: DifficultyLevel) -> some View {
        let isSelected = level == selection
        return Button {
            selection = level
            Haptics.impact(.light)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.dsPaperInk)
                    Text(level.cseReference)
                        .font(.caption)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                }
                Spacer(minLength: DSSpacing.xs)
                if level == currentLevel {
                    levelBadge("当前", color: .dsPaperInkSecondary)
                }
                if level == recommendedLevel {
                    levelBadge("建议", color: .dsSkyDeep)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.dsSky : Color.dsBorder)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                isSelected ? Color.dsSky.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("placement.level.\(level.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func levelBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }
}

extension View {
    @ViewBuilder
    func placementTopBar<Bar: View>(
        @ViewBuilder content: () -> Bar
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            VStack(spacing: 0) {
                content()
                self
            }
        }
    }

    @ViewBuilder
    func placementBottomBar<Bar: View>(
        @ViewBuilder content: () -> Bar
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            VStack(spacing: 0) {
                self
                content()
            }
        }
    }

    @ViewBuilder
    func placementScrollEdgeBlend() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }

    func placementPaperPanel(
        padding: CGFloat = DSSpacing.md,
        weight _: DSWorkbenchPanelWeight = .reading
    ) -> some View {
        DSWorkbenchPaperSheet(
            radius: DSRadius.card,
            padding: padding
        ) {
            self
        }
    }
}

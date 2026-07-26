import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 自绘内容、原生 sheet 行为的统一模态对话框配置。
public struct DSModalDialogConfiguration: Sendable, Equatable {
    public enum Tone: Sendable, Equatable {
        case info
        case warning
        case danger
        case success
    }

    public enum ActionRole: Sendable, Equatable {
        case standard
        case cancel
        case destructive
    }

    public let eyebrow: String
    public let title: String
    public let message: String
    public let icon: String
    public let tone: Tone
    public let primaryTitle: String
    public let primaryIcon: String?
    public let primaryRole: ActionRole
    public let secondaryTitle: String?
    public let secondaryIcon: String?
    public let allowsInteractiveDismiss: Bool

    public init(
        eyebrow: String,
        title: String,
        message: String,
        icon: String,
        tone: Tone,
        primaryTitle: String,
        primaryIcon: String? = nil,
        primaryRole: ActionRole = .standard,
        secondaryTitle: String? = "取消",
        secondaryIcon: String? = nil,
        allowsInteractiveDismiss: Bool = true
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.icon = icon
        self.tone = tone
        self.primaryTitle = primaryTitle
        self.primaryIcon = primaryIcon
        self.primaryRole = primaryRole
        self.secondaryTitle = secondaryTitle
        self.secondaryIcon = secondaryIcon
        self.allowsInteractiveDismiss = allowsInteractiveDismiss
    }
}

public extension View {
    /// 使用系统 sheet 管理模态行为，仅自绘内容与按钮；动作在 sheet 完成关闭后执行。
    func dsModalDialog(
        isPresented: Binding<Bool>,
        configuration: DSModalDialogConfiguration,
        onPrimary: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            DSModalDialogModifier(
                isPresented: isPresented,
                configuration: configuration,
                onPrimary: onPrimary,
                onCancel: onCancel
            )
        )
    }
}

private struct DSModalDialogModifier: ViewModifier {
    private enum PendingAction {
        case primary
        case cancel
    }

    @Binding var isPresented: Bool
    let configuration: DSModalDialogConfiguration
    let onPrimary: () -> Void
    let onCancel: () -> Void

    @State private var pendingAction: PendingAction?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: performPendingAction) {
            DSModalDialogView(
                configuration: configuration,
                onPrimary: { select(.primary) },
                onCancel: { select(.cancel) }
            )
        }
    }

    private func select(_ action: PendingAction) {
        switch action {
        case .primary where configuration.primaryRole == .destructive:
            #if canImport(UIKit)
            Haptics.notify(.warning)
            #endif
        case .primary:
            Haptics.impact(.medium)
        case .cancel:
            Haptics.impact(.light)
        }
        pendingAction = action
        isPresented = false
    }

    private func performPendingAction() {
        let action = pendingAction
        pendingAction = nil
        switch action {
        case .primary:
            onPrimary()
        case .cancel:
            onCancel()
        case nil:
            // 系统手势、辅助功能 Escape 与外部状态关闭都等价于取消。
            onCancel()
        }
    }
}

private struct DSModalDialogView: View {
    let configuration: DSModalDialogConfiguration
    let onPrimary: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var tint: Color {
        switch configuration.tone {
        case .info: .dsSky
        case .warning: .dsSunset
        case .danger: .dsDanger
        case .success: .dsSuccess
        }
    }

    private var detents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact {
            return [.large]
        }
        return [.height(configuration.secondaryTitle == nil ? 304 : 356)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                header
                actions
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.md)
        }
        .scrollIndicators(.hidden)
        .presentationDetents(detents)
        .presentationDragIndicator(configuration.allowsInteractiveDismiss ? .visible : .hidden)
        .presentationCornerRadius(DSRadius.hero)
        .presentationBackground(Color.dsSurface)
        .interactiveDismissDisabled(!configuration.allowsInteractiveDismiss)
        .accessibilityAction(.escape) {
            guard configuration.allowsInteractiveDismiss else { return }
            onCancel()
        }
    }

    private var header: some View {
        VStack(spacing: DSSpacing.xs) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.11))
                    .frame(width: 58, height: 58)
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 1)
                    .frame(width: 58, height: 58)
                Image(systemName: configuration.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            Text(configuration.eyebrow)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)

            Text(configuration.title)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(configuration.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }

    private var actions: some View {
        VStack(spacing: DSSpacing.sm) {
            Button(role: buttonRole, action: onPrimary) {
                actionLabel(configuration.primaryTitle, icon: configuration.primaryIcon)
            }
            .buttonStyle(.dsAction(.tinted(tint)))

            if let secondaryTitle = configuration.secondaryTitle {
                Button(role: .cancel, action: onCancel) {
                    actionLabel(secondaryTitle, icon: configuration.secondaryIcon)
                }
                .buttonStyle(.dsAction(.secondary))
            }
        }
    }

    private var buttonRole: ButtonRole? {
        switch configuration.primaryRole {
        case .standard: nil
        case .cancel: .cancel
        case .destructive: .destructive
        }
    }

    private func actionLabel(_ title: String, icon: String?) -> some View {
        HStack(spacing: DSSpacing.xs) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
    }
}

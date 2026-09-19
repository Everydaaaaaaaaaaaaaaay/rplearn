import SwiftUI

/// Shared nonblocking feedback: SF Symbols, adaptive colors, two seconds on screen.
public struct DSQuickNotice: Identifiable, Equatable, Sendable {
    public enum Symbol: String, Sendable {
        case finishPractice = "bubble.left.and.text.bubble.right"
        case protectedFriend = "person.crop.circle.badge.checkmark"
    }
    public let id = UUID()
    public let text: String
    public let symbol: Symbol
    public init(_ text: String, symbol: Symbol) { self.text = text; self.symbol = symbol }
}

private struct QuickNoticeModifier: ViewModifier {
    @Binding var notice: DSQuickNotice?
    func body(content: Content) -> some View {
        content.overlay {
            if let notice {
                VStack(spacing: 14) {
                    Image(systemName: notice.symbol.rawValue)
                        .font(.system(size: 30, weight: .regular))
                    Text(notice.text).font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .padding(24).frame(maxWidth: 230)
                .foregroundStyle(.primary)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.1), radius: 16, y: 5)
                .transition(.opacity).id(notice.id)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quickNotice")
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
        .task(id: notice?.id) {
            guard let current = notice else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if notice?.id == current.id { notice = nil }
        }
    }
}

public extension View {
    func dsQuickNotice(_ notice: Binding<DSQuickNotice?>) -> some View {
        modifier(QuickNoticeModifier(notice: notice))
    }
}

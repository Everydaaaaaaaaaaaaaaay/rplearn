import DesignSystem
import SwiftUI

enum AppointmentStyle {
    static let ink = Color.dsTravelNavy
    static let canvas = Color(red: 0.985, green: 0.98, blue: 0.965)
}

struct AppointmentPage<Content: View>: View {
    let cityID: String
    let cityName: String
    var title = ""
    var backLabel = "返回"
    var onBack: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            AppointmentPhotoView(cityID: cityID, cityName: cityName, paused: true,
                                 showsControls: false, showsPlaceholder: false)
                .frame(height: 148).clipped()
                .overlay(alignment: .bottom) {
                    HStack(spacing: 12) {
                        AppointmentBackButton(label: backLabel, onBack: onBack)
                        if !title.isEmpty { Text(title).font(.subheadline.weight(.medium)) }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppointmentStyle.canvas).foregroundStyle(AppointmentStyle.ink).tint(AppointmentStyle.ink)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

struct AppointmentSectionDivider: View {
    var body: some View {
        Rectangle().fill(AppointmentStyle.ink.opacity(0.09)).frame(height: 0.5).padding(.vertical, 22)
    }
}

struct AppointmentBackButton: View {
    var label = "返回"
    var onBack: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let onBack { onBack() } else { dismiss() }
        } label: {
            Image(systemName: "chevron.left").font(.system(size: 22, weight: .regular))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("appointment.back")
    }
}


struct AppointmentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(AppointmentStyle.ink.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

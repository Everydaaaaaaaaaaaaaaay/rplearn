import DesignSystem
import SwiftUI

enum AppointmentStyle {
    static let ink = Color.dsTravelNavy
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.97)
}

struct AppointmentBackdrop: View {
    let cityID: String
    let cityName: String

    var body: some View {
        AppointmentPhotoView(cityID: cityID, cityName: cityName, paused: true, showsControls: false)
            .blur(radius: 14, opaque: true)
            .overlay(.white.opacity(0.30))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct AppointmentSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                if reduceTransparency || contrast == .increased {
                    shape.fill(AppointmentStyle.canvas)
                } else {
                    shape.fill(.regularMaterial).environment(\.colorScheme, .light)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.65)))
    }
}

private struct AppointmentChrome: ViewModifier {
    let cityID: String
    let cityName: String

    func body(content: Content) -> some View {
        content
            .background { AppointmentBackdrop(cityID: cityID, cityName: cityName) }
            .foregroundStyle(AppointmentStyle.ink)
            .tint(AppointmentStyle.ink)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
    }
}

extension View {
    func appointmentSurface(radius: CGFloat = 28) -> some View {
        modifier(AppointmentSurface(radius: radius))
    }

    func appointmentChrome(cityID: String, cityName: String) -> some View {
        modifier(AppointmentChrome(cityID: cityID, cityName: cityName))
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

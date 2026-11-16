import BackendKit
import DesignSystem
import SwiftUI

extension ChatView {
    var appointmentBanner: some View {
        HStack(spacing: 12) {
            if let item = viewModel.appointments.first {
                Button { deps.onOpenAppointment?(item.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar").font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayTitle(companionName: viewModel.character.displayName)).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(AppointmentDisplayTime.beijing(item.startsAt)).font(.caption)
                            Text(AppointmentDisplayTime.local(item.startsAt, city: item.cityName, timeZone: item.timeZone))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("chat.appointment")
                Menu {
                    Button("整理聊天中的约定") { Task { await viewModel.refreshAppointments(detect: true) } }
                    Button("全部约定") { deps.onOpenAppointment?(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("约定选项")
            } else {
                Image(systemName: "calendar")
                Text(viewModel.appointmentNotice ?? "聊好时间地点，就可以记下约定。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(viewModel.checkingAppointments ? "整理中…" : "整理约定") {
                    Task { await viewModel.refreshAppointments(detect: true) }
                }.font(.caption.weight(.semibold)).disabled(viewModel.checkingAppointments)
                    .accessibilityIdentifier("chat.detectAppointment")
            }
        }.padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.dsSurface).overlay(alignment: .bottom) { Divider() }
    }

}

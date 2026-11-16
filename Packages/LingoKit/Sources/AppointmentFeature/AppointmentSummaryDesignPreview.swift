#if DEBUG
import BackendKit
import DesignSystem
import SwiftUI

/// Native design preview backed by the isolated appointment fixture.
public struct AppointmentSummaryDesignPreview: View {
    private let onClose: () -> Void
    private let ink = AppointmentStyle.ink
    private let paper = Color(red: 0.985, green: 0.98, blue: 0.965)
    @State private var detail: BackendAppointmentDetail?
    @State private var error: String?
    @State private var history = false
    @State private var memory = false

    public init(onClose: @escaping () -> Void) { self.onClose = onClose }

    public var body: some View {
        VStack(spacing: 0) {
            AppointmentPhotoView(cityID: "london", cityName: "伦敦", paused: true, showsControls: false)
                .frame(height: 148).clipped()
                .overlay(alignment: .bottom) {
                    HStack(spacing: 12) {
                        AppointmentBackButton(onBack: onClose)
                        Text("回顾").font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            ScrollView {
                if let detail, let summary = detail.summary {
                    VStack(alignment: .leading, spacing: 0) {
                        identity(detail.appointment)
                        sectionDivider
                        relationship(summary)
                        sectionDivider
                        choices(detail)
                        sectionDivider
                        memories(summary)
                        Button { history = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("回看完整经历")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12))
                            }.font(.system(size: 15, weight: .medium)).frame(minHeight: 48)
                        }.buttonStyle(.plain).padding(.top, 12)
                        Button(action: onClose) { Text("返回聊天") }
                            .buttonStyle(AppointmentPrimaryButtonStyle()).padding(.top, 12)
                    }
                    .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .center)
                } else if let error {
                    AppointmentErrorView(message: error, loading: false) { Task { await load() } }.padding(24)
                } else { ProgressView().padding(40) }
            }.scrollBounceBehavior(.basedOnSize)
        }
        .background(paper).foregroundStyle(ink).tint(ink)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .task { await load() }
        .sheet(isPresented: $history) { AppointmentHistoryView(detail: detail, characterName: { _ in "Oliver" }) }
        .sheet(isPresented: $memory) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let summary = detail?.summary { memories(summary, showsManagement: false) }
                    }.padding(24)
                }
                .background(paper).foregroundStyle(ink)
                .appointmentNavigation("共同记忆")
            }.tint(ink)
        }
    }

    private func identity(_ item: BackendAppointment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                AvatarBadge(name: "Oliver", size: 48, imageName: "avatar_oliver")
                    .accessibilityIdentifier("appointment.design.avatar")
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayTitle(companionName: "Oliver"))
                        .font(.system(size: 22, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("appointment.design.title")
                    Label(item.placeName, systemImage: "mappin")
                        .font(.system(size: 13)).foregroundStyle(ink.opacity(0.6))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 13))
                Text(AppointmentDisplayTime.beijing(item.startsAt)).font(.system(size: 13))
                Spacer(minLength: 4)
                Text(AppointmentDisplayTime.local(item.startsAt, city: item.cityName, timeZone: item.timeZone))
                    .font(.system(size: 12)).foregroundStyle(ink.opacity(0.55))
            }.foregroundStyle(ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func relationship(_ summary: BackendAppointmentSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(red: 0.65, green: 0.32, blue: 0.40))
                .frame(width: 38, height: 38)
                .background(Color(red: 0.65, green: 0.32, blue: 0.40).opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("好感 \(summary.affinity.delta?.formatted(.number.sign(strategy: .always())) ?? "待结算")")
                        .font(.system(size: 18, weight: .semibold))
                        .accessibilityIdentifier("appointment.design.affinity")
                    Spacer()
                    if let before = summary.affinity.before, let after = summary.affinity.after {
                        Text("\(before.formatted()) → \(after.formatted())")
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(ink.opacity(0.5))
                    }
                }
                Text(summary.affinity.reason).font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choices(_ detail: BackendAppointmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("你的选择", systemImage: "arrow.turn.down.right")
                .font(.system(size: 16, weight: .semibold))
            ForEach(detail.session?.decisions ?? []) { decision in
                HStack(alignment: .top, spacing: 12) {
                    UserAvatar(name: "你", size: 26)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(decision.input).font(.system(size: 16, weight: .medium)).lineSpacing(3)
                        Text(decision.outcome).font(.system(size: 14)).lineSpacing(3)
                            .foregroundStyle(ink.opacity(0.65))
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func memories(_ summary: BackendAppointmentSummary, showsManagement: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("共同记忆", systemImage: "bookmark")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Label("已保存", systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(ink.opacity(0.5))
            }
            ForEach(summary.memories) { value in
                Text(value.content).font(.system(size: 15)).lineSpacing(4)
                    .foregroundStyle(ink.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
            if showsManagement {
                Button { memory = true } label: {
                    HStack(spacing: 6) {
                        Text("管理记忆")
                        Image(systemName: "arrow.up.right").font(.system(size: 11))
                    }.font(.system(size: 13, weight: .medium)).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle().fill(ink.opacity(0.09)).frame(height: 0.5).padding(.vertical, 22)
    }

    private func load() async {
        do {
            let service = AppointmentPreviewService(scenario: "confirmed")
            let id = AppointmentListView.previewAppointmentID
            let started = try await service.appointmentCommand(id, action: .start,
                request: .init(commandId: UUID(), expectedRevision: 0))
            let continued = try await service.appointmentCommand(id, action: .choice,
                request: .init(commandId: UUID(), expectedRevision: started.appointment.revision,
                               input: "Could we sit by the water? 我想安静坐一会。"))
            detail = try await service.appointmentCommand(id, action: .choice,
                request: .init(commandId: UUID(), expectedRevision: continued.appointment.revision, finish: true))
            error = nil
        } catch { self.error = "本地预览暂时无法载入。" }
    }
}
#endif

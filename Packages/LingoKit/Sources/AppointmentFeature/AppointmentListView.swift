import BackendKit
import DesignSystem
import SwiftUI

public struct AppointmentListView: View {
    private let service: any AppointmentServing
    private let currentCityID: String
    private let initialAppointmentID: UUID?
    private let characterName: (UUID) -> String
    private let onChat: (UUID) -> Void
    private let onMemory: (UUID) -> Void
    private let onClose: (() -> Void)?
    private let cache: AppointmentCache
    private let readingServices: AppointmentReadingServices?
    private let settle: (@Sendable (UUID) async throws -> Void)?
    @State private var appointments: [BackendAppointment] = []
    @State private var path: [UUID] = []
    @State private var loading = false
    @State private var message: String?
    @State private var openedInitial = false

    public init(client: BackendClient, currentCityID: String, storageNamespace: String, initialAppointmentID: UUID? = nil, readingServices: AppointmentReadingServices? = nil, settle: (@Sendable (UUID) async throws -> Void)? = nil, onClose: (() -> Void)? = nil, characterName: @escaping (UUID) -> String, onChat: @escaping (UUID) -> Void, onMemory: @escaping (UUID) -> Void) {
        self.init(service: client, currentCityID: currentCityID, storageNamespace: storageNamespace, initialAppointmentID: initialAppointmentID, readingServices: readingServices, settle: settle, onClose: onClose, characterName: characterName, onChat: onChat, onMemory: onMemory)
    }

    init(service: any AppointmentServing, currentCityID: String, storageNamespace: String, initialAppointmentID: UUID? = nil, readingServices: AppointmentReadingServices? = nil, settle: (@Sendable (UUID) async throws -> Void)? = nil, onClose: (() -> Void)? = nil, characterName: @escaping (UUID) -> String, onChat: @escaping (UUID) -> Void, onMemory: @escaping (UUID) -> Void) {
        self.service = service; self.currentCityID = currentCityID; self.initialAppointmentID = initialAppointmentID
        self.characterName = characterName; self.onChat = onChat; self.onMemory = onMemory
        self.cache = AppointmentCaches.account(storageNamespace)
        self.readingServices = readingServices; self.settle = settle; self.onClose = onClose
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if loading && appointments.isEmpty { ProgressView("正在查看约定…") }
                else if appointments.isEmpty {
                    ContentUnavailableView("还没有约定", systemImage: "calendar", description: Text("在聊天里与旅伴约好时间地点，就会出现在这里。"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            ForEach(appointments.sorted { $0.startsAt < $1.startsAt }) { item in
                                NavigationLink(value: item.id) { appointmentCard(item) }
                                    .buttonStyle(DSSceneEntranceButtonStyle())
                                    .accessibilityIdentifier("appointment.card.\(item.id.uuidString.lowercased())")
                            }
                        }
                        .padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .appointmentChrome(cityID: currentCityID, cityName: BackendAppointment.cityDisplayName(id: currentCityID, fallback: currentCityID))
            .navigationTitle("赴约")
            .toolbar { if let onClose { ToolbarItem(placement: .cancellationAction) { Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("关闭约定") } } }
            .safeAreaInset(edge: .bottom) {
                if let message { VStack { Text(message).font(.footnote); Button("重新载入") { Task { await load() } } }.padding().frame(maxWidth: .infinity).background(.regularMaterial) }
            }
            .navigationDestination(for: UUID.self) { id in
                AppointmentDetailView(id: id, service: service, cache: cache, currentCityID: currentCityID, readingServices: readingServices, settle: settle, characterName: characterName, onChat: onChat, onMemory: onMemory)
            }
            .refreshable { await load() }
            .onChange(of: path) { _, value in if value.isEmpty { Task { await load() } } }
            .task {
                if !openedInitial, let initialAppointmentID { openedInitial = true; path = [initialAppointmentID] }
                await load()
            }
        }
        .tint(AppointmentStyle.ink)
        .preferredColorScheme(.light)
    }

    private func appointmentCard(_ item: BackendAppointment) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(AppointmentTime.status(item)).font(.caption)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium))
            }.foregroundStyle(AppointmentStyle.ink.opacity(0.6))
            Text(item.displayTitle(companionName: characterName(item.characterId)))
                .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(item.placeName).font(.subheadline).foregroundStyle(AppointmentStyle.ink.opacity(0.75))
            AppointmentTimeView(appointment: item)
        }
        .multilineTextAlignment(.leading)
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .appointmentSurface()
    }

    private func load() async {
        guard !loading else { return }; loading = true
        defer { loading = false }
        if appointments.isEmpty, let cached = try? await cache.list() { appointments = cached.appointments }
        do {
            let response = try await service.appointments()
            try await cache.saveList(response)
            appointments = response.appointments; message = nil
        } catch { message = "暂时无法同步约定。已保存的经历仍可离线回看。" }
    }
}

struct AppointmentDetailView: View {
    @State private var model: AppointmentModel
    @State private var reader = false
    @State private var summary = false
    @State private var confirmCancel = false
    @State private var photoCredits = false
    let currentCityID: String
    let readingServices: AppointmentReadingServices?
    let characterName: (UUID) -> String
    let onChat: (UUID) -> Void
    let onMemory: (UUID) -> Void

    init(id: UUID, service: any AppointmentServing, cache: AppointmentCache, currentCityID: String, readingServices: AppointmentReadingServices?, settle: (@Sendable (UUID) async throws -> Void)?, characterName: @escaping (UUID) -> String, onChat: @escaping (UUID) -> Void, onMemory: @escaping (UUID) -> Void) {
        _model = State(initialValue: AppointmentModel(id: id, service: service, cache: cache, settle: settle))
        self.readingServices = readingServices
        self.currentCityID = currentCityID; self.characterName = characterName; self.onChat = onChat; self.onMemory = onMemory
    }

    var body: some View {
        ScrollView {
            if let detail = model.detail {
                let item = detail.appointment
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 28)
                    VStack(alignment: .leading, spacing: 22) {
                        Text(AppointmentTime.status(item)).font(.caption)
                            .foregroundStyle(AppointmentStyle.ink.opacity(0.6))
                        Text(item.displayTitle(companionName: characterName(item.characterId)))
                            .font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Divider().overlay(AppointmentStyle.ink.opacity(0.08))
                        Label(item.placeName, systemImage: "mappin.and.ellipse")
                            .font(.body.weight(.medium))
                        AppointmentTimeView(appointment: item)
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .appointmentSurface()
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = model.error { AppointmentErrorView(message: error, loading: model.submitting) { Task { if model.pending != nil { await model.retry() } else { await model.load() } } } }
                        if model.pending != nil && model.error == nil { Text("上次回应已保留，请重试以同步结果。").font(.footnote); Button("重试原回应") { Task { await model.retry() } } }
                        if item.status == "completed" || item.status == "finishing" {
                            Button("查看这次回顾") { summary = true }.buttonStyle(AppointmentPrimaryButtonStyle())
                        } else if item.status == "in_progress" || detail.session != nil {
                            Button("继续赴约") { reader = true }.buttonStyle(AppointmentPrimaryButtonStyle()).accessibilityIdentifier("appointment.resume")
                        } else if item.status == "confirmed" {
                            Button(model.submitting ? "正在接上这一页…" : "去赴约") {
                                Task { await model.submit(action: .start); if model.detail?.session != nil { reader = true } }
                            }.buttonStyle(AppointmentPrimaryButtonStyle()).disabled(model.submitting || model.offline || !AppointmentTime.entryAvailable(detail, cityID: currentCityID) || model.pending != nil)
                                .accessibilityIdentifier("appointment.start")
                            if !AppointmentTime.entryAvailable(detail, cityID: currentCityID) {
                                Text(entryExplanation(detail)).font(.footnote).foregroundStyle(.secondary)
                            }
                        } else { Button("回聊天商量下次") { onChat(item.characterId) }.buttonStyle(AppointmentPrimaryButtonStyle()) }
                        if detail.session != nil, item.status == "completed" { Button("回看完整经历") { reader = true }.frame(minHeight: 44) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
            } else if model.loading { ProgressView("正在打开约定…").padding(40) }
            else { AppointmentErrorView(message: model.error ?? "约定暂时无法打开", loading: false) { Task { await model.load() } }.padding() }
        }
        .appointmentChrome(cityID: model.detail?.appointment.cityId ?? currentCityID, cityName: model.detail?.appointment.displayCityName ?? "")
        .navigationTitle("约定").navigationBarTitleDisplayMode(.inline)
        .dsTabBarHidden()
        .controlSize(.large)
        .refreshable { await model.load() }
        .task { await model.load() }
        .navigationDestination(isPresented: $reader) { AppointmentReaderView(model: model, readingServices: readingServices, characterName: characterName, onChat: onChat, onMemory: onMemory) }
        .navigationDestination(isPresented: $summary) { AppointmentSummaryView(model: model, characterName: characterName, onChat: onChat, onMemory: onMemory) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("照片来源", systemImage: "info.circle") { photoCredits = true }
                    if let item = model.detail?.appointment, item.status == "confirmed" {
                        Button("商量改期", systemImage: "bubble.left") { onChat(item.characterId) }
                        Button("取消约定", systemImage: "calendar.badge.minus", role: .destructive) { confirmCancel = true }
                            .disabled(model.offline || model.submitting || model.pending != nil)
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 44, height: 44) }
                    .accessibilityLabel("约定选项").accessibilityIdentifier("appointment.details.options")
            }
        }
        .sheet(isPresented: $photoCredits) {
            AppointmentPhotoCreditsView(cityID: model.detail?.appointment.cityId ?? currentCityID,
                                        cityName: model.detail?.appointment.displayCityName ?? "")
        }
        .confirmationDialog("取消这次约定？", isPresented: $confirmCancel, titleVisibility: .visible) {
            if model.detail?.appointment.status == "confirmed" {
                Button("取消约定", role: .destructive) { Task { await model.submit(action: .cancel) } }
            }
            Button("保留约定", role: .cancel) { }
        } message: { Text("时间地点会保留为历史。取消不会扣好感，之后可以在聊天里重新约定。") }
    }

    private func entryExplanation(_ detail: BackendAppointmentDetail) -> String {
        if detail.appointment.cityId != currentCityID { return "这次约定在\(detail.appointment.displayCityName)。切换应用城市后，可在约定时段进入。" }
        return "可赴约时段 · \(AppointmentDisplayTime.beijingWindow(opens: detail.appointment.windowOpensAt, closes: detail.appointment.windowClosesAt))"
    }
}

struct AppointmentErrorView: View {
    let message: String
    let loading: Bool
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Button(loading ? "正在接上…" : "重试") { retry() }.disabled(loading).frame(minHeight: 44).accessibilityIdentifier("appointment.retry")
        }.accessibilityElement(children: .contain)
    }
}

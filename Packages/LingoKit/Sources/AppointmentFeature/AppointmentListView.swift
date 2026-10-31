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
                    ContentUnavailableView("下一次见，慢慢约。", systemImage: "calendar", description: Text("在聊天里与旅伴约好时间地点，就会出现在这里。"))
                } else {
                    List(appointments.sorted { $0.startsAt < $1.startsAt }) { item in
                        NavigationLink(value: item.id) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.title).font(.headline)
                                Text("\(characterName(item.characterId)) · \(item.cityName) · \(item.placeName)").font(.subheadline)
                                Text(AppointmentTime.formatted(item.startsAt, timeZone: item.timeZone)).font(.subheadline).foregroundStyle(.secondary)
                                Text(AppointmentTime.status(item)).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.accessibilityIdentifier("appointment.card.\(item.id.uuidString.lowercased())")
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("赴约")
            .toolbar { if let onClose { ToolbarItem(placement: .cancellationAction) { Button("关闭", action: onClose) } } }
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
        .preferredColorScheme(.light)
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
                VStack(alignment: .leading, spacing: 20) {
                    AppointmentPhotoView(cityID: item.cityId, cityName: item.cityName, paused: false)
                        .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(item.title).font(.largeTitle.weight(.medium)).fontDesign(.serif)
                    Text("与 \(characterName(item.characterId)) · \(AppointmentTime.status(item))").font(.headline)
                    Label(item.placeName, systemImage: "mappin.and.ellipse")
                    Text("\(item.cityName)当地时间\n\(AppointmentTime.formatted(item.startsAt, timeZone: item.timeZone))")
                    if TimeZone.current.identifier != item.timeZone {
                        Text("设备所在时区\n\(AppointmentTime.formatted(item.startsAt, timeZone: TimeZone.current.identifier))").foregroundStyle(.secondary)
                    }
                    if let error = model.error { AppointmentErrorView(message: error, loading: model.submitting) { Task { if model.pending != nil { await model.retry() } else { await model.load() } } } }
                    if model.pending != nil && model.error == nil { Text("上次回应已保留，请重试以同步结果。").font(.footnote); Button("重试原回应") { Task { await model.retry() } } }
                    if item.status == "completed" || item.status == "finishing" {
                        Button("查看这次回顾") { summary = true }.buttonStyle(.borderedProminent)
                    } else if item.status == "in_progress" || detail.session != nil {
                        Button("继续这次相处") { reader = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("appointment.resume")
                    } else if item.status == "confirmed" {
                        Button(model.submitting ? "正在接上这一页…" : "去赴约") {
                            Task { await model.submit(action: .start); if model.detail?.session != nil { reader = true } }
                        }.buttonStyle(.borderedProminent).disabled(model.submitting || model.offline || !AppointmentTime.entryAvailable(detail, cityID: currentCityID) || model.pending != nil)
                            .accessibilityIdentifier("appointment.start")
                        Text(entryExplanation(detail)).font(.footnote).foregroundStyle(.secondary)
                        Button("回聊天商量改期") { onChat(item.characterId) }.frame(minHeight: 44)
                        Button("取消这次约定", role: .destructive) { confirmCancel = true }.frame(minHeight: 44).disabled(model.offline || model.submitting || model.pending != nil)
                    } else { Button("回聊天商量下次") { onChat(item.characterId) }.buttonStyle(.borderedProminent) }
                    if detail.session != nil, item.status == "completed" { Button("回看完整经历") { reader = true } }
                }.padding(20)
            } else if model.loading { ProgressView("正在打开约定…").padding(40) }
            else { AppointmentErrorView(message: model.error ?? "约定暂时无法打开", loading: false) { Task { await model.load() } }.padding() }
        }
        .navigationTitle("约定").navigationBarTitleDisplayMode(.inline)
        .controlSize(.large)
        .refreshable { await model.load() }
        .task { await model.load() }
        .navigationDestination(isPresented: $reader) { AppointmentReaderView(model: model, readingServices: readingServices, characterName: characterName, onChat: onChat, onMemory: onMemory) }
        .navigationDestination(isPresented: $summary) { AppointmentSummaryView(model: model, characterName: characterName, onChat: onChat, onMemory: onMemory) }
        .confirmationDialog("取消这次约定？", isPresented: $confirmCancel, titleVisibility: .visible) {
            if model.detail?.appointment.status == "confirmed" {
                Button("取消约定", role: .destructive) { Task { await model.submit(action: .cancel) } }
            }
            Button("保留约定", role: .cancel) { }
        } message: { Text("时间地点会保留为历史。取消不会扣好感，之后可以在聊天里重新约定。") }
    }

    private func entryExplanation(_ detail: BackendAppointmentDetail) -> String {
        if detail.appointment.cityId != currentCityID { return "这次约定在\(detail.appointment.cityName)。切换应用城市后，可在约定时段进入。" }
        if AppointmentTime.entryAvailable(detail, cityID: currentCityID) { return "已到约定时段。开始后可随时暂停，再继续。" }
        return "可进入时间：\(AppointmentTime.formatted(detail.appointment.windowOpensAt, timeZone: detail.appointment.timeZone)) 至 \(AppointmentTime.formatted(detail.appointment.windowClosesAt, timeZone: detail.appointment.timeZone))。以服务端时间为准。"
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

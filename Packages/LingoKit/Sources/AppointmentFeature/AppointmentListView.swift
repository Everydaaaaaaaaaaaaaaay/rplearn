import BackendKit
import DesignSystem
import PersistenceKit
import SwiftUI

public struct AppointmentListView: View {
    private let service: any AppointmentServing
    private let currentCityID: String
    private let initialAppointmentID: UUID?
    private let characterName: (UUID) -> String
    private let characterCards: [UUID: CharacterCard]
    private let onChat: (UUID) -> Void
    private let onMemory: (UUID) -> Void
    private let onClose: (() -> Void)?
    private let cache: AppointmentCache
    private let readingServices: AppointmentReadingServices?
    private let settle: (@Sendable (UUID) async throws -> Void)?
    @State private var appointments: [BackendAppointment] = []
    @State private var path: [AppointmentRoute] = []
    @State private var selectedModel: AppointmentModel?
    @State private var loading = false
    @State private var message: String?
    @State private var openedInitial = false

    public init(client: BackendClient, currentCityID: String, storageNamespace: String, initialAppointmentID: UUID? = nil, readingServices: AppointmentReadingServices? = nil, settle: (@Sendable (UUID) async throws -> Void)? = nil, onClose: (() -> Void)? = nil, characterName: @escaping (UUID) -> String, characterCards: [UUID: CharacterCard] = [:], onChat: @escaping (UUID) -> Void, onMemory: @escaping (UUID) -> Void) {
        self.init(service: client, currentCityID: currentCityID, storageNamespace: storageNamespace, initialAppointmentID: initialAppointmentID, readingServices: readingServices, settle: settle, onClose: onClose, characterName: characterName, characterCards: characterCards, onChat: onChat, onMemory: onMemory)
    }

    init(service: any AppointmentServing, currentCityID: String, storageNamespace: String, initialAppointmentID: UUID? = nil, readingServices: AppointmentReadingServices? = nil, settle: (@Sendable (UUID) async throws -> Void)? = nil, onClose: (() -> Void)? = nil, characterName: @escaping (UUID) -> String, characterCards: [UUID: CharacterCard] = [:], onChat: @escaping (UUID) -> Void, onMemory: @escaping (UUID) -> Void) {
        self.service = service; self.currentCityID = currentCityID; self.initialAppointmentID = initialAppointmentID
        self.characterName = characterName; self.characterCards = characterCards
        self.onChat = onChat; self.onMemory = onMemory
        self.cache = AppointmentCaches.account(storageNamespace)
        self.readingServices = readingServices; self.settle = settle; self.onClose = onClose
    }

    public var body: some View {
        NavigationStack(path: $path) {
            AppointmentPage(cityID: currentCityID, cityName: BackendAppointment.cityDisplayName(id: currentCityID, fallback: currentCityID),
                            backLabel: "返回活动", onBack: onClose) {
                Group {
                    if loading && appointments.isEmpty { ProgressView("正在查看约定…") }
                    else if appointments.isEmpty {
                        ContentUnavailableView("还没有约定", systemImage: "calendar", description: Text("在聊天里与旅伴约好时间地点，就会出现在这里。"))
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(appointments.sorted { $0.startsAt < $1.startsAt }) { item in
                                        AppointmentCardView(item: item, service: service, cache: cache,
                                                            currentCityID: currentCityID, settle: settle,
                                                            characterName: characterName, onChat: onChat) { model, route in
                                            guard path.isEmpty else { return }
                                            selectedModel = model
                                            path.append(route)
                                        }
                                        .id(item.id)
                                    }
                                }
                                .padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .onChange(of: appointments.map(\.id), initial: true) { _, ids in
                                if !openedInitial, let initialAppointmentID, ids.contains(initialAppointmentID) {
                                    openedInitial = true
                                    proxy.scrollTo(initialAppointmentID, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message { VStack { Text(message).font(.footnote); Button("重新载入") { Task { await load() } } }.padding().frame(maxWidth: .infinity).background(AppointmentStyle.canvas) }
            }
            .navigationDestination(for: AppointmentRoute.self) { route in
                if let selectedModel {
                    switch route {
                    case .reader:
                        AppointmentReaderView(model: selectedModel, readingServices: readingServices,
                                              characterName: characterName, onChat: onChat, onMemory: onMemory)
                    case .summary:
                        AppointmentSummaryView(model: selectedModel, characterName: characterName,
                                               onChat: onChat, onMemory: onMemory)
                    }
                }
            }
            .refreshable { await load() }
            .onChange(of: path) { _, value in if value.isEmpty { Task { await load() } } }
            .task { await load() }
        }
        .environment(\.appointmentCharacterCards, characterCards)
        .tint(AppointmentStyle.ink)
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

private enum AppointmentRoute: Hashable {
    case reader
    case summary
}

private struct AppointmentCardView: View {
    let item: BackendAppointment
    @State private var model: AppointmentModel
    @State private var confirmCancel = false
    @State private var photoCredits = false
    let currentCityID: String
    let characterName: (UUID) -> String
    let onChat: (UUID) -> Void
    let onOpen: (AppointmentModel, AppointmentRoute) -> Void

    init(item: BackendAppointment, service: any AppointmentServing, cache: AppointmentCache,
         currentCityID: String, settle: (@Sendable (UUID) async throws -> Void)?,
         characterName: @escaping (UUID) -> String, onChat: @escaping (UUID) -> Void,
         onOpen: @escaping (AppointmentModel, AppointmentRoute) -> Void) {
        self.item = item
        _model = State(initialValue: AppointmentModel(id: item.id, service: service, cache: cache, settle: settle))
        self.currentCityID = currentCityID
        self.characterName = characterName
        self.onChat = onChat
        self.onOpen = onOpen
    }

    private var appointment: BackendAppointment { model.detail?.appointment ?? item }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(AppointmentTime.status(appointment)).font(.caption)
                    .foregroundStyle(AppointmentStyle.ink.opacity(0.6))
                Spacer()
                options
            }
            AppointmentIdentityView(appointment: appointment, name: characterName(appointment.characterId))
            if let error = model.error {
                AppointmentErrorView(message: error, loading: model.loading || model.submitting) {
                    Task { if model.pending != nil { await model.retry() } else { await model.load() } }
                }
            } else if model.pending != nil && !model.submitting {
                Button("重试原回应") { Task { await model.retry() } }.frame(minHeight: 44)
            }
            action.padding(.top, 4)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 22).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(AppointmentStyle.ink.opacity(0.09)).frame(height: 0.5) }
        .task(id: item.revision) { await model.load() }
        .sheet(isPresented: $photoCredits) {
            AppointmentPhotoCreditsView(cityID: appointment.cityId, cityName: appointment.displayCityName)
        }
        .confirmationDialog("取消这次约定？", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("取消约定", role: .destructive) { Task { await model.submit(action: .cancel) } }
            Button("保留约定", role: .cancel) { }
        } message: { Text("取消不会扣好感，之后可以在聊天里重新约定。") }
    }

    private var options: some View {
        Menu {
            Button("照片来源", systemImage: "info.circle") { photoCredits = true }
            if appointment.status == "confirmed" {
                Button("商量改期", systemImage: "bubble.left") { onChat(appointment.characterId) }
                Button("取消约定", systemImage: "calendar.badge.minus", role: .destructive) { confirmCancel = true }
                    .disabled(model.detail == nil || model.offline || model.submitting || model.pending != nil)
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("约定选项").accessibilityIdentifier("appointment.details.options")
    }

    @ViewBuilder private var action: some View {
        if appointment.status == "completed" || appointment.status == "finishing" {
            Button("查看回顾") { onOpen(model, .summary) }
                .buttonStyle(AppointmentPrimaryButtonStyle()).disabled(model.detail == nil)
                .accessibilityIdentifier("appointment.openSummary")
        } else if appointment.status == "in_progress" || model.detail?.session != nil {
            Button("继续赴约") { onOpen(model, .reader) }
                .buttonStyle(AppointmentPrimaryButtonStyle()).disabled(model.detail == nil)
                .accessibilityIdentifier("appointment.resume")
        } else if appointment.status == "confirmed" {
            Button(model.submitting ? "正在开始…" : "去赴约") {
                Task {
                    // Refresh the server clock and status when entering from a long-lived list.
                    await model.load()
                    guard let detail = model.detail, !model.offline else { return }
                    if detail.appointment.status == "completed" || detail.appointment.status == "finishing" {
                        onOpen(model, .summary)
                    } else if detail.session != nil {
                        onOpen(model, .reader)
                    } else if AppointmentTime.entryAvailable(detail, cityID: currentCityID) {
                        await model.submit(action: .start)
                        if model.detail?.session != nil { onOpen(model, .reader) }
                    }
                }
            }
            .buttonStyle(AppointmentPrimaryButtonStyle())
            .disabled(model.loading || model.submitting || model.offline || model.detail == nil || model.pending != nil || appointment.cityId != currentCityID)
            .accessibilityIdentifier("appointment.start")
            if let detail = model.detail, !AppointmentTime.entryAvailable(detail, cityID: currentCityID) {
                Text(appointment.cityId != currentCityID
                     ? "切换到\(appointment.cityName)后赴约"
                     : "可赴约时段 · \(AppointmentDisplayTime.beijingWindow(opens: appointment.windowOpensAt, closes: appointment.windowClosesAt))")
                    .font(.footnote).foregroundStyle(AppointmentStyle.ink.opacity(0.65))
            }
        } else {
            Button("回聊天商量下次") { onChat(appointment.characterId) }
                .buttonStyle(AppointmentPrimaryButtonStyle())
        }
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

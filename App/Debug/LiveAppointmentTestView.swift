#if DEBUG
import AppointmentFeature
import BackendKit
import CoreKit
import DictKit
import PersistenceKit
import SpeechKit
import SwiftUI
import SyncKit

/// Runs the normal appointment API with its own credentials and local stores.
struct LiveAppointmentTestView: View {
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    let speech: any SpeechService
    let onClose: () -> Void

    @State private var session: Session?
    @State private var failure: String?
    @State private var attempt = 0

    private struct Session {
        let client: BackendClient
        let sync: BackendContentSyncCoordinator
        let coordinator: AppointmentCoordinator
        let accountID: UUID
        let cityID: String
        let cards: [UUID: CharacterCard]
        let reading: AppointmentReadingServices
    }

    var body: some View {
        ZStack {
            if let session {
                AppointmentListView(client: session.client, currentCityID: session.cityID,
                    storageNamespace: "live-appointment-test-\(session.accountID.uuidString)",
                    readingServices: session.reading, settle: { id in try await session.coordinator.settle(id) },
                    onClose: onClose, backLabel: "返回设置",
                    characterName: { session.cards[$0]?.name ?? "旅伴" }, characterCards: session.cards,
                    onChat: { _ in onClose() }, onMemory: { _ in onClose() })
            } else {
                NavigationStack {
                    Group {
                        if let failure {
                            ContentUnavailableView {
                                Label("真实赴约", systemImage: "calendar.badge.exclamationmark")
                            } description: {
                                Text(failure)
                            } actions: {
                                Button("重试") { attempt += 1 }
                            }
                        } else {
                            ProgressView("正在连接测试账号…")
                        }
                    }
                    .navigationTitle("真实赴约")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("返回设置", action: onClose) }
                    }
                }
            }
        }
        .task(id: attempt) { await connect() }
        .onDisappear {
            if let session { Task { await session.sync.deactivate() } }
        }
    }

    private func connect() async {
        guard session == nil else { return }
        failure = nil
        do {
            let credentials = KeychainAuthCredentialStore(keychain: KeychainStore(service: "com.lingotrip.debug.appointment-test"))
            let ticket = FileManager.default.temporaryDirectory.appendingPathComponent("appointment-test-session.json")
            if FileManager.default.fileExists(atPath: ticket.path) {
                let credential = try JSONDecoder().decode(StoredAuthCredential.self, from: Data(contentsOf: ticket))
                try credentials.save(credential)
                try FileManager.default.removeItem(at: ticket)
            }
            let client = BackendClient(configuration: .live, credentialStore: credentials)
            guard let identity = try await client.restoreSession() else {
                failure = "这台设备还没有可用的独立测试账号。账号内的真实约定可以从「活动 → 赴约」进入。"
                return
            }
            let snapshot: BackendSyncSnapshot = try await client.get("/v1/sync/snapshot")
            let container = try await Task.detached {
                try ModelContainerFactory.makeContainer(inMemory: true)
            }.value
            let sync = BackendContentSyncCoordinator(backend: client, store: ContentSyncStore(modelContainer: container))
            do {
                _ = try await sync.activate(userID: identity.userID)
                let roster = RosterStore(modelContainer: container)
                let characters = try await roster.allCharacters()
                try Task.checkCancellation()
                session = Session(client: client, sync: sync,
                    coordinator: AppointmentCoordinator(backend: client, sync: sync),
                    accountID: identity.userID, cityID: snapshot.state.profile.currentRegionId,
                    cards: Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0.card) }),
                    reading: AppointmentReadingServices(dictionary: dictionary, grammar: grammar,
                        favorites: FavoritesStore(modelContainer: container), speech: speech))
            } catch {
                await sync.deactivate()
                throw error
            }
        } catch {
            guard !Task.isCancelled else { return }
            failure = (error as? BackendClientError)?.errorDescription ?? "暂时无法准备独立测试账号，请重试。"
        }
    }
}
#endif

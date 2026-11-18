import Combine
import BackendKit
import DomainKit
import Foundation
import Observation

/// App-owned lifetime: Tab/navigation disappearance never owns an action request.
@MainActor
@Observable
public final class ActivityJourneyCoordinator {
    private(set) var model: SocialEncounterModel?
    private(set) var cityOuting: CityOutingModel?
    public private(set) var hasUnreadResult = false
    @ObservationIgnored private var observation: AnyCancellable?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var viewing = false
    @ObservationIgnored private var resultWasSeen = false
    public init() {}

    public var isPreparing: Bool { cityOuting?.isPreparing ?? (model?.started == true && model?.canReveal == false) }
    public var isRunning: Bool { cityOuting?.isRunning ?? (model?.started == true && model?.completed == false) }
    public var activeActivity: SceneActivity? { cityOuting?.activity ?? model?.activity }

    func preparePlace(archive: CityOutingArchive, region: Region, deps: HomeDependencies, namespace: String, gateway: any OutingGateway) {
        guard !isRunning else { return }
        let next = CityOutingModel(archive: archive, region: region, deps: deps, namespace: namespace, gateway: gateway)
        model = nil; cityOuting = next; resultWasSeen = false
        observation = next.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func prepare(activity: SceneActivity, region: Region, deps: HomeDependencies, namespace: String) {
        if isRunning { return }
        cityOuting = nil
        let next = SocialEncounterModel(activity: activity, region: region, deps: deps, namespace: namespace)
        resultWasSeen = false
        model = next
        observation = next.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func start() {
        if let cityOuting { cityOuting.start(); return }
        guard let model else { return }
        model.start()
        guard let deadline = model.revealAt, deadlineTask == nil else { return }
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
    func setViewing(_ visible: Bool) {
        viewing = visible
        if visible { setUnreadResult(false) }
        else { model?.stopSpeech(); cityOuting?.stopSpeech() }
        refresh()
    }
    private func refresh() {
        if cityOuting?.snapshot != nil || model?.canReveal == true {
            if viewing { resultWasSeen = true; setUnreadResult(false) }
            else if !resultWasSeen { setUnreadResult(true) }
        }
    }
    private func setUnreadResult(_ value: Bool) {
        guard hasUnreadResult != value else { return }
        hasUnreadResult = value
    }
    public func reset() {
        observation = nil
        deadlineTask?.cancel(); deadlineTask = nil
        model?.pause(); model = nil
        cityOuting?.pause(); cityOuting = nil
        setUnreadResult(false)
        resultWasSeen = false
    }
}

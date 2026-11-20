import Combine
import BackendKit
import DomainKit
import Foundation
import Observation

/// App-owned lifetime: Tab/navigation disappearance never owns an action request.
@MainActor
@Observable
public final class ActivityJourneyCoordinator {
    private(set) var cityOuting: CityOutingModel?
    public private(set) var hasUnreadResult = false
    @ObservationIgnored private var observation: AnyCancellable?
    @ObservationIgnored private var viewing = false
    @ObservationIgnored private var resultWasSeen = false
    public init() {}

    public var isPreparing: Bool { cityOuting?.isPreparing == true }
    public var hasOpenOuting: Bool { cityOuting != nil }

    func preparePlace(archive: CityOutingArchive, region: Region, deps: HomeDependencies, namespace: String, gateway: any OutingGateway) {
        guard cityOuting?.isRunning != true else { return }
        let next = CityOutingModel(archive: archive, region: region, deps: deps, namespace: namespace, gateway: gateway)
        cityOuting = next; resultWasSeen = false
        observation = next.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func setViewing(_ visible: Bool) {
        viewing = visible
        if visible { setUnreadResult(false) }
        else { cityOuting?.stopSpeech() }
        refresh()
    }
    private func refresh() {
        if cityOuting?.snapshot != nil {
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
        cityOuting?.pause(); cityOuting = nil
        setUnreadResult(false)
        resultWasSeen = false
    }
}

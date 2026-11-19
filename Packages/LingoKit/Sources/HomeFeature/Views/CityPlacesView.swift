import BackendKit
import SwiftUI

struct CityPlacesView: View {
    let cityName: String
    let catalog: BackendActivityCatalog
    var showsChrome: Bool = true
    let onBack: () -> Void
    let onJournal: () -> Void
    let onSelect: (BackendActivityPlace) -> Void
    let resumeTitle: String?
    let onResume: () -> Void

    var body: some View {
        ActivitySceneBrowser(cityName: cityName, places: catalog.places,
                            showsChrome: showsChrome,
                            onBack: onBack, onJournal: onJournal, onSelect: onSelect,
                            resumeTitle: resumeTitle, onResume: onResume)
    }

    static let paper = Color(red: 0.975, green: 0.965, blue: 0.945)
}

import CoreKit
import DesignSystem
import DictKit
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

struct EncounterPresentation: Identifiable {
    let id = UUID()
    let character: CharacterDTO
    let openingLine: String
    let origin: EncounterService.Origin
    let activity: Region.Activity
    let region: Region
    let companionName: String?
}

extension Region.ActivityCategory {
    var titleZh: String {
        switch self {
        case .culture: "人文"
        case .food: "美食"
        case .outdoors: "户外"
        case .social: "社交"
        case .night: "夜游"
        }
    }

    var icon: String {
        switch self {
        case .culture: "building.columns.fill"
        case .food: "fork.knife"
        case .outdoors: "figure.hiking"
        case .social: "person.2.fill"
        case .night: "moon.stars.fill"
        }
    }

    var tint: Color {
        switch self {
        case .culture: .dsQuiz
        case .food: .dsSunset
        case .outdoors: .dsSuccess
        case .social: .dsSky
        case .night: .dsSpeech
        }
    }
}

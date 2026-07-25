import SwiftUI
import UIKit

public enum DSScenePalette {
    public struct City: Sendable {
        public let skyTop: Color
        public let skyBottom: Color
        public let silhouetteFar: Color
        public let silhouetteNear: Color
        public let accent: Color

        public init(
            skyTop: Color,
            skyBottom: Color,
            silhouetteFar: Color,
            silhouetteNear: Color,
            accent: Color
        ) {
            self.skyTop = skyTop
            self.skyBottom = skyBottom
            self.silhouetteFar = silhouetteFar
            self.silhouetteNear = silhouetteNear
            self.accent = accent
        }
    }

    public static func city(_ regionID: String) -> City {
        switch regionID {
        case "melbourne":
            City(
                skyTop: Color(light: UIColor(hex: 0x58D4DC), dark: UIColor(hex: 0x216C78)),
                skyBottom: Color(light: UIColor(hex: 0xFFF0D0), dark: UIColor(hex: 0x253C47)),
                silhouetteFar: Color(light: UIColor(hex: 0x7CB7B3), dark: UIColor(hex: 0x25505A)),
                silhouetteNear: Color(light: UIColor(hex: 0x277D87), dark: UIColor(hex: 0x163842)),
                accent: .dsCyan
            )
        case "newyork":
            City(
                skyTop: Color(light: UIColor(hex: 0x68BDF3), dark: UIColor(hex: 0x214A72)),
                skyBottom: Color(light: UIColor(hex: 0xFFD8AC), dark: UIColor(hex: 0x443445)),
                silhouetteFar: Color(light: UIColor(hex: 0x7796B5), dark: UIColor(hex: 0x334153)),
                silhouetteNear: Color(light: UIColor(hex: 0x354C6A), dark: UIColor(hex: 0x202B3A)),
                accent: Color(light: UIColor(hex: 0xFF7967), dark: UIColor(hex: 0xE17468))
            )
        default:
            City(
                skyTop: Color(light: UIColor(hex: 0x28AEEF), dark: UIColor(hex: 0x1D5583)),
                skyBottom: Color(light: UIColor(hex: 0xCDEEFF), dark: UIColor(hex: 0x263E56)),
                silhouetteFar: Color(light: UIColor(hex: 0x6EA3BA), dark: UIColor(hex: 0x324D5D)),
                silhouetteNear: Color(light: UIColor(hex: 0x315E78), dark: UIColor(hex: 0x203846)),
                accent: .dsSky
            )
        }
    }

    public static func story(_ key: String?) -> [Color] {
        switch key {
        case "london_bookshop": dynamicPair(0x7A6658, 0x24201E, darkTop: 0x433A34, darkBottom: 0x121110)
        case "london_street": dynamicPair(0x7E99B0, 0x32465F, darkTop: 0x425466, darkBottom: 0x192332)
        case "melbourne_beach": dynamicPair(0xFFC66C, 0x3E92BB, darkTop: 0x8C6A42, darkBottom: 0x234D62)
        case "melbourne_cafe": dynamicPair(0x9D7A5C, 0x453125, darkTop: 0x594536, darkBottom: 0x251C18)
        case "newyork_subway": dynamicPair(0x666A73, 0x252833, darkTop: 0x3C3E45, darkBottom: 0x15161B)
        case "newyork_street": dynamicPair(0xE39A5C, 0x59405E, darkTop: 0x76533B, darkBottom: 0x302536)
        default: dynamicPair(0x566D8D, 0x202B40, darkTop: 0x354458, darkBottom: 0x141A27)
        }
    }

    public static func ticket(_ seed: Int) -> [Color] {
        switch abs(seed) % 6 {
        case 0: dynamicPair(0xFF8E63, 0xE94A65, darkTop: 0xB7614C, darkBottom: 0x923849)
        case 1: dynamicPair(0x5AAEF5, 0x3F5EC8, darkTop: 0x3E78A9, darkBottom: 0x30478E)
        case 2: dynamicPair(0x6EC98D, 0x248B7D, darkTop: 0x4B8A63, darkBottom: 0x22645E)
        case 3: dynamicPair(0xF8C54D, 0xE18A31, darkTop: 0xA88639, darkBottom: 0x955E29)
        case 4: dynamicPair(0xB57DE0, 0x7653C8, darkTop: 0x7B579B, darkBottom: 0x523E8D)
        default: dynamicPair(0x58C8D1, 0x327B9C, darkTop: 0x408C92, darkBottom: 0x285A71)
        }
    }

    private static func dynamicPair(
        _ lightTop: UInt,
        _ lightBottom: UInt,
        darkTop: UInt,
        darkBottom: UInt
    ) -> [Color] {
        [
            Color(light: UIColor(hex: lightTop), dark: UIColor(hex: darkTop)),
            Color(light: UIColor(hex: lightBottom), dark: UIColor(hex: darkBottom)),
        ]
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

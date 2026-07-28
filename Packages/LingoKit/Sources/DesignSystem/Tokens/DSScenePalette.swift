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
        case "capetown":
            City(
                skyTop: Color(light: UIColor(hex: 0x2FAFE8), dark: UIColor(hex: 0x245A73)),
                skyBottom: Color(light: UIColor(hex: 0xF8D4A5), dark: UIColor(hex: 0x493B34)),
                silhouetteFar: Color(light: UIColor(hex: 0x78A47A), dark: UIColor(hex: 0x385648)),
                silhouetteNear: Color(light: UIColor(hex: 0x315C57), dark: UIColor(hex: 0x203D3A)),
                accent: Color(light: UIColor(hex: 0xF07B64), dark: UIColor(hex: 0xD36C5B))
            )
        case "singapore":
            City(
                skyTop: Color(light: UIColor(hex: 0x51C9DE), dark: UIColor(hex: 0x256878)),
                skyBottom: Color(light: UIColor(hex: 0xFFF0C2), dark: UIColor(hex: 0x3D443E)),
                silhouetteFar: Color(light: UIColor(hex: 0x6FB5A1), dark: UIColor(hex: 0x315A51)),
                silhouetteNear: Color(light: UIColor(hex: 0x247767), dark: UIColor(hex: 0x1B433D)),
                accent: Color(light: UIColor(hex: 0xEE8C57), dark: UIColor(hex: 0xCC744A))
            )
        case "dublin":
            City(
                skyTop: Color(light: UIColor(hex: 0x68BDED), dark: UIColor(hex: 0x285873)),
                skyBottom: Color(light: UIColor(hex: 0xE7F2D1), dark: UIColor(hex: 0x34443B)),
                silhouetteFar: Color(light: UIColor(hex: 0x83A98A), dark: UIColor(hex: 0x3C5948)),
                silhouetteNear: Color(light: UIColor(hex: 0x46694E), dark: UIColor(hex: 0x273D31)),
                accent: Color(light: UIColor(hex: 0x3FA268), dark: UIColor(hex: 0x39845A))
            )
        case "edinburgh":
            City(
                skyTop: Color(light: UIColor(hex: 0x72A9D8), dark: UIColor(hex: 0x334D67)),
                skyBottom: Color(light: UIColor(hex: 0xDDE7D7), dark: UIColor(hex: 0x3A403E)),
                silhouetteFar: Color(light: UIColor(hex: 0x7B8D85), dark: UIColor(hex: 0x414B48)),
                silhouetteNear: Color(light: UIColor(hex: 0x4B5655), dark: UIColor(hex: 0x2B3233)),
                accent: Color(light: UIColor(hex: 0x8C73B5), dark: UIColor(hex: 0x78639A))
            )
        case "vancouver":
            City(
                skyTop: Color(light: UIColor(hex: 0x3FB4EC), dark: UIColor(hex: 0x245D7A)),
                skyBottom: Color(light: UIColor(hex: 0xD8F1EA), dark: UIColor(hex: 0x314846)),
                silhouetteFar: Color(light: UIColor(hex: 0x6E9C91), dark: UIColor(hex: 0x38564F)),
                silhouetteNear: Color(light: UIColor(hex: 0x315D58), dark: UIColor(hex: 0x203D3B)),
                accent: Color(light: UIColor(hex: 0x3B9F8B), dark: UIColor(hex: 0x358472))
            )
        case "auckland":
            City(
                skyTop: Color(light: UIColor(hex: 0x32B8E8), dark: UIColor(hex: 0x23627A)),
                skyBottom: Color(light: UIColor(hex: 0xDFF5D2), dark: UIColor(hex: 0x344A3A)),
                silhouetteFar: Color(light: UIColor(hex: 0x72A987), dark: UIColor(hex: 0x395A49)),
                silhouetteNear: Color(light: UIColor(hex: 0x2E7167), dark: UIColor(hex: 0x21453E)),
                accent: Color(light: UIColor(hex: 0x20A99A), dark: UIColor(hex: 0x26877D))
            )
        case "nairobi":
            City(
                skyTop: Color(light: UIColor(hex: 0x4CB9E6), dark: UIColor(hex: 0x295E73)),
                skyBottom: Color(light: UIColor(hex: 0xF3D89C), dark: UIColor(hex: 0x4A4032)),
                silhouetteFar: Color(light: UIColor(hex: 0x92A866), dark: UIColor(hex: 0x4A5938)),
                silhouetteNear: Color(light: UIColor(hex: 0x536A42), dark: UIColor(hex: 0x33412B)),
                accent: Color(light: UIColor(hex: 0xE3944A), dark: UIColor(hex: 0xC47A3D))
            )
        case "toronto":
            City(
                skyTop: Color(light: UIColor(hex: 0x55B9E9), dark: UIColor(hex: 0x285C78)),
                skyBottom: Color(light: UIColor(hex: 0xE7F3F0), dark: UIColor(hex: 0x344747)),
                silhouetteFar: Color(light: UIColor(hex: 0x7CA2AD), dark: UIColor(hex: 0x3C535C)),
                silhouetteNear: Color(light: UIColor(hex: 0x425F68), dark: UIColor(hex: 0x293D43)),
                accent: Color(light: UIColor(hex: 0xE65353), dark: UIColor(hex: 0xC84A4A))
            )
        case "sydney":
            City(
                skyTop: Color(light: UIColor(hex: 0x34B7E8), dark: UIColor(hex: 0x22627E)),
                skyBottom: Color(light: UIColor(hex: 0xFFE1A3), dark: UIColor(hex: 0x4C4032)),
                silhouetteFar: Color(light: UIColor(hex: 0x70A7B2), dark: UIColor(hex: 0x385964)),
                silhouetteNear: Color(light: UIColor(hex: 0x315F70), dark: UIColor(hex: 0x213E49)),
                accent: Color(light: UIColor(hex: 0xF39A45), dark: UIColor(hex: 0xCE7F3B))
            )
        case "neworleans":
            City(
                skyTop: Color(light: UIColor(hex: 0x78B4D6), dark: UIColor(hex: 0x34556D)),
                skyBottom: Color(light: UIColor(hex: 0xF6C783), dark: UIColor(hex: 0x58402F)),
                silhouetteFar: Color(light: UIColor(hex: 0x7E9A78), dark: UIColor(hex: 0x415440)),
                silhouetteNear: Color(light: UIColor(hex: 0x4B654E), dark: UIColor(hex: 0x2F4132)),
                accent: Color(light: UIColor(hex: 0xB56ACA), dark: UIColor(hex: 0x9859AA))
            )
        case "manchester":
            City(
                skyTop: Color(light: UIColor(hex: 0x7DA8C0), dark: UIColor(hex: 0x3B5363)),
                skyBottom: Color(light: UIColor(hex: 0xE4D9C5), dark: UIColor(hex: 0x49433B)),
                silhouetteFar: Color(light: UIColor(hex: 0x8B9691), dark: UIColor(hex: 0x49514F)),
                silhouetteNear: Color(light: UIColor(hex: 0x505D5C), dark: UIColor(hex: 0x303939)),
                accent: Color(light: UIColor(hex: 0xE2A62F), dark: UIColor(hex: 0xBD8928))
            )
        case "kingston":
            City(
                skyTop: Color(light: UIColor(hex: 0x42BCE3), dark: UIColor(hex: 0x24667B)),
                skyBottom: Color(light: UIColor(hex: 0xFFD89A), dark: UIColor(hex: 0x55412F)),
                silhouetteFar: Color(light: UIColor(hex: 0x75A979), dark: UIColor(hex: 0x3C5A43)),
                silhouetteNear: Color(light: UIColor(hex: 0x37694C), dark: UIColor(hex: 0x244331)),
                accent: Color(light: UIColor(hex: 0xF2A53A), dark: UIColor(hex: 0xCB8731))
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
        case "capetown_signal_hill": dynamicPair(0xE7A56D, 0x355B6C, darkTop: 0x7A5940, darkBottom: 0x203946)
        case "singapore_rain": dynamicPair(0x6CB8C5, 0x31525D, darkTop: 0x3E6C75, darkBottom: 0x1D3238)
        case "singapore_supertree": dynamicPair(0x4E9B8A, 0x353B6B, darkTop: 0x315E56, darkBottom: 0x222643)
        case "capetown_bokaap": dynamicPair(0xE99375, 0x267B82, darkTop: 0x754A3D, darkBottom: 0x17474C)
        case "singapore_hawker": dynamicPair(0xE9A552, 0x287B70, darkTop: 0x7A5731, darkBottom: 0x18473F)
        case "dublin_library": dynamicPair(0x9A7952, 0x345641, darkTop: 0x554431, darkBottom: 0x1D3327)
        case "edinburgh_royal_mile": dynamicPair(0x77879C, 0x4C405F, darkTop: 0x424B58, darkBottom: 0x2A2435)
        case "vancouver_seawall": dynamicPair(0x5AA8C9, 0x2F665C, darkTop: 0x345F70, darkBottom: 0x1C3B36)
        case "auckland_harbour": dynamicPair(0x52B9CF, 0x236B78, darkTop: 0x316B77, darkBottom: 0x173F47)
        case "nairobi_karura": dynamicPair(0x8AA45C, 0x31543A, darkTop: 0x4C5B37, darkBottom: 0x1D3224)
        case "toronto_path": dynamicPair(0x7CA8B5, 0x355B66, darkTop: 0x465E66, darkBottom: 0x213941)
        case "sydney_harbour": dynamicPair(0x62B9D3, 0x315E81, darkTop: 0x376B7A, darkBottom: 0x1E3A50)
        case "neworleans_jazz": dynamicPair(0xD49B59, 0x593C68, darkTop: 0x735638, darkBottom: 0x33243D)
        case "manchester_record": dynamicPair(0x788C98, 0x4B3A36, darkTop: 0x455159, darkBottom: 0x2A2220)
        case "kingston_studio": dynamicPair(0xD8A64C, 0x2D6752, darkTop: 0x755B31, darkBottom: 0x1C3E32)
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

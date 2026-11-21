import SwiftUI

/// 伦敦以外 14 座城市的卡通配方。只保留每座城市最容易被孩子认出的一两处特征。
extension PuffCityCatalog {
    private static let glassBlues: [UInt32] = [0xD6E6FA, 0xC6DAF4, 0xE2ECFA, 0xBCD3F0]
    private static let glassTeals: [UInt32] = [0xCDEBEA, 0xB9DFE3, 0xDDF1F0, 0xC3E2EE]
    private static let pastelHouses: [UInt32] = [0xFFC9D6, 0xFFE3A3, 0xC8EEDB, 0xD7CCFF, 0xBFE2FF, 0xFFD2B3]

    static let manchester = PuffCityRecipe(
        id: "manchester", nameZh: "曼彻斯特", timeZoneID: "Europe/London", terrain: .water, celestialX: 420,
        backdrop: { p in
            p.farSkyline(seed: 21, maxHeight: 40)
        },
        landmarks: { p in
            p.terraces(from: 8, to: 150, colors: [0xE29A80, 0xD98A72, 0xE8A890], roof: 0x6E7598, seed: 3)
            p.domedHall(240, width: 110, height: 30, wall: 0xEBD3AC, dome: 0x9FB2D8)
            p.gothicClockTower(270, height: 92)
            p.brickMill(380, width: 80)
            p.skyscraper(512, width: 20, height: 124, color: 0xC6DAF4, top: .slant, seed: 5)
            p.towerCluster(from: 540, to: 712, seed: 23, maxHeight: 78, colors: glassBlues)
        },
        foreground: { p in
            p.roundTree(30, size: 1.1)
            p.lampPost(140)
            p.roundTree(210)
            p.lampPost(330)
            p.roundTree(450, size: 1.05)
            p.roundTree(640)
        },
        movers: { p in
            p.sail(.narrowboat, range: 120...420, period: 60)
            p.drive(.tram(0xFFC93C), period: 30)
        },
        iconX: 255
    )

    static let edinburgh = PuffCityRecipe(
        id: "edinburgh", nameZh: "爱丁堡", timeZoneID: "Europe/London", terrain: .land, celestialX: 330,
        backdrop: { p in
            p.mountain(600, width: 300, height: 70, color: 0xA9CBB0)
            p.mountain(670, width: 160, height: 48, color: 0x9CC0A6)
            p.farSkyline(seed: 31, maxHeight: 32, skip: [60...250])
        },
        landmarks: { p in
            p.castleRock(150)
            p.terraces(from: 250, to: 430, colors: [0xEADCC2, 0xE2D2B6, 0xF0E4CF], height: 34, roof: 0x5F6788, seed: 7)
            p.gothicSpire(470, height: 104)
            p.terraces(from: 510, to: 712, colors: [0xEADCC2, 0xE2D2B6, 0xF0E4CF], height: 30, roof: 0x5F6788, seed: 9)
        },
        foreground: { p in
            p.pineTree(24, size: 1.1)
            p.pineTree(44, size: 0.85)
            p.lampPost(240)
            p.roundTree(330)
            p.lampPost(520)
            p.pineTree(610)
            p.pineTree(700, size: 1.1)
        },
        movers: { p in
            p.drive(.bus(0xB4405A), period: 27)
        },
        iconX: 150
    )

    static let dublin = PuffCityRecipe(
        id: "dublin", nameZh: "都柏林", timeZoneID: "Europe/Dublin", terrain: .water, celestialX: 520,
        backdrop: { p in
            p.mountain(160, width: 420, height: 46, color: 0xB4DDB0)
            p.mountain(560, width: 380, height: 40, color: 0xA8D6A6)
            p.farSkyline(seed: 41, maxHeight: 30)
        },
        landmarks: { p in
            p.terraces(from: 8, to: 220, colors: [0xD98C6A, 0xCF7E5E, 0xE09A7A], height: 34, roof: 0x5F6788, seed: 2)
            p.footArchBridge(310, span: 118)
            p.needle(420, height: 136)
            p.domedHall(570, width: 140, height: 28, wall: 0xF1E8D6, dome: 0x8FD3B6)
        },
        foreground: { p in
            p.roundTree(30, size: 1.1)
            p.lampPost(150)
            p.roundTree(230)
            p.roundTree(470, size: 0.95)
            p.lampPost(520)
            p.roundTree(690, size: 1.1)
        },
        movers: { p in
            p.sail(.sailboat(0x3FC48C), range: 380...520, period: 52)
            p.drive(.bus(0xFFC93C), period: 26)
        },
        iconX: 365
    )

    static let newYork = PuffCityRecipe(
        id: "newyork", nameZh: "纽约", timeZoneID: "America/New_York", terrain: .water, celestialX: 420,
        backdrop: { p in
            p.farSkyline(seed: 51, minHeight: 30, maxHeight: 74)
        },
        landmarks: { p in
            p.liberty(48)
            p.towerCluster(from: 96, to: 200, seed: 53, minHeight: 44, maxHeight: 86, colors: glassBlues)
            p.empireState(226)
            p.towerCluster(from: 252, to: 286, seed: 57, minHeight: 50, maxHeight: 70, colors: glassBlues)
            p.chrysler(306)
            p.towerCluster(from: 326, to: 400, seed: 59, minHeight: 36, maxHeight: 76, colors: glassBlues)
            p.suspensionBridge(530, span: 230)
            p.skyscraper(690, width: 26, height: 128, color: 0xC6DAF4, top: .antenna, seed: 61)
        },
        foreground: { p in
            p.roundTree(140)
            p.lampPost(260)
            p.roundTree(400, size: 0.95)
            p.lampPost(620)
            p.roundTree(660)
        },
        movers: { p in
            p.sail(.ferry(0xFF9A3D), range: 80...330, period: 58)
            p.drive(.taxi, period: 18)
            p.drive(.taxi, period: 18, phase: 9)
        },
        iconX: 262
    )

    static let newOrleans = PuffCityRecipe(
        id: "neworleans", nameZh: "新奥尔良", timeZoneID: "America/Chicago", terrain: .water, celestialX: 470,
        backdrop: { p in
            p.farSkyline(seed: 61, maxHeight: 34)
            p.towerCluster(from: 420, to: 540, seed: 63, minHeight: 40, maxHeight: 82, colors: glassBlues)
        },
        landmarks: { p in
            p.cathedral(110)
            p.terraces(from: 150, to: 380, colors: pastelHouses, height: 30, roof: 0x6E7598, balconies: true, seed: 4)
            p.terraces(from: 560, to: 712, colors: pastelHouses, height: 28, roof: 0x6E7598, balconies: true, seed: 8)
        },
        foreground: { p in
            p.roundTree(30, size: 1.2)
            p.lampPost(180)
            p.roundTree(300, size: 1.1)
            p.lampPost(460)
            p.roundTree(600, size: 1.15)
        },
        movers: { p in
            p.sail(.paddleSteamer, range: 200...520, period: 70)
            p.drive(.tram(0x3FAF7A), period: 32)
        },
        iconX: 140
    )

    static let toronto = PuffCityRecipe(
        id: "toronto", nameZh: "多伦多", timeZoneID: "America/Toronto", terrain: .water, celestialX: 120,
        backdrop: { p in
            p.farSkyline(seed: 71, maxHeight: 50)
        },
        landmarks: { p in
            p.towerCluster(from: 20, to: 200, seed: 73, minHeight: 36, maxHeight: 80, colors: glassTeals)
            p.needleTower(250, height: 148, podRatio: 0.66, podWidth: 20)
            p.lowDome(330, width: 74)
            p.towerCluster(from: 380, to: 712, seed: 77, minHeight: 40, maxHeight: 100, colors: glassBlues)
        },
        foreground: { p in
            p.roundTree(50)
            p.lampPost(180)
            p.pineTree(300)
            p.lampPost(460)
            p.roundTree(580, size: 1.1)
            p.pineTree(690)
        },
        movers: { p in
            p.sail(.sailboat(0xFF6B7A), range: 60...240, period: 50)
            p.sail(.sailboat(0x4DA8FF), range: 400...600, period: 64, phase: 20)
            p.drive(.tram(0xE5484D), period: 30)
        },
        iconX: 250
    )

    static let vancouver = PuffCityRecipe(
        id: "vancouver", nameZh: "温哥华", timeZoneID: "America/Vancouver", terrain: .water, celestialX: 330,
        backdrop: { p in
            p.mountain(150, width: 320, height: 96, color: 0x9DB6D8, snow: true)
            p.mountain(400, width: 280, height: 78, color: 0xA8C0DE, snow: true)
            p.mountain(630, width: 300, height: 104, color: 0x93AED3, snow: true)
        },
        landmarks: { p in
            p.towerCluster(from: 20, to: 330, seed: 81, minHeight: 34, maxHeight: 86, colors: glassTeals)
            p.canadaPlace(410)
            p.needleTower(520, height: 92, podRatio: 0.85, podWidth: 22, color: 0xD9E0EE)
            p.towerCluster(from: 560, to: 712, seed: 83, minHeight: 34, maxHeight: 76, colors: glassTeals)
        },
        foreground: { p in
            p.pineTree(30, size: 1.15)
            p.pineTree(52, size: 0.9)
            p.lampPost(200)
            p.pineTree(350)
            p.lampPost(470)
            p.pineTree(640, size: 1.1)
            p.pineTree(664, size: 0.85)
        },
        movers: { p in
            p.sail(.ferry(0x3C8DDE), range: 200...360, period: 60)
            p.sail(.sailboat(0xFFC93C), range: 470...640, period: 48, phase: 12)
            p.drive(.bus(0x2E7FD6), period: 26)
        },
        iconX: 415
    )

    static let sydney = PuffCityRecipe(
        id: "sydney", nameZh: "悉尼", timeZoneID: "Australia/Sydney", terrain: .water, celestialX: 330,
        backdrop: { p in
            p.farSkyline(seed: 91, minHeight: 24, maxHeight: 62, skip: [80...240])
            p.needleTower(300, height: 132, podRatio: 0.78, podWidth: 18, podColor: 0xF5C451)
        },
        landmarks: { p in
            p.operaHouse(150)
            p.archBridge(540, span: 250)
        },
        foreground: { p in
            p.palmTree(30, size: 1.1)
            p.lampPost(230)
            p.palmTree(340, lean: -1)
            p.palmTree(690, size: 1.15)
        },
        movers: { p in
            p.sail(.ferry(0x2FA866), range: 240...420, period: 50)
            p.sail(.sailboat(0xFF6B7A), range: 600...700, period: 40, phase: 8)
            p.drive(.bus(0x2E7FD6), period: 26)
        },
        iconX: 150
    )

    static let melbourne = PuffCityRecipe(
        id: "melbourne", nameZh: "墨尔本", timeZoneID: "Australia/Melbourne", terrain: .water, celestialX: 560,
        backdrop: { p in
            p.farSkyline(seed: 101, minHeight: 24, maxHeight: 64)
            p.skyscraper(470, width: 22, height: 132, color: 0xC9D3E6, top: .gold, seed: 1)
        },
        landmarks: { p in
            p.domedHall(170, width: 150, height: 30, wall: 0xF5D28E, dome: 0x8FD3B6, clock: true)
            p.towerCluster(from: 270, to: 440, seed: 103, minHeight: 40, maxHeight: 92, colors: glassBlues)
            p.towerCluster(from: 500, to: 600, seed: 107, minHeight: 36, maxHeight: 70, colors: glassBlues)
        },
        foreground: { p in
            p.roundTree(40, size: 1.15)
            p.lampPost(280)
            p.roundTree(420)
            p.lampPost(520)
            p.roundTree(710)
        },
        movers: { p in
            p.ferrisWheel(655, centerY: 92, radius: 40)
            p.sail(.sailboat(0xFFC93C), range: 260...460, period: 54)
            p.drive(.tram(0x4CB37A), period: 32)
        },
        iconX: 175
    )

    static let auckland = PuffCityRecipe(
        id: "auckland", nameZh: "奥克兰", timeZoneID: "Pacific/Auckland", terrain: .water, celestialX: 440,
        backdrop: { p in
            p.mountain(560, width: 360, height: 56, color: 0x9CC2B2)
            p.farSkyline(seed: 111, maxHeight: 40, skip: [380...720])
        },
        landmarks: { p in
            p.towerCluster(from: 30, to: 200, seed: 113, minHeight: 36, maxHeight: 84, colors: glassTeals)
            p.needleTower(230, height: 156, podRatio: 0.7, podWidth: 20)
            p.towerCluster(from: 256, to: 340, seed: 117, minHeight: 32, maxHeight: 70, colors: glassTeals)
        },
        foreground: { p in
            p.palmTree(30)
            p.lampPost(200)
            p.roundTree(370)
            p.palmTree(540, lean: -1)
            p.roundTree(690, size: 1.1)
        },
        movers: { p in
            p.sail(.sailboat(0xFF6B7A), range: 380...520, period: 44)
            p.sail(.sailboat(0x4DA8FF), range: 480...640, period: 52, phase: 14)
            p.sail(.sailboat(0xFFC93C), range: 560...700, period: 38, phase: 6)
            p.drive(.bus(0x3FAF7A), period: 26)
        },
        iconX: 232
    )

    static let singapore = PuffCityRecipe(
        id: "singapore", nameZh: "新加坡", timeZoneID: "Asia/Singapore", terrain: .water, celestialX: 520,
        backdrop: { p in
            p.farSkyline(seed: 121, minHeight: 34, maxHeight: 76)
        },
        landmarks: { p in
            p.towerCluster(from: 20, to: 250, seed: 123, minHeight: 50, maxHeight: 104, colors: glassBlues)
            p.marinaBaySands(360)
            p.supertree(470, height: 58)
            p.supertree(500, height: 76, color: 0xFF9BC8)
            p.supertree(530, height: 50, color: 0x9FD8FF)
        },
        foreground: { p in
            p.palmTree(36, size: 1.1)
            p.lampPost(200)
            p.palmTree(300, lean: -1)
            p.palmTree(560)
            p.palmTree(700, size: 1.1, lean: -1)
        },
        movers: { p in
            p.ferrisWheel(640, centerY: 90, radius: 42)
            p.sail(.ferry(0xFF9A3D), range: 160...440, period: 56)
            p.drive(.bus(0x8A62E8), period: 26)
        },
        iconX: 400
    )

    static let capeTown = PuffCityRecipe(
        id: "capetown", nameZh: "开普敦", timeZoneID: "Africa/Johannesburg", terrain: .water, celestialX: 610,
        backdrop: { p in
            p.mountain(320, width: 560, height: 96, color: 0x8FA8CB, flatTop: 240)
            p.mountain(640, width: 170, height: 88, color: 0x9BB2D2)
            p.farSkyline(seed: 131, maxHeight: 30)
        },
        landmarks: { p in
            p.terraces(from: 20, to: 240, colors: [0xFF8FB1, 0xFFD36B, 0xA7E07B, 0x7CC7FF, 0xB9A2FF, 0xFFA36B], height: 26, roof: 0x6E7598, seed: 5)
            p.towerCluster(from: 280, to: 440, seed: 133, minHeight: 26, maxHeight: 58, colors: glassBlues)
            p.lighthouse(600)
        },
        foreground: { p in
            p.palmTree(30, size: 1.1)
            p.lampPost(260)
            p.palmTree(470, lean: -1)
            p.palmTree(690, size: 1.1)
        },
        movers: { p in
            p.sail(.sailboat(0xFF6B7A), range: 260...440, period: 46)
            p.sail(.ferry(0x37A0D8), range: 460...560, period: 40, phase: 10)
            p.drive(.bus(0x37A0D8), period: 26)
        },
        iconX: 300
    )

    static let nairobi = PuffCityRecipe(
        id: "nairobi", nameZh: "内罗毕", timeZoneID: "Africa/Nairobi", terrain: .land, celestialX: 220,
        backdrop: { p in
            p.mountain(130, width: 300, height: 40, color: 0xB6CFAE)
            p.mountain(320, width: 260, height: 32, color: 0xAECAA8)
            p.farSkyline(seed: 141, minHeight: 20, maxHeight: 54, skip: [0...340])
        },
        landmarks: { p in
            p.towerCluster(from: 380, to: 460, seed: 143, minHeight: 40, maxHeight: 84, colors: glassBlues)
            p.kicc(500)
            p.towerCluster(from: 560, to: 712, seed: 147, minHeight: 36, maxHeight: 90, colors: glassBlues)
        },
        foreground: { p in
            p.acaciaTree(40, size: 1.2)
            p.giraffe(120, size: 1.05)
            p.giraffe(170, size: 0.8, facing: -1)
            p.acaciaTree(260)
            p.acaciaTree(640, size: 0.9)
        },
        movers: { p in
            p.drive(.bus(0xFF7A3D), period: 26)
        },
        iconX: 150
    )

    static let kingston = PuffCityRecipe(
        id: "kingston", nameZh: "金斯敦", timeZoneID: "America/Jamaica", terrain: .water, celestialX: 440,
        backdrop: { p in
            p.mountain(200, width: 420, height: 100, color: 0x7FA8CC)
            p.mountain(540, width: 380, height: 80, color: 0x8DB5D6)
            p.mountain(360, width: 200, height: 60, color: 0x9DC6A6)
        },
        landmarks: { p in
            p.terraces(from: 20, to: 260, colors: [0xFFD36B, 0x7FD8B0, 0xFF9BB5, 0x8FCBFF, 0xFFB27A], height: 22, roof: 0x6E7598, seed: 6)
            p.towerCluster(from: 300, to: 440, seed: 153, minHeight: 26, maxHeight: 52, colors: glassBlues)
            p.lighthouse(620, stripe: 0xFF6B6B)
        },
        foreground: { p in
            p.palmTree(30, size: 1.15)
            p.palmTree(60, size: 0.9, lean: -1)
            p.lampPost(280)
            p.palmTree(480)
            p.palmTree(700, size: 1.1, lean: -1)
        },
        movers: { p in
            p.sail(.sailboat(0xFFC93C), range: 300...500, period: 46)
            p.sail(.ferry(0x3FC48C), range: 480...580, period: 40, phase: 10)
            p.drive(.bus(0xFFC93C), period: 26)
        },
        iconX: 200
    )
}

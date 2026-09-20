import Foundation

/// Stored character casting, shared by persistence and speech without feature dependencies.
public enum CharacterReadingVoice: String, Codable, CaseIterable, Sendable {
    case m1 = "M1", m2 = "M2", m3 = "M3", m4 = "M4", m5 = "M5"
    case f1 = "F1", f2 = "F2", f3 = "F3", f4 = "F4", f5 = "F5"

    public static let narrator: Self = .f5

    public static func isBritish(_ nationality: String) -> Bool {
        let value = nationality.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["british", "english", "scottish", "welsh", "northern irish", "uk", "united kingdom", "英国", "英格兰", "苏格兰", "威尔士", "北爱尔兰"].contains { value == $0 || value.hasPrefix($0 + " ") }
    }

    /// Version-stable fallback for old cards. Once saved, the explicit property wins.
    public static func assigned(name: String, gender: String, nationality: String, age: Int = 25) -> Self {
        let male = gender.lowercased() == "male"
        if isBritish(nationality) { return male ? .m5 : .f5 }
        switch name {
        case "Oliver", "Oliver Bennett": return .m5
        case "Ruby", "Ruby Walker": return .f3
        case "Marcus", "Marcus Rivera": return .m3
        default: break
        }
        if age >= 50 { return male ? .m4 : .f4 }
        // Identity-based variation within the appropriate gender pool, never a random launch seed.
        let pool: [Self] = male ? [.m1, .m2, .m3, .m4] : [.f1, .f2, .f3, .f4]
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in name.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return pool[Int(hash % UInt64(pool.count))]
    }
}

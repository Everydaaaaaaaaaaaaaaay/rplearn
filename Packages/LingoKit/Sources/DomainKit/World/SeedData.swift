import Foundation
import PersistenceKit

/// 随包种子数据加载（main_characters.json）。
public enum SeedData {
    public static func mainCharacterCards(url: URL) throws -> [CharacterCard] {
        struct File: Decodable {
            let characters: [CharacterCard]
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).characters
    }
}

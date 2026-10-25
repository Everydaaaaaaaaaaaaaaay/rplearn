import BackendKit
import Foundation
@testable import LearningFeature
import Testing

private let corpusURL: URL = {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root.appending(path: "build/learning-corpus-audit/public-units.json")
}()

// Opt-in companion to learning-published-corpus.test.ts; consumes its public DTOs.
@Suite("Published corpus iOS compatibility", .enabled(if: FileManager.default.fileExists(atPath: corpusURL.path)))
struct LearningPublishedCorpusTests {
    @Test("Every public group and response decodes and retains its input and answer identities")
    func everyPublishedQuestion() throws {
        let units = try JSONDecoder().decode([LearningUnit].self, from: Data(contentsOf: corpusURL))
        #expect(units.count > 1000)
        var count = 0
        for unit in units {
            #expect(!unit.questions.isEmpty)
            #expect(Set(unit.questions.map(\.id)).count == unit.questions.count)
            if let projection = LearningPracticeProjection(unit: unit) {
                #expect(projection.task.sections.flatMap(\.questions).map(\.id) == unit.questions.map(\.id))
                for section in projection.task.sections {
                    #expect(!section.text.isEmpty)
                    for q in section.questions {
                        let source = try #require(unit.questions.first { $0.id == q.id })
                        #expect(q.options.count == (source.options ?? []).count)
                        #expect(Set(projection.optionIDs[q.id]?.values.map { $0 } ?? []) == Set((source.options ?? []).map(\.id)))
                    }
                }
            }
            for q in unit.questions {
                let plan = LearningReadingPlan(unit: unit, question: q)
                #expect(!plan.originalText.isEmpty)
                switch q.type {
                case .choice, .listeningChoice:
                    let options = try #require(q.options)
                    #expect(options.count >= 2)
                    #expect(options.allSatisfy { !$0.text.isEmpty || $0.imageAssetId != nil })
                    #expect(Set(options.map(\.id)).count == options.count)
                case .completion:
                    #expect(!q.prompt.isEmpty)
                default:
                    Issue.record("No public original interaction expected here: \(unit.id)/\(q.id)/\(q.type)")
                }
                count += 1
            }
        }
        #expect(count > 11000)
    }
}

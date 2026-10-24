import Foundation

/// Keep the actual directions and question, but avoid rendering an identical block twice.
/// This applies to all question kinds, including listening, matching and word-block controls.
enum LearningQuestionText {
    static func showsPrompt(_ prompt: String, instruction: String, material: String?) -> Bool {
        let question = normalized(prompt)
        guard !question.isEmpty else { return false }
        return question != normalized(instruction) && (material.map { question != normalized($0) } ?? true)
    }
    private static func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

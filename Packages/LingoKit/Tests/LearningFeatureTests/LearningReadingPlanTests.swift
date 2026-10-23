import BackendKit
import Foundation
@testable import LearningFeature
import Testing

@Suite("材料分篇与作答节奏")
struct LearningReadingPlanTests {
    private func unit(material: String, prompts: [String], family: String = "reading_choice",
                      options: [String] = ["A. One", "B. Two", "C. Three"]) throws -> LearningUnit {
        let object: [String: Any] = [
            "id": "test.reading", "version": 1, "schemaVersion": 1, "roleKey": "companion",
            "level": "junior2", "title": "阅读", "summary": "阅读", "scene": "练习",
            "estimatedMinutes": 5, "goalIds": ["test.reading"], "beats": [],
            "originalGroup": ["id": "test.reading", "family": family, "label": "阅读"],
            "questions": prompts.enumerated().map { index, prompt in
                ["id": "q\(index + 1)", "type": "choice", "goalId": "test.reading",
                 "instruction": "阅读并选择", "prompt": prompt, "hint": "回看材料", "material": material,
                 "options": options.enumerated().map { ["id": "o\($0.offset)", "text": $0.element] }] as [String: Any]
            }
        ]
        return try JSONDecoder().decode(LearningUnit.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("显式题号范围对应文章；同篇共享阅读身份，下一篇不混入前文")
    func groupedReading() throws {
        let source = "Read both articles.\n\nA组（第1—2题）\n\nFirst article.\n\nSecond paragraph.\n\nB组（第3—4题）\n\nAnother article."
        let unit = try unit(material: source, prompts: ["One?", "Two?", "Three?", "Four?"])
        let plans = unit.questions.map { LearningReadingPlan(unit: unit, question: $0) }
        #expect(plans.map(\.preferredSectionID) == ["A", "A", "B", "B"])
        #expect(plans[0].sections == plans[1].sections)
        #expect(plans[0].sections[0].text == "First article.\n\nSecond paragraph.")
        #expect(plans[2].sections[1].text == "Another article.")
        #expect(plans[1].progress(questionID: "q2") == "本篇第 2 / 2 题")
        #expect(plans[0].introduction == "Read both articles.")
        #expect(plans.allSatisfy { $0.usesPane })
    }

    @Test("两篇独立材料只统计本篇题目，不把另一篇混入阅读和计数")
    func separateMaterials() throws {
        let base = try unit(material: "First passage.", prompts: ["One?", "Two?", "Three?", "Four?"])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        var questions = object["questions"] as! [[String: Any]]
        for index in 2..<4 { questions[index]["material"] = "Second passage." }
        object["questions"] = questions
        let combined = try JSONDecoder().decode(LearningUnit.self, from: JSONSerialization.data(withJSONObject: object))
        let plan = LearningReadingPlan(unit: combined, question: combined.questions[2])
        #expect(plan.originalText == "Second passage.")
        #expect(plan.sections[0].questionIDs == ["q3", "q4"])
        #expect(plan.progress(questionID: "q3") == "本篇第 1 / 2 题")
        #expect(plan.progress(questionID: "q4") == "本篇第 2 / 2 题")
    }

    @Test("Passage前缀定位；跨文比较不根据题中提到的字母猜材料")
    func passagesAndCrossText() throws {
        let unit = try unit(material: "Read.\n\nPassage 1\n\nFirst text.\n\nPassage 2\n\nNext text.",
                            prompts: ["Passage 1 — Why?", "Passage 2 — How?"])
        #expect(LearningReadingPlan(unit: unit, question: unit.questions[1]).preferredSectionID == "Passage 2")
        let comparison = try self.unit(material: "Compare all views.\n\nA — Nina Cole\n\nHer view.\n\nB — Omar Finch\n\nHis view.",
                                       prompts: ["Who disagrees with reviewer A?", "Who agrees with B?"], family: "cross_text_matching")
        let plan = LearningReadingPlan(unit: comparison, question: comparison.questions[0])
        #expect(plan.sections.count == 2)
        #expect(plan.preferredSectionID == nil)
        #expect(plan.originalText.contains("His view."))
    }

    @Test("旧快照工具选项只显示名字；普通理解题和插段题不截断答案内容")
    func namedChoicesAndParagraphAnswers() throws {
        let descriptions = ["A. StoryTrack offers short stories. You can read them and check new words.",
                            "B. SpeakPair gives you situations. You record your answer and try again.",
                            "C. ListenReplay contains dialogues. You can replay parts and check the script."]
        let source = "Read all tools.\n\n" + descriptions.joined(separator: "\n\n")
        let tool = try unit(material: source, prompts: ["Ada’s need?", "Leo’s need?"], options: descriptions)
        let plan = LearningReadingPlan(unit: tool, question: tool.questions[0])
        #expect(plan.optionLabels == ["o0": "A. StoryTrack", "o1": "B. SpeakPair", "o2": "C. ListenReplay"])
        #expect(plan.sections[0].text == source)
        #expect(tool.questions[0].options?.map(\.text) == descriptions)
        let paragraphs = ["A. Instead of leaving, she returned to the room.",
                          "B. When the room opened, a visitor asked about the map.",
                          "C. At first, the map seemed difficult to read."]
        let passage = "The complete article with gap (1) ____.\n\nCandidates\n\n" + paragraphs.joined(separator: "\n\n")
        let insertion = try unit(material: passage, prompts: ["第1处", "第2处"], family: "paragraph_gap_insertion", options: paragraphs)
        let insertionPlan = LearningReadingPlan(unit: insertion, question: insertion.questions[0])
        #expect(insertionPlan.optionLabels == ["o0": "段落 A", "o1": "段落 B", "o2": "段落 C"])
        #expect(!insertionPlan.sections[0].text.contains(paragraphs[0]))
        #expect(insertionPlan.sections[1].text == String(paragraphs[0].dropFirst(3)))
        #expect(insertionPlan.preferredSectionID == "whole")
        #expect(insertionPlan.originalText == passage)
        #expect(insertion.questions[0].options?.map(\.text) == paragraphs)
    }

    @Test("不确定的边界保留全文；对话、表格和短材料不被字母选项误分篇")
    func conservativeFallback() throws {
        let material = "A: Hello.\nB: Hi.\n\n| Day | Time\n\n| Monday | 9:00"
        let unit = try unit(material: material, prompts: ["When?"])
        let plan = LearningReadingPlan(unit: unit, question: unit.questions[0])
        #expect(plan.sections.count == 1)
        #expect(plan.sections[0].text == material)
        #expect(!plan.usesPane)
        let duplicate = try self.unit(material: "Passage 1\n\nFirst.\n\nPassage 1\n\nSecond.", prompts: ["Why?"])
        #expect(LearningReadingPlan(unit: duplicate, question: duplicate.questions[0]).sections[0].text == duplicate.questions[0].material)
    }

    @Test("带小写连接词的明确活动标题可以缩短，普通长答案不作猜测")
    func activityTitles() throws {
        let options = ["A. Voices of the Town: Older residents bring photographs and discuss daily life in the town.",
                       "B. Makers' Gift Table: Students work with clean old paper and small wooden pieces to make frames.",
                       "C. Round-table English: Students discuss a short English story in pairs and small groups."]
        let activity = try unit(material: options.joined(separator: "\n\n"), prompts: ["Which activity?", "Which fits?"], options: options)
        let plan = LearningReadingPlan(unit: activity, question: activity.questions[0])
        #expect(plan.optionLabels["o0"] == "A. Voices of the Town")
        let ordinary = try unit(material: "Read this article.", prompts: ["Why?", "How?"], options: options)
        #expect(LearningReadingPlan(unit: ordinary, question: ordinary.questions[0]).optionLabels.isEmpty)
    }
}

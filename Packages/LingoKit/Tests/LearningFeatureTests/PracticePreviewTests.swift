#if DEBUG
import Foundation
@testable import LearningFeature
import Testing

@Suite("Task-based practice preview")
@MainActor
struct PracticePreviewTests {
    private func model() -> PracticePreviewModel {
        PracticePreviewModel(defaults: UserDefaults(suiteName: "PracticePreviewTests.\(UUID().uuidString)")!)
    }

    @Test("Whole passages keep balanced task sizes and matching blank/option structure")
    func fixtures() {
        let tasks = PracticePreviewFixtures.tasks
        #expect(tasks.map(\.count) == [7, 15, 15])
        #expect(tasks[0].sections.map { $0.questions.count } == [3, 4])
        #expect(tasks[1].sections[0].questions.count == 15)
        #expect(tasks[2].sections.map { $0.questions.count } == [5, 10])
        for section in tasks.flatMap(\.sections) {
            #expect(!section.text.isEmpty)
            for (index, question) in section.questions.enumerated() {
                #expect(section.paragraphs.indices.contains(question.evidenceParagraph))
                if section.kind != .reading { #expect(section.text.contains("____\(index + 1)____")) }
                if section.kind == .insertion { #expect(question.options.count == 7) }
                if let key = question.correctOption { #expect(question.options.contains { $0.id == key }) }
            }
        }
    }

    @Test("No answer is graded before an entire passage is submitted; submitted work is locked")
    func feedbackBoundary() {
        let model = model(); model.start()
        let first = model.question
        model.setAnswer(first.correctOption!)
        #expect(model.result(for: first) == nil)
        model.submitSection()
        #expect(!model.draft.isReviewing)
        for index in model.section.questions.indices {
            model.selectQuestion(index); model.setAnswer(model.question.correctOption!)
        }
        #expect(model.section.questions.allSatisfy { model.result(for: $0) == nil })
        model.submitSection()
        #expect(model.draft.isReviewing)
        #expect(model.result(for: first) == .correct)
        model.setAnswer("wrong")
        #expect(model.answer(for: first) == first.correctOption)
        model.finishReview()
        #expect(model.draft.sectionIndex == 1)
        #expect(!model.draft.isReviewing)
        #expect(model.result(for: model.question) == nil)
    }

    @Test("Shared sentence moves between gaps and clearing it leaves both unfilled")
    func insertionReassignment() {
        let model = model(); model.selectTask(2); model.start()
        model.setAnswer("A"); model.selectQuestion(1); model.setAnswer("A")
        #expect(model.answer(for: model.section.questions[0]).isEmpty)
        #expect(model.answer(for: model.question) == "A")
        model.setAnswer("")
        #expect(model.answeredCount == 0)
    }

    @Test("Draft reload restores answers, flags, current passage, review state and reading offset")
    func resume() {
        let defaults = UserDefaults(suiteName: "PracticePreviewTests.\(UUID().uuidString)")!
        let model = PracticePreviewModel(defaults: defaults)
        model.start(); model.setAnswer("B"); model.toggleFlag(); model.selectQuestion(2)
        model.rememberReadingOffset(485, for: model.section.id)
        model.goToCover()
        let reloaded = PracticePreviewModel(defaults: defaults)
        #expect(reloaded.draft.questionIndex == 2)
        #expect(reloaded.draft.answers == model.draft.answers)
        #expect(reloaded.draft.flagged == model.draft.flagged)
        #expect(reloaded.draft.offsets[model.section.id] == 485)
        reloaded.start()
        #expect(reloaded.page == .work)
        reloaded.selectTask(1)
        #expect(!reloaded.hasProgress)
        reloaded.selectTask(0)
        #expect(reloaded.draft.questionIndex == 2)
        for index in reloaded.section.questions.indices {
            reloaded.selectQuestion(index); reloaded.setAnswer(reloaded.question.correctOption!)
        }
        reloaded.submitSection()
        let reviewing = PracticePreviewModel(defaults: defaults)
        #expect(reviewing.draft.isReviewing)
        #expect(reviewing.result(for: reviewing.question) == .correct)
    }

    @Test("Unlisted grammar expressions remain reviewable, with whitespace-normalized accepted answers")
    func unlistedGrammar() {
        let model = model(); model.selectTask(2); model.start()
        for index in model.section.questions.indices {
            model.selectQuestion(index); model.setAnswer(model.question.correctOption!)
        }
        model.submitSection(); model.finishReview()
        #expect(model.section.kind == .grammar)
        model.setAnswer("   ")
        #expect(model.answeredCount == 0)
        for index in model.section.questions.indices {
            model.selectQuestion(index)
            model.setAnswer(index == 1 ? "unlisted expression" : "  \(model.question.acceptedAnswers[0].uppercased())  ")
        }
        model.submitSection()
        #expect(model.result(for: model.section.questions[0]) == .correct)
        #expect(model.result(for: model.section.questions[1]) == .needsReview)
        model.finishReview()
        #expect(model.draft.completed)
        #expect(model.correctCount == 14)
        #expect(model.needsReviewCount == 1)
        model.revisit(section: 0, question: 3)
        model.finishReview()
        #expect(model.page == .summary)
        #expect(model.draft.completed)
    }
}
#endif

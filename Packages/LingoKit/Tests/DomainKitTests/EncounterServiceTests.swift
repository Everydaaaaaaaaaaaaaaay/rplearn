import Foundation
import LLMKit
import Testing
@testable import DomainKit
@testable import PersistenceKit

@Suite("EncounterService")
struct EncounterServiceTests {
    private let region = Region(
        id: "london", nameEn: "London", nameZh: "伦敦", countryCode: "GB",
        countryNameEn: "United Kingdom", countryNameZh: "英国", taglineZh: "-", landmarks: [], activities: []
    )

    private let validJSON = """
    {"name":"Poppy Hale","age":27,"gender":"female","nationality":"British",
    "occupation":"florist","hobbies":["园艺","骑行"],"appearance":"red coat",
    "personality":"warm, a bit forgetful","speech_style":"soft and quick",
    "background":"Runs a flower stall near the market. Loves rainy days.",
    "opening_line":"Oh! Sorry, mind the buckets - are you lost, love?"}
    """

    @Test("掷骰边界：偶遇概率 35%，来源 60/30/10")
    func rolls() {
        #expect(EncounterService.shouldEncounter(roll: 0))
        #expect(EncounterService.shouldEncounter(roll: 0.349))
        #expect(!EncounterService.shouldEncounter(roll: 0.35))
        #expect(EncounterService.shouldEncounter(roll: 0.54, probability: 0.55))
        #expect(!EncounterService.shouldEncounter(roll: 0.55, probability: 0.55))
        #expect(EncounterService.rollOrigin(roll: 0) == .local)
        #expect(EncounterService.rollOrigin(roll: 0.599) == .local)
        #expect(EncounterService.rollOrigin(roll: 0.6) == .domestic)
        #expect(EncounterService.rollOrigin(roll: 0.899) == .domestic)
        #expect(EncounterService.rollOrigin(roll: 0.9) == .foreigner)
        #expect(EncounterService.rollOrigin(roll: 0.999) == .foreigner)
    }

    @Test("LLM 生成成功：解码 + 校验 + regionID 绑定当前地区")
    func generationSuccess() async {
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.tier == .balanced)
            #expect(request.temperature == 1.0)
            return self.validJSON
        })
        let service = EncounterService(llm: mock)
        let encounter = await service.generateEncounter(
            origin: .local, region: region, userLevel: .junior3, existingNames: []
        )
        #expect(!encounter.isFallback)
        #expect(encounter.card.name == "Poppy Hale")
        #expect(encounter.card.regionID == "london")
        #expect(encounter.card.hobbies == ["园艺", "骑行"])
        #expect(encounter.openingLine.contains("Sorry"))
    }

    @Test("姓名重复触发重试，仍重复则回退模板卡")
    func duplicateNameFallsBack() async {
        let mock = MockLLMProvider(completeHandler: { _ in self.validJSON })
        let service = EncounterService(llm: mock)
        let encounter = await service.generateEncounter(
            origin: .local, region: region, userLevel: .junior3,
            existingNames: ["Poppy Hale"] // 与生成结果重名
        )
        #expect(encounter.isFallback)
        #expect(encounter.card.name != "Poppy Hale")
        #expect(!encounter.openingLine.isEmpty)
    }

    @Test("模型返回英文爱好时重试并回退中文模板")
    func englishHobbiesFallBackToLocalizedTemplate() async {
        let englishJSON = validJSON.replacingOccurrences(
            of: #""hobbies":["园艺","骑行"]"#,
            with: #""hobbies":["gardening","cycling"]"#
        )
        let mock = MockLLMProvider(completeHandler: { _ in englishJSON })
        let encounter = await EncounterService(llm: mock).generateEncounter(
            origin: .local,
            region: region,
            userLevel: .junior3,
            existingNames: []
        )

        #expect(encounter.isFallback)
        #expect(encounter.card.hobbies == ["烹饪", "骑行", "经典电影"])
    }

    @Test("LLM 全挂时回退模板卡，且避开已有姓名")
    func llmFailureFallsBack() async {
        let mock = MockLLMProvider(completeHandler: { _ in
            throw LLMError.http(status: 500, message: "down")
        })
        let service = EncounterService(llm: mock)
        let encounter = await service.generateEncounter(
            origin: .foreigner, region: region, userLevel: .senior1,
            existingNames: ["Sam Porter"]
        )
        #expect(encounter.isFallback)
        #expect(encounter.card.name != "Sam Porter")
        #expect(encounter.card.nationality != region.countryNameEn) // foreigner
    }

    @Test("生成提示词包含来源约束与姓名去重")
    func promptContent() {
        let prompt = EncounterService.generationPrompt(
            origin: .domestic, region: region, userLevel: .junior3, existingNames: ["A", "B"]
        )
        #expect(prompt.contains("ANOTHER city"))
        #expect(prompt.contains("Do NOT use these names: A, B"))
        #expect(prompt.contains("Simplified Chinese UI tag"))
    }
}

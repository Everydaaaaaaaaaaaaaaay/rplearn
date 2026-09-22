import Foundation

public struct LearningTask: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let skill: LearningSystemPolicy.Skill
    public let band: Int
    public let topic: String
    public let instruction: String
    public static var bank: [Self] {
        let scenes: [(String, String, String, String)] = [
            ("travel", "周末出游", "海边和公园", "原计划地点临时关闭"),
            ("food", "准备晚餐", "家里做饭和去餐厅", "一位朋友临时不能吃辣"),
            ("hobbies", "安排休闲活动", "看电影和读书", "原定活动临时取消"),
            ("study", "准备一次学习活动", "独自学习和小组学习", "伙伴临时无法参加"),
            ("work", "安排团队活动", "线上交流和现场交流", "时间突然缩短一半"),
            ("daily_life", "安排一天的日常生活", "早点出门和晚点出门", "突然开始下雨"),
            ("travel", "参观博物馆", "看绘画展和看历史展", "原定展厅临时关闭"),
            ("travel", "安排山间短途旅行", "坐缆车和走山路", "同行者的脚受伤了"),
            ("food", "准备野餐", "带三明治和带沙拉", "天气变得很热"),
            ("food", "给朋友做早餐", "煮粥和烤面包", "烤箱突然坏了"),
            ("hobbies", "开始一种新爱好", "画画和摄影", "可用预算减少了"),
            ("hobbies", "度过雨天的下午", "拼图和做手工", "朋友带来了年幼的孩子"),
            ("study", "为英语测验做准备", "阅读笔记和做练习题", "考试提前了一天"),
            ("study", "完成一项小组作业", "分工写作和一起讨论", "资料临时无法打开"),
            ("work", "向同事介绍一个想法", "画示意图和做幻灯片", "投影设备无法使用"),
            ("work", "安排一次工作交接", "写文档和现场演示", "接手的人在另一个城市"),
            ("daily_life", "购买一件日用品", "去附近小店和去远处超市", "公共交通暂停了"),
            ("daily_life", "整理住处", "先整理书桌和先整理衣柜", "只有半小时空闲")
        ]
        return LearningSystemPolicy.Skill.allCases.flatMap { skill in
            (1...3).flatMap { band in scenes.enumerated().map { sceneIndex, values in
                let (topic, scene, options, change) = values
                let instruction: String
                switch skill {
                case .preference:
                    instruction = band == 1 ? "聊聊\(scene)：说出你的选择和一个理由。" : band == 2 ? "聊聊\(scene)：比较\(options)，说说你的取舍。" : "聊聊\(scene)：\(change)，你会怎样调整选择？为什么？"
                case .experience:
                    instruction = band == 1 ? "聊聊你上次\(scene)时发生的一件事，加一个细节。" : band == 2 ? "聊聊你上次\(scene)的经历，讲清至少两件事的先后顺序。" : "聊聊你上次\(scene)遇到的问题，解释原因、结果，并说出从中学到什么或下次会怎样调整。"
                case .planning:
                    instruction = band == 1 ? "聊聊\(scene)：你准备做什么？什么时候或在哪里？" : band == 2 ? "聊聊\(scene)：讲清两个安排以及它们的顺序。" : "聊聊\(scene)：\(change)，提出一个可行的替代安排。"
                case .clarification:
                    instruction = band == 1 ? "聊聊\(scene)：假设没有听懂对方提到的时间，请说清哪里不懂并请求解释。" : band == 2 ? "聊聊\(scene)：假设对方没理解你的计划，用另一种说法解释原意。" : "聊聊\(scene)：假设对方误以为你已答应\(options.components(separatedBy: "和").first ?? scene)，请纠正这个误解，并确认双方理解一致。"
                }
                return Self(id: "task-v1-\(skill.rawValue)-\(band)-\(topic)-\(sceneIndex)", skill: skill, band: band, topic: topic, instruction: instruction)
            } }
        }
    }
}

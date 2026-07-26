import Foundation

public extension CharacterCard {
    /// 面向中文界面展示的爱好标签。
    ///
    /// 新生成的偶遇角色会直接保存中文标签；映射表用于兼容旧版本已经落库的
    /// 英文角色卡，原始值仍保留给角色设定和跨端同步使用。
    var localizedHobbies: [String] {
        hobbies.map(CharacterHobbyLocalization.localizedTitle)
    }
}

enum CharacterHobbyLocalization {
    private static let exactTitles: [String: String] = [
        "making handmade pasta": "做手工意面",
        "collecting vinyl records": "收藏黑胶唱片",
        "playing table tennis": "打乒乓球",
        "gardening": "园艺",
        "cycling": "骑行",
        "cooking": "烹饪",
        "old movies": "经典电影",
        "photography": "摄影",
        "film photography": "胶片摄影",
        "street photography": "街头摄影",
        "board games": "桌游",
        "hiking": "徒步",
        "sketching": "素描",
        "coffee tasting": "咖啡品鉴",
        "coffee brewing": "手冲咖啡",
        "vinyl records": "黑胶收藏",
        "football": "足球",
        "basketball": "篮球",
        "tennis": "网球",
        "table tennis": "乒乓球",
        "badminton": "羽毛球",
        "surfing": "冲浪",
        "swimming": "游泳",
        "running": "跑步",
        "rock climbing": "攀岩",
        "camping": "露营",
        "stargazing": "观星",
        "birdwatching": "观鸟",
        "indie music": "独立音乐",
        "live music": "现场音乐",
        "classical music": "古典音乐",
        "jazz": "爵士乐",
        "music": "音乐",
        "karaoke": "唱歌",
        "playing guitar": "弹吉他",
        "playing piano": "弹钢琴",
        "playing drums": "打鼓",
        "reading": "阅读",
        "books": "阅读",
        "poetry": "诗歌",
        "creative writing": "创意写作",
        "calligraphy": "书法",
        "painting": "绘画",
        "drawing": "绘画",
        "pottery": "陶艺",
        "making ceramics": "做陶艺",
        "knitting": "编织",
        "sewing": "缝纫",
        "woodworking": "木工",
        "flower arranging": "插花",
        "baking": "烘焙",
        "baking sourdough": "烤酸面包",
        "tea tasting": "品茶",
        "wine tasting": "葡萄酒品鉴",
        "craft beer": "精酿啤酒",
        "street food": "街头美食",
        "travel": "旅行",
        "traveling": "旅行",
        "museums": "逛博物馆",
        "art galleries": "逛画廊",
        "video games": "电子游戏",
        "chess": "国际象棋",
        "yoga": "瑜伽",
        "volunteering": "志愿活动",
        "collecting postcards": "收藏明信片",
        "listening to podcasts": "听播客",
        "watching old movies": "看老电影",
    ]

    static func localizedTitle(_ rawTitle: String) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return exactTitles[title.lowercased()] ?? title
    }
}

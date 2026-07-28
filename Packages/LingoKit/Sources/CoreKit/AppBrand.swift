/// 应用品牌的统一入口，避免各功能模块散落硬编码。
public enum AppBrand {
    /// 面向中文用户展示的产品名称。
    public static let displayName = "咕游记"

    /// 面向国际化场景与会员产品展示的英文名称。
    public static let englishName = "Coovingo"

    /// 品牌短句，统一用于欢迎页与轻量品牌露出。
    public static let tagline = "把英语说进旅程里"

    /// 吉祥物既是旅行向导，也是独立于角色的英语建议来源。
    public static let mascotName = "咕咕"
    public static let mascotRole = "旅行向导 · 英语搭子"
}

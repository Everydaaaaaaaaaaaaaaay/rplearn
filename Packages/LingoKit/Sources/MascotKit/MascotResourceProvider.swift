import Foundation

/// 一个已解析、已校验，可直接交给任意渲染后端的资产包。
public struct MascotAssetPackage: Sendable {
    public let id: MascotAssetID
    public let modelURL: URL
    public let catalog: MascotAnimationCatalog

    public init(id: MascotAssetID, modelURL: URL, catalog: MascotAnimationCatalog) {
        self.id = id
        self.modelURL = modelURL
        self.catalog = catalog
    }
}

/// 对资产来源的最小能力约束。生产环境、预览和远端缓存都能提供自己的实现。
public protocol MascotResourceProviding: Sendable {
    func loadAsset(_ id: MascotAssetID) throws -> MascotAssetPackage
}

public enum MascotResourceError: LocalizedError, Equatable {
    case unsupportedAsset(MascotAssetID)
    case missingResource(String)
    case unsupportedSchema(String)
    case invalidCatalog(String)
    case invalidModelFilename(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedAsset(id):
            "不支持的吉祥物资产：\(id.rawValue)"
        case let .missingResource(name):
            "吉祥物资源缺失：\(name)"
        case let .unsupportedSchema(schema):
            "不支持的吉祥物动画目录版本：\(schema)"
        case let .invalidCatalog(reason):
            "吉祥物动画目录无效：\(reason)"
        case let .invalidModelFilename(filename):
            "吉祥物模型文件名无效：\(filename)"
        }
    }
}

/// Swift Package 内置资源提供器。也允许注入其他 Bundle，便于宿主 App 和测试复用。
public struct BundledMascotResourceProvider: @unchecked Sendable {
    private struct Descriptor {
        let catalogName: String
        let subdirectory: String?
    }

    private let bundle: Bundle

    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    public func loadAsset(_ id: MascotAssetID) throws -> MascotAssetPackage {
        let descriptor = try descriptor(for: id)
        guard let catalogURL = bundle.url(
            forResource: descriptor.catalogName,
            withExtension: "json",
            subdirectory: descriptor.subdirectory
        ) else {
            throw MascotResourceError.missingResource("\(descriptor.catalogName).json")
        }

        let catalog = try JSONDecoder().decode(
            MascotAnimationCatalog.self,
            from: Data(contentsOf: catalogURL)
        )
        try catalog.validate()

        let modelName = catalog.modelFilename as NSString
        let stem = modelName.deletingPathExtension
        let fileExtension = modelName.pathExtension
        guard !stem.isEmpty, !fileExtension.isEmpty else {
            throw MascotResourceError.invalidModelFilename(catalog.modelFilename)
        }
        guard let modelURL = bundle.url(
            forResource: stem,
            withExtension: fileExtension,
            subdirectory: descriptor.subdirectory
        ) else {
            throw MascotResourceError.missingResource(catalog.modelFilename)
        }

        return MascotAssetPackage(id: id, modelURL: modelURL, catalog: catalog)
    }

    private func descriptor(for id: MascotAssetID) throws -> Descriptor {
        switch id {
        case .gugu:
            Descriptor(catalogName: "gugu-v3-animation-map", subdirectory: nil)
        default:
            throw MascotResourceError.unsupportedAsset(id)
        }
    }
}

extension BundledMascotResourceProvider: MascotResourceProviding {}

public extension BundledMascotResourceProvider {
    /// 应用默认使用的内置咕咕资产包。
    static let packageResources = Self(bundle: .module)
}

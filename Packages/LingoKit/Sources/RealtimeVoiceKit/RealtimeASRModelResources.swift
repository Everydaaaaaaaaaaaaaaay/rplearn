import Foundation

/// 隔离 SwiftPM 资源布局，识别引擎只接收经过完整性检查的模型目录。
enum RealtimeASRModelResources {
    struct Locations: Equatable {
        let parakeetEOU320: URL
        let senseVoiceSmallINT8: URL
    }

    private struct RequiredFile {
        let path: String
        let byteCount: Int
    }

    private static let parakeetRequiredFiles = [
        RequiredFile(
            path: "streaming_encoder.mlmodelc/weights/weight.bin",
            byteCount: 212_865_856
        ),
        RequiredFile(path: "decoder.mlmodelc/weights/weight.bin", byteCount: 7_873_600),
        RequiredFile(path: "joint_decision.mlmodelc/weights/weight.bin", byteCount: 2_794_182),
        RequiredFile(path: "vocab.json", byteCount: 17_437),
    ]
    private static let senseVoiceRequiredFiles = [
        RequiredFile(
            path: "SenseVoicePreprocessor.mlmodelc/weights/weight.bin",
            byteCount: 3_037_504
        ),
        RequiredFile(
            path: "SenseVoiceSmall_int8.mlmodelc/weights/weight.bin",
            byteCount: 235_373_118
        ),
        RequiredFile(path: "vocab.json", byteCount: 352_064),
    ]

    static func bundled() throws -> Locations {
        guard let root = Bundle.module.url(
            forResource: "RealtimeASRModels",
            withExtension: nil
        ) else {
            throw RealtimeVoiceError.modelPreparationFailed
        }

        let locations = Locations(
            parakeetEOU320: root.appendingPathComponent("ParakeetEOU320", isDirectory: true),
            senseVoiceSmallINT8: root.appendingPathComponent("SenseVoiceSmallINT8", isDirectory: true)
        )
        guard containsRequiredFiles(
            parakeetRequiredFiles,
            in: locations.parakeetEOU320
        ), containsRequiredFiles(
            senseVoiceRequiredFiles,
            in: locations.senseVoiceSmallINT8
        ) else {
            throw RealtimeVoiceError.modelPreparationFailed
        }
        return locations
    }

    private static func containsRequiredFiles(_ files: [RequiredFile], in directory: URL) -> Bool {
        files.allSatisfy { file in
            let path = directory.appendingPathComponent(file.path).path
            guard FileManager.default.fileExists(atPath: path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber
            else { return false }
            return size.intValue == file.byteCount
        }
    }
}

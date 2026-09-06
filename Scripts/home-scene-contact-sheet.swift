import AppKit
import Foundation

// Deterministic review sheet of native XCTest screenshots; never modifies scene assets.
// swift Scripts/home-scene-contact-sheet.swift <exported-attachments-directory> <output-directory>
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Expected attachment and output directories") }
let source = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
struct Attachment: Decodable { let exportedFileName: String; let suggestedHumanReadableName: String }
struct Test: Decodable { let attachments: [Attachment] }
let tests = try JSONDecoder().decode([Test].self, from: Data(contentsOf: source.appendingPathComponent("manifest.json")))
let attachments = tests.flatMap(\.attachments).filter { $0.suggestedHumanReadableName.hasPrefix("home-city-") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width = 340, label = 32, columns = 3
for start in stride(from: 0, to: attachments.count, by: columns) {
    let batch = Array(attachments[start..<min(start + columns, attachments.count)])
    let images = batch.map { NSImage(contentsOf: source.appendingPathComponent($0.exportedFileName))! }
    let height = Int(ceil(images.map { $0.size.height / $0.size.width * CGFloat(width) }.max()!))
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * batch.count,
                                  pixelsHigh: height + label, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(white: 0.12, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width * batch.count, height: height + label).fill()
    for (index, attachment) in batch.enumerated() {
        let image = images[index]
        let imageHeight = image.size.height / image.size.width * CGFloat(width)
        image.draw(in: NSRect(x: CGFloat(index * width), y: CGFloat(height) - imageHeight,
                             width: CGFloat(width), height: imageHeight))
        let name = attachment.suggestedHumanReadableName.components(separatedBy: "_")[0]
        (name as NSString).draw(at: NSPoint(x: index * width + 12, y: height + 7),
                               withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white])
    }
    NSGraphicsContext.restoreGraphicsState()
    let destination = output.appendingPathComponent("home-cities-\(start / columns + 1).jpg")
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.94])!.write(to: destination)
    print(destination.path)
}

// A single overview plus the larger three-city sheets for closer inspection.
let overviewColumns = 5, overviewWidth = 240, overviewLabel = 24
let overviewImages = attachments.map { NSImage(contentsOf: source.appendingPathComponent($0.exportedFileName))! }
if let aspect = overviewImages.map({ $0.size.height / $0.size.width }).max() {
    let tileHeight = Int(ceil(aspect * CGFloat(overviewWidth)))
    let rows = (attachments.count + overviewColumns - 1) / overviewColumns
    let totalHeight = rows * (tileHeight + overviewLabel)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: overviewWidth * overviewColumns,
                                  pixelsHigh: totalHeight, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(white: 0.12, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: overviewWidth * overviewColumns, height: totalHeight).fill()
    for (index, image) in overviewImages.enumerated() {
        let x = CGFloat(index % overviewColumns * overviewWidth)
        let top = CGFloat(totalHeight - index / overviewColumns * (tileHeight + overviewLabel))
        let imageHeight = image.size.height / image.size.width * CGFloat(overviewWidth)
        image.draw(in: NSRect(x: x, y: top - CGFloat(overviewLabel) - imageHeight,
                             width: CGFloat(overviewWidth), height: imageHeight))
        let title = attachments[index].suggestedHumanReadableName.components(separatedBy: "_")[0]
            .replacingOccurrences(of: "home-city-", with: "")
        (title as NSString).draw(at: NSPoint(x: x + 10, y: top - 19),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
    }
    NSGraphicsContext.restoreGraphicsState()
    let destination = output.appendingPathComponent("home-cities-overview.jpg")
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.94])!.write(to: destination)
    print(destination.path)
}

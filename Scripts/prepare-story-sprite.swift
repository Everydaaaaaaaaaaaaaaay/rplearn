// Deterministic alpha extraction only. Does not redraw generated artwork.
// swift Scripts/prepare-story-sprite.swift input.png output.png
import Foundation
import Vision
import CoreImage
import ImageIO

guard CommandLine.arguments.count == 3 else { fatalError("Usage: input.png output.png") }
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Refusing to overwrite output") }
let handler = VNImageRequestHandler(url: input)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let observation = request.results?.first, !observation.allInstances.isEmpty,
      let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("No foreground or invalid image")
}
let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
let image = CIImage(cgImage: cgImage)
let masked = image.applyingFilter("CIBlendWithMask", parameters: [
    kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
    kCIInputMaskImageKey: CIImage(cvPixelBuffer: mask),
])
// Vision's broad mask can include a pale fringe. Remove only pale neutral pixels
// connected to transparency/exterior; do not key the cream clothes or eye whites.
let width = cgImage.width, height = cgImage.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
CIContext().render(masked, toBitmap: &pixels, rowBytes: width * 4,
                   bounds: image.extent, format: .RGBA8, colorSpace: colorSpace)
var exterior = [Bool](repeating: false, count: width * height)
var queue = [Int]()
func isBackdrop(_ index: Int) -> Bool {
    let i = index * 4
    if pixels[i + 3] < 32 { return true }
    let alpha = max(1, Double(pixels[i + 3])) / 255
    let r = Double(pixels[i]) / alpha, g = Double(pixels[i + 1]) / alpha, b = Double(pixels[i + 2]) / alpha
    return min(r, g, b) > 218 && max(r, g, b) - min(r, g, b) < 35
}
func enqueue(_ p: Int) {
    if !exterior[p] && isBackdrop(p) { exterior[p] = true; queue.append(p) }
}
for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }
// These approved sprites have pale neutral backdrops and warm, non-white clothes.
// Seed enclosed backdrop holes (hair loops, bent elbows, fingers), preserving the
// measured eye region so anime eye whites can never be keyed out. A broad face
// rectangle would incorrectly protect white backdrop trapped between hair curls.
let isNora = input.lastPathComponent.hasPrefix("nora")
let eyeX = isNora ? 0.39...0.55 : 0.44...0.61
let eyeY = isNora ? 0.16...0.19 : 0.13...0.17
for y in 0..<height {
    for x in 0..<width {
        let eyes = eyeX.contains(Double(x) / Double(width)) && eyeY.contains(Double(y) / Double(height))
        if !eyes { enqueue(y * width + x) }
    }
}
var cursor = 0
while cursor < queue.count {
    let p = queue[cursor]; cursor += 1
    if p % width > 0 { enqueue(p - 1) }
    if p % width < width - 1 { enqueue(p + 1) }
    if p >= width { enqueue(p - width) }
    if p < width * (height - 1) { enqueue(p + width) }
}
for p in queue { for c in 0..<4 { pixels[p * 4 + c] = 0 } }
let result = CIImage(bitmapData: Data(pixels), bytesPerRow: width * 4,
                     size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: colorSpace)
try CIContext().writePNGRepresentation(of: result, to: output, format: .RGBA8,
                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
print("Alpha extracted: \(output.path)")

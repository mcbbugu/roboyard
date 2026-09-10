import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Convert a reviewed screen recording to a shareable MP4, GIF, and contact sheet.
@main struct PrepareRecording {
    static func main() async throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080)!
        try await export.export(to: output.appendingPathComponent("RoboYard-demo.mp4"), as: .mp4)
        let frames = AVAssetImageGenerator(asset: asset)
        frames.appliesPreferredTrackTransform = true
        frames.maximumSize = CGSize(width: 960, height: 960)
        let count = Int(duration * 8)
        let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent("desktop.gif") as CFURL, UTType.gif.identifier as CFString, count, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<count {
            let image = try await frames.image(at: CMTime(seconds: Double(i) / 8, preferredTimescale: 600)).image
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.125]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
        let seconds = Int(duration)
        let rows = (seconds + 3) / 4
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: rows * 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var images: [CGImage] = []
        for second in 0..<seconds {
            images.append(try await frames.image(at: CMTime(seconds: Double(second), preferredTimescale: 600)).image)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 1280, height: rows * 200).fill()
        for (i, image) in images.enumerated() {
            let x = (i % 4) * 320; let y = (rows - 1 - i / 4) * 200
            NSGraphicsContext.current!.cgContext.draw(image, in: CGRect(x: x, y: y + 20, width: 320, height: 179))
            ("\(i)s" as NSString).draw(at: NSPoint(x: x + 8, y: y + 2), withAttributes: [.foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("contact-sheet.png"))
        print("Prepared \(duration)s recording")
    }
}

import Foundation
import Metal
import AppKit
import CoreVideo
import UniformTypeIdentifiers

/// Captures screenshots from the Metal rendering pipeline.
@MainActor
final class ScreenshotCapture {

    /// Capture the current video frame as an NSImage.
    static func captureFrame(from pixelBuffer: CVPixelBuffer) -> NSImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// Save a screenshot to a file.
    static func saveScreenshot(
        from pixelBuffer: CVPixelBuffer,
        to directory: URL? = nil,
        format: ImageFormat = .png
    ) -> URL? {
        guard let image = captureFrame(from: pixelBuffer) else { return nil }

        let saveDir = directory ?? defaultScreenshotDirectory()
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "MacPlayer_\(timestamp).\(format.fileExtension)"
        let fileURL = saveDir.appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: format.bitmapType, properties: format.properties)
        else { return nil }

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("[Screenshot] Failed to save: \(error)")
            return nil
        }
    }

    /// Save screenshot with file picker dialog.
    static func saveScreenshotWithDialog(from pixelBuffer: CVPixelBuffer) {
        guard let image = captureFrame(from: pixelBuffer) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "MacPlayer_Screenshot.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format: ImageFormat = url.pathExtension.lowercased() == "jpg" ? .jpeg : .png

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: format.bitmapType, properties: format.properties)
        else { return }

        try? data.write(to: url)
    }

    /// Resize an NSImage and compress to JPEG data for thumbnail use.
    static func resizeAndCompress(image: NSImage, maxWidth: CGFloat) -> Data? {
        let aspect = image.size.height / image.size.width
        let targetWidth = min(image.size.width, maxWidth)
        let targetHeight = targetWidth * aspect
        let targetSize = NSSize(width: targetWidth, height: targetHeight)

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return nil }

        return jpegData
    }

    private static func defaultScreenshotDirectory() -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacPlayer Screenshots")
    }
}

enum ImageFormat {
    case png
    case jpeg

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var bitmapType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    var properties: [NSBitmapImageRep.PropertyKey: Any] {
        switch self {
        case .png: return [:]
        case .jpeg: return [.compressionFactor: 0.9]
        }
    }
}

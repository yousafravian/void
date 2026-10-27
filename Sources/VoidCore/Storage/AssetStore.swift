import Foundation
import AppKit
import CryptoKit

public final class AssetStore: @unchecked Sendable {
    public static let shared = AssetStore()

    public let assetsDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory = baseDirectory {
            self.assetsDirectory = baseDirectory.appendingPathComponent("Assets", isDirectory: true)
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.assetsDirectory = appSupport
                .appendingPathComponent("Void", isDirectory: true)
                .appendingPathComponent("Assets", isDirectory: true)
        }
        try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    }

    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(of string: String) -> String {
        sha256Hex(of: Data(string.utf8))
    }

    @discardableResult
    public func saveData(_ data: Data, ext: String = "bin") -> String {
        let hash = Self.sha256Hex(of: data) + "." + ext
        let targetURL = assetsDirectory.appendingPathComponent(hash)
        lock.lock()
        defer { lock.unlock() }
        if !fileManager.fileExists(atPath: targetURL.path) {
            try? data.write(to: targetURL, options: .atomic)
        }
        return hash
    }

    public func saveExplicitAsset(hash: String, data: Data) {
        let targetURL = assetsDirectory.appendingPathComponent(hash)
        lock.lock()
        defer { lock.unlock() }
        if !fileManager.fileExists(atPath: targetURL.path) {
            try? data.write(to: targetURL, options: .atomic)
        }
    }

    public func loadData(forHash hash: String?) -> Data? {
        guard let hash = hash, !hash.isEmpty else { return nil }
        let url = assetsDirectory.appendingPathComponent(hash)
        return try? Data(contentsOf: url)
    }

    public func fileURL(forHash hash: String?) -> URL? {
        guard let hash = hash, !hash.isEmpty else { return nil }
        let url = assetsDirectory.appendingPathComponent(hash)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func loadImage(forHash hash: String?) -> NSImage? {
        guard let data = loadData(forHash: hash) else { return nil }
        return NSImage(data: data)
    }

    public func saveImage(_ image: NSImage) -> (imageHash: String, thumbHash: String, width: Int, height: Int, byteSize: Int64)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let width = bitmap.pixelsWide > 0 ? bitmap.pixelsWide : Int(image.size.width)
        let height = bitmap.pixelsHigh > 0 ? bitmap.pixelsHigh : Int(image.size.height)
        let imageHash = saveData(pngData, ext: "png")

        // Generate retina thumbnail (max 520px dimension)
        let maxDim: CGFloat = 520
        let scale = min(1.0, maxDim / CGFloat(max(width, height, 1)))
        let thumbW = max(1, Int(CGFloat(width) * scale))
        let thumbH = max(1, Int(CGFloat(height) * scale))

        let thumbData: Data
        if scale < 1.0, let thumbImage = resizedPNGData(from: image, width: thumbW, height: thumbH) {
            thumbData = thumbImage
        } else {
            thumbData = pngData
        }
        let thumbHash = saveData(thumbData, ext: "png")

        return (imageHash, thumbHash, width, height, Int64(pngData.count))
    }

    public func rotateImage90Clockwise(imageHash: String) -> (imageHash: String, thumbHash: String, width: Int, height: Int, byteSize: Int64)? {
        guard let original = loadImage(forHash: imageHash) else { return nil }
        let origSize = original.size
        guard origSize.width > 0 && origSize.height > 0 else { return nil }

        let newSize = NSSize(width: origSize.height, height: origSize.width)
        let rotated = NSImage(size: newSize)
        rotated.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byDegrees: -90)
        transform.translateX(by: -origSize.width / 2, yBy: -origSize.height / 2)
        transform.concat()
        original.draw(at: .zero, from: NSRect(origin: .zero, size: origSize), operation: .copy, fraction: 1.0)
        rotated.unlockFocus()

        return saveImage(rotated)
    }

    public func exportTemporaryPNGFile(forHash hash: String, preferredName: String? = nil) -> URL? {
        guard let data = loadData(forHash: hash) else { return nil }
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("VoidExports", isDirectory: true)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let sanitized = (preferredName ?? "Void Image")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = sanitized.hasSuffix(".png") ? sanitized : "\(sanitized).png"
        let outURL = tempDir.appendingPathComponent(filename)
        try? data.write(to: outURL, options: .atomic)
        return outURL
    }

    @discardableResult
    public func garbageCollect(referencedHashes: Set<String>) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let files = try? fileManager.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var removedCount = 0
        for fileURL in files {
            let name = fileURL.lastPathComponent
            if !referencedHashes.contains(name) {
                try? fileManager.removeItem(at: fileURL)
                removedCount += 1
            }
        }
        return removedCount
    }

    private func resizedPNGData(from image: NSImage, width: Int, height: Int) -> Data? {
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmapRep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return bitmapRep.representation(using: .png, properties: [:])
    }
}

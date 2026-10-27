import Foundation
import AppKit

public final class AppIconColorExtractor: @unchecked Sendable {
    public static let shared = AppIconColorExtractor()

    private var cache: [String: String] = [
        "com.apple.Safari": "#007AFF",
        "com.apple.Notes": "#FFCC00",
        "com.apple.dt.Xcode": "#0A84FF",
        "com.apple.Terminal": "#2C2C2E",
        "com.apple.finder": "#1E88E5",
        "com.apple.mail": "#0A84FF",
        "com.apple.MobileSMS": "#30D158",
        "com.figma.Desktop": "#FF375F",
        "com.microsoft.VSCode": "#007ACC",
        "com.todesktop.230313mzl4w4u92": "#5856D6", // Cursor
        "com.google.Chrome": "#4285F4",
        "company.thebrowser.Browser": "#FF5E5B", // Arc
        "com.tinyspeck.slackmacgap": "#611F69",
        "com.spotify.client": "#1DB954"
    ]
    private var iconCache: [String: NSImage] = [:]
    private let lock = NSLock()

    public init() {}

    public func colorHex(forBundleID bundleID: String?, appURL: URL? = nil) -> String {
        guard let bundleID = bundleID, !bundleID.isEmpty else {
            return "#FF9400"
        }
        lock.lock()
        if let cached = cache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolvedURL = appURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let url = resolvedURL else {
            return "#5856D6"
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let extracted = sampleDominantVibrantColor(from: icon) ?? "#0A84FF"

        lock.lock()
        cache[bundleID] = extracted
        iconCache[bundleID] = icon
        lock.unlock()
        return extracted
    }

    public func appIcon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return nil }
        lock.lock()
        if let cached = iconCache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        lock.lock()
        iconCache[bundleID] = icon
        lock.unlock()
        return icon
    }

    private func sampleDominantVibrantColor(from image: NSImage) -> String? {
        let sampleSize = 24
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: sampleSize,
            pixelsHigh: sampleSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: sampleSize * 4,
            bitsPerPixel: 32
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        image.draw(in: NSRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        var bestR: Double = 0.04
        var bestG: Double = 0.52
        var bestB: Double = 1.0
        var bestScore: Double = -1.0

        for y in 3..<(sampleSize - 3) {
            for x in 3..<(sampleSize - 3) {
                guard let color = bitmapRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let alpha = Double(color.alphaComponent)
                guard alpha > 0.6 else { continue }
                let r = Double(color.redComponent)
                let g = Double(color.greenComponent)
                let b = Double(color.blueComponent)
                let sat = Double(color.saturationComponent)
                let bri = Double(color.brightnessComponent)

                // Prefer vibrant colors that aren't pure white or near-black
                let score = (sat * 2.2) + (bri > 0.2 && bri < 0.95 ? 0.8 : 0.1)
                if score > bestScore {
                    bestScore = score
                    bestR = r
                    bestG = g
                    bestB = b
                }
            }
        }

        let ri = max(0, min(255, Int(bestR * 255)))
        let gi = max(0, min(255, Int(bestG * 255)))
        let bi = max(0, min(255, Int(bestB * 255)))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

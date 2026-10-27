import Foundation
import AppKit

public struct PayloadClassifier {
    public static func parseColorHex(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40, !trimmed.contains("\n") else { return nil }

        // 6-digit HEX (#RRGGBB or RRGGBB)
        let hexPattern = #"^#?([A-Fa-f0-9]{6})$"#
        if let regex = try? NSRegularExpression(pattern: hexPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let hexRange = Range(match.range(at: 1), in: trimmed) {
            return "#" + String(trimmed[hexRange]).uppercased()
        }

        // rgb(r, g, b) or rgba(r, g, b, a)
        let rgbPattern = #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*[\d.]+)?\s*\)$"#
        if let regex = try? NSRegularExpression(pattern: rgbPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let rRange = Range(match.range(at: 1), in: trimmed),
           let gRange = Range(match.range(at: 2), in: trimmed),
           let bRange = Range(match.range(at: 3), in: trimmed),
           let r = Int(trimmed[rRange]), let g = Int(trimmed[gRange]), let b = Int(trimmed[bRange]),
           (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) {
            return String(format: "#%02X%02X%02X", r, g, b)
        }

        // hsl(h, s%, l%)
        let hslPattern = #"^hsla?\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%(?:\s*,\s*[\d.]+)?\s*\)$"#
        if let regex = try? NSRegularExpression(pattern: hslPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let hRange = Range(match.range(at: 1), in: trimmed),
           let sRange = Range(match.range(at: 2), in: trimmed),
           let lRange = Range(match.range(at: 3), in: trimmed),
           let h = Double(trimmed[hRange]), let s = Double(trimmed[sRange]), let l = Double(trimmed[lRange]),
           (0...360).contains(h), (0...100).contains(s), (0...100).contains(l) {
            let color = hslToHex(h: h / 360.0, s: s / 100.0, l: l / 100.0)
            return color
        }

        return nil
    }

    public static func parseValidWebURL(from rawText: String) -> URL? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              host.contains(".") || host == "localhost" || host == "127.0.0.1" else {
            return nil
        }
        return url
    }

    public static func looksLikeSourceCode(_ text: String, sourceBundleID: String? = nil) -> Bool {
        let codeIDEs: Set<String> = [
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.exafunction.windsurf",
            "com.sublimetext.4",
            "com.jetbrains.intellij"
        ]
        if let bundle = sourceBundleID, codeIDEs.contains(bundle), text.contains("\n") {
            return true
        }

        let codeSignals = [
            "func ", "struct ", "class ", "import ", "public ", "private ",
            "const ", "let ", "function ", "=>", "return ", "SELECT ", "FROM ",
            "CREATE TABLE", "def ", "#include", "std::", "interface ", "package ",
            "#!/bin/", "{\n", "};\n", "</div>", "</script>"
        ]
        var hits = 0
        for signal in codeSignals where text.contains(signal) {
            hits += 1
            if hits >= 2 { return true }
        }
        return false
    }

    public static func classifyString(
        _ text: String,
        title: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        sourceAppColorHex: String? = nil,
        assetStore: AssetStore = .shared
    ) -> ClipboardItem {
        let charCount = text.count
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lineCount = max(1, text.components(separatedBy: .newlines).count)

        let rtfHash = rtfData.map { assetStore.saveData($0, ext: "rtf") }
        let htmlHash = htmlData.map { assetStore.saveData($0, ext: "html") }

        if let hex = parseColorHex(from: text) {
            return ClipboardItem(
                contentType: .color,
                title: title,
                plainText: text.trimmingCharacters(in: .whitespacesAndNewlines),
                colorHex: hex,
                charCount: charCount,
                wordCount: wordCount,
                lineCount: lineCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                sourceAppColorHex: sourceAppColorHex,
                contentHash: AssetStore.sha256Hex(of: hex)
            )
        }

        if let url = parseValidWebURL(from: text) {
            let host = url.host?.replacingOccurrences(of: "www.", with: "")
            return ClipboardItem(
                contentType: .link,
                title: title,
                plainText: url.absoluteString,
                rtfAssetHash: rtfHash,
                htmlAssetHash: htmlHash,
                urlString: url.absoluteString,
                linkSummary: host,
                charCount: charCount,
                wordCount: wordCount,
                lineCount: lineCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                sourceAppColorHex: sourceAppColorHex,
                contentHash: AssetStore.sha256Hex(of: url.absoluteString)
            )
        }

        let contentType: ClipboardContentType = looksLikeSourceCode(text, sourceBundleID: sourceAppBundleID) ? .code : .text

        return ClipboardItem(
            contentType: contentType,
            title: title,
            plainText: text,
            rtfAssetHash: rtfHash,
            htmlAssetHash: htmlHash,
            charCount: charCount,
            wordCount: wordCount,
            lineCount: lineCount,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            sourceAppColorHex: sourceAppColorHex,
            contentHash: AssetStore.sha256Hex(of: text)
        )
    }

    public static func classifyPasteboard(
        _ pasteboard: NSPasteboard,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        sourceAppColorHex: String?,
        assetStore: AssetStore = .shared
    ) -> ClipboardItem? {
        // 1. Check for Finder File URLs first (when actual files on disk are copied)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map(\.path)
            var totalSize: Int64 = 0
            for url in urls {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? NSNumber {
                    totalSize += size.int64Value
                }
            }

            // If a single image file was copied from Finder, still store it as File or Image?
            // Paste 6 treats Finder file copies as File cards (with preview & file size), UNLESS raw image data without file URL is on pasteboard.
            let displayNames = urls.map(\.lastPathComponent).joined(separator: ", ")
            let hashInput = paths.sorted().joined(separator: "|")
            return ClipboardItem(
                contentType: .file,
                title: urls.count == 1 ? urls.first?.lastPathComponent : "\(urls.count) Files",
                plainText: displayNames,
                fileURLs: paths,
                fileSizeBytes: totalSize > 0 ? totalSize : nil,
                charCount: displayNames.count,
                wordCount: urls.count,
                lineCount: urls.count,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                sourceAppColorHex: sourceAppColorHex,
                contentHash: AssetStore.sha256Hex(of: hashInput)
            )
        }

        // 2. Check for Image Data (Screenshots, Copy Image from browser/Preview)
        if let image = NSImage(pasteboard: pasteboard),
           image.size.width > 1, image.size.height > 1,
           pasteboard.string(forType: .string) == nil {
            if let saved = assetStore.saveImage(image) {
                return ClipboardItem(
                    contentType: .image,
                    imageAssetHash: saved.imageHash,
                    thumbnailAssetHash: saved.thumbHash,
                    fileSizeBytes: saved.byteSize,
                    imageWidth: saved.width,
                    imageHeight: saved.height,
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName,
                    sourceAppColorHex: sourceAppColorHex,
                    contentHash: saved.imageHash
                )
            }
        }

        // 3. Check for String / RTF / HTML / URL
        if let str = pasteboard.string(forType: .string), !str.isEmpty {
            let rtfData = pasteboard.data(forType: .rtf)
            let htmlData = pasteboard.data(forType: .html)
            return classifyString(
                str,
                rtfData: rtfData,
                htmlData: htmlData,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                sourceAppColorHex: sourceAppColorHex,
                assetStore: assetStore
            )
        }

        // 4. Fallback: Image even if string was empty
        if let image = NSImage(pasteboard: pasteboard),
           let saved = assetStore.saveImage(image) {
            return ClipboardItem(
                contentType: .image,
                imageAssetHash: saved.imageHash,
                thumbnailAssetHash: saved.thumbHash,
                fileSizeBytes: saved.byteSize,
                imageWidth: saved.width,
                imageHeight: saved.height,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                sourceAppColorHex: sourceAppColorHex,
                contentHash: saved.imageHash
            )
        }

        return nil
    }

    private static func hslToHex(h: Double, s: Double, l: Double) -> String {
        let r: Double
        let g: Double
        let b: Double

        if s == 0 {
            r = l; g = l; b = l
        } else {
            func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
                var t = tIn
                if t < 0 { t += 1 }
                if t > 1 { t -= 1 }
                if t < 1/6 { return p + (q - p) * 6 * t }
                if t < 1/2 { return q }
                if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
                return p
            }
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            r = hue2rgb(p, q, h + 1/3)
            g = hue2rgb(p, q, h)
            b = hue2rgb(p, q, h - 1/3)
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }
}

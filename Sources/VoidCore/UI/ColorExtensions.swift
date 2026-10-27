import SwiftUI
import AppKit

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 148, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static let voidYellow = Color(hex: "#FFB250")
    static let voidOrange = Color(hex: "#FF9400")
    static let voidBlack = Color(hex: "#101010")
}

public extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FF9400" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var isLightColor: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.62
    }
}

public enum TextHighlightHelper {
    public static func highlightedAttributedString(
        text: String,
        searchQuery: String,
        isCode: Bool = false
    ) -> AttributedString {
        let truncated = String(text.prefix(1200))
        var attr = AttributedString(truncated)

        if isCode {
            applySimpleSyntaxTint(to: &attr, source: truncated)
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return attr }

        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for token in tokens where !token.isEmpty {
            var searchStart = truncated.startIndex
            while searchStart < truncated.endIndex,
                  let range = truncated.range(of: token, options: .caseInsensitive, range: searchStart..<truncated.endIndex) {
                if let attrRange = Range(range, in: attr) {
                    attr[attrRange].backgroundColor = Color.voidYellow.opacity(0.45)
                    attr[attrRange].foregroundColor = .primary
                }
                searchStart = range.upperBound
            }
        }
        return attr
    }

    private static func applySimpleSyntaxTint(to attr: inout AttributedString, source: String) {
        let keywords = [
            "func", "struct", "class", "enum", "protocol", "import", "public", "private",
            "let", "var", "return", "if", "else", "guard", "switch", "case", "async", "await",
            "const", "function", "export", "default", "SELECT", "FROM", "WHERE", "INSERT", "CREATE"
        ]
        for kw in keywords {
            let pattern = "\\b\(kw)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: nsRange) {
                if let strRange = Range(match.range, in: source),
                   let attrRange = Range(strRange, in: attr) {
                    attr[attrRange].foregroundColor = Color(hex: "#FF375F")
                }
            }
        }
    }
}

import Foundation
import AppKit
import NaturalLanguage

public enum WritingToolAction: String, CaseIterable, Sendable {
    case proofread = "Proofread"
    case rewrite = "Rewrite"
    case friendly = "Friendly"
    case professional = "Professional"
    case concise = "Concise"
    case summarize = "Summarize"
    case compose = "Compose"

    public var systemImage: String {
        switch self {
        case .proofread: return "checkmark.bubble"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .friendly: return "face.smiling"
        case .professional: return "briefcase"
        case .concise: return "arrow.down.right.and.arrow.up.left"
        case .summarize: return "list.bullet.rectangle"
        case .compose: return "wand.and.stars"
        }
    }
}

public final class WritingToolsService: @unchecked Sendable {
    public static let shared = WritingToolsService()

    public init() {}

    public func apply(_ action: WritingToolAction, to input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }

        switch action {
        case .proofread:
            return proofreadText(trimmed)
        case .rewrite:
            return rewriteText(trimmed)
        case .friendly:
            return makeFriendly(trimmed)
        case .professional:
            return makeProfessional(trimmed)
        case .concise:
            return makeConcise(trimmed)
        case .summarize:
            return summarizeText(trimmed)
        case .compose:
            return composeExpansion(trimmed)
        }
    }

    private func proofreadText(_ text: String) -> String {
        let checker = NSSpellChecker.shared
        let nsStr = NSMutableString(string: text)
        var offset = 0
        while offset < nsStr.length {
            let range = checker.checkSpelling(of: nsStr as String, startingAt: offset)
            guard range.location != NSNotFound, range.length > 0 else { break }
            if let correction = checker.correction(
                forWordRange: range,
                in: nsStr as String,
                language: checker.language(),
                inSpellDocumentWithTag: 0
            ) {
                nsStr.replaceCharacters(in: range, with: correction)
                offset = range.location + (correction as NSString).length
            } else {
                offset = range.location + range.length
            }
        }
        // Normalize double spaces and capitalize first character of sentences
        let collapsed = (nsStr as String).replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return capitalizeFirstLetter(of: collapsed)
    }

    private func rewriteText(_ text: String) -> String {
        let cleaned = proofreadText(text)
        let lines = cleaned.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func makeFriendly(_ text: String) -> String {
        let base = proofreadText(text)
        if base.hasSuffix("!") || base.hasPrefix("Hey") {
            return base
        }
        return "Hey there! \(base) Let me know if you need anything else!"
    }

    private func makeProfessional(_ text: String) -> String {
        var result = proofreadText(text)
        let replacements: [(String, String)] = [
            ("hey ", "Hello, "),
            ("thanks", "Thank you"),
            ("thx", "Thank you"),
            ("asap", "at your earliest convenience"),
            ("fyi", "For your information,"),
            ("btw", "Additionally,")
        ]
        for (informal, formal) in replacements {
            result = result.replacingOccurrences(of: informal, with: formal, options: .caseInsensitive)
        }
        if !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") {
            result += "."
        }
        return capitalizeFirstLetter(of: result)
    }

    private func makeConcise(_ text: String) -> String {
        var result = text
        let fillers = [
            "just ", "basically ", "actually ", "literally ", "in order to ",
            "at the end of the day, ", "for all intents and purposes, ", "very ", "really "
        ]
        for filler in fillers {
            result = result.replacingOccurrences(of: filler, with: filler == "in order to " ? "to " : "", options: .caseInsensitive)
        }
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return capitalizeFirstLetter(of: result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func summarizeText(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                sentences.append(s)
            }
            return true
        }
        if sentences.count <= 2 {
            return "• " + sentences.joined(separator: "\n• ")
        }
        let keyPoints = sentences.prefix(3)
        return keyPoints.map { "• \($0)" }.joined(separator: "\n")
    }

    private func composeExpansion(_ text: String) -> String {
        let base = capitalizeFirstLetter(of: text)
        return """
        \(base)

        Key Details:
        • Context: Prepared via Void Writing Tools
        • Action Items: Review and share with your team
        """
    }

    private func capitalizeFirstLetter(of str: String) -> String {
        guard let first = str.first else { return str }
        return first.uppercased() + str.dropFirst()
    }
}

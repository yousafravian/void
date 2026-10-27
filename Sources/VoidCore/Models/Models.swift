import Foundation
import AppKit

public enum ClipboardContentType: String, Codable, CaseIterable, Sendable {
    case text = "text"
    case link = "link"
    case image = "image"
    case file = "file"
    case color = "color"
    case code = "code"

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .color: return "Color"
        case .code: return "Code"
        }
    }

    public var systemImage: String {
        switch self {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "folder"
        case .color: return "paintpalette"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

public struct OCRTextRegion: Codable, Equatable, Sendable {
    public var text: String
    /// Normalized Vision bounding box (0...1 in bottom-left origin or top-left origin)
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var contentType: ClipboardContentType
    public var title: String?
    public var plainText: String?
    public var rtfAssetHash: String?
    public var htmlAssetHash: String?
    public var imageAssetHash: String?
    public var thumbnailAssetHash: String?
    public var colorHex: String?
    public var urlString: String?
    public var linkTitle: String?
    public var linkSummary: String?
    public var fileURLs: [String]
    public var fileSizeBytes: Int64?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var charCount: Int
    public var wordCount: Int
    public var lineCount: Int
    public var ocrText: String?
    public var ocrBoxes: [OCRTextRegion]
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var sourceAppColorHex: String?
    public var contentHash: String
    public var pinboardID: String?
    public var pinboardSortOrder: Int
    public var createdAt: Date
    public var lastCopiedAt: Date

    public init(
        id: String = UUID().uuidString,
        contentType: ClipboardContentType,
        title: String? = nil,
        plainText: String? = nil,
        rtfAssetHash: String? = nil,
        htmlAssetHash: String? = nil,
        imageAssetHash: String? = nil,
        thumbnailAssetHash: String? = nil,
        colorHex: String? = nil,
        urlString: String? = nil,
        linkTitle: String? = nil,
        linkSummary: String? = nil,
        fileURLs: [String] = [],
        fileSizeBytes: Int64? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        charCount: Int = 0,
        wordCount: Int = 0,
        lineCount: Int = 0,
        ocrText: String? = nil,
        ocrBoxes: [OCRTextRegion] = [],
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        sourceAppColorHex: String? = nil,
        contentHash: String,
        pinboardID: String? = nil,
        pinboardSortOrder: Int = 0,
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date()
    ) {
        self.id = id
        self.contentType = contentType
        self.title = title
        self.plainText = plainText
        self.rtfAssetHash = rtfAssetHash
        self.htmlAssetHash = htmlAssetHash
        self.imageAssetHash = imageAssetHash
        self.thumbnailAssetHash = thumbnailAssetHash
        self.colorHex = colorHex
        self.urlString = urlString
        self.linkTitle = linkTitle
        self.linkSummary = linkSummary
        self.fileURLs = fileURLs
        self.fileSizeBytes = fileSizeBytes
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.charCount = charCount
        self.wordCount = wordCount
        self.lineCount = lineCount
        self.ocrText = ocrText
        self.ocrBoxes = ocrBoxes
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.sourceAppColorHex = sourceAppColorHex
        self.contentHash = contentHash
        self.pinboardID = pinboardID
        self.pinboardSortOrder = pinboardSortOrder
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
    }

    public var displayHeaderTitle: String {
        if let title = title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return contentType.displayName
    }

    public var relativeTimeString: String {
        let elapsed = Date().timeIntervalSince(lastCopiedAt)
        if elapsed < 45 {
            return "just now"
        } else if elapsed < 3600 {
            let mins = max(1, Int(elapsed / 60))
            return "\(mins)m"
        } else if elapsed < 86400 {
            let hours = max(1, Int(elapsed / 3600))
            return "\(hours)h"
        } else if elapsed < 172800 {
            return "yesterday"
        } else {
            let days = max(2, Int(elapsed / 86400))
            return "\(days)d"
        }
    }

    public var cardFooterMetadata: String {
        switch contentType {
        case .text, .code:
            return "\(charCount) characters"
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "\(w) × \(h)"
            }
            return "Image"
        case .link:
            if let urlStr = urlString, let host = URL(string: urlStr)?.host {
                return host.replacingOccurrences(of: "www.", with: "")
            }
            return urlString ?? "Link"
        case .color:
            return (colorHex ?? "#000000").uppercased()
        case .file:
            let count = fileURLs.count
            let sizeStr = fileSizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
            if count > 1 {
                return "\(count) files" + (sizeStr.isEmpty ? "" : " • \(sizeStr)")
            } else if let first = fileURLs.first {
                let name = URL(fileURLWithPath: first).lastPathComponent
                return sizeStr.isEmpty ? name : "\(name) • \(sizeStr)"
            }
            return "File"
        }
    }

    public var detailedPreviewMetadata: String {
        switch contentType {
        case .text, .code:
            return "\(charCount) characters • \(wordCount) words • \(lineCount) lines"
        case .image:
            let dims = (imageWidth != nil && imageHeight != nil) ? "\(imageWidth!) × \(imageHeight!)" : "Image"
            if let bytes = fileSizeBytes {
                return "\(dims) • \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
            }
            return dims
        case .file:
            let firstName = fileURLs.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "File"
            let name = fileURLs.count > 1 ? "\(firstName) + \(fileURLs.count - 1) more" : firstName
            if let bytes = fileSizeBytes {
                return "\(name) • \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
            }
            return name
        case .link:
            return urlString ?? "Link"
        case .color:
            return (colorHex ?? "#000000").uppercased()
        }
    }
}

public struct Pinboard: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var sortOrder: Int
    public var createdAt: Date

    public static let presetColors: [(name: String, hex: String)] = [
        ("Sunset Orange", "#FF9400"),
        ("Solar Yellow", "#FFB250"),
        ("Coral Red", "#FF453A"),
        ("Electric Pink", "#FF375F"),
        ("Royal Purple", "#BF5AF2"),
        ("Indigo", "#5856D6"),
        ("Ocean Blue", "#0A84FF"),
        ("Mint Green", "#30D158")
    ]

    public init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String = "#FF9400",
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

public struct PinboardArchive: Codable, Sendable {
    public struct EmbeddedAsset: Codable, Sendable {
        public var hash: String
        public var ext: String
        public var base64Data: String

        public init(hash: String, ext: String, base64Data: String) {
            self.hash = hash
            self.ext = ext
            self.base64Data = base64Data
        }
    }

    public var version: Int
    public var pinboard: Pinboard
    public var items: [ClipboardItem]
    public var assets: [EmbeddedAsset]

    public init(version: Int = 1, pinboard: Pinboard, items: [ClipboardItem], assets: [EmbeddedAsset]) {
        self.version = version
        self.pinboard = pinboard
        self.items = items
        self.assets = assets
    }
}

public enum DateRangeFilter: String, Codable, CaseIterable, Sendable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"

    public var cutoffDateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        switch self {
        case .today:
            return (startOfToday, now)
        case .yesterday:
            let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return (startOfYesterday, startOfToday)
        case .last7Days, .lastWeek:
            let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
            return (sevenDaysAgo, now)
        case .lastMonth:
            let monthAgo = cal.date(byAdding: .month, value: -1, to: now) ?? now
            return (monthAgo, now)
        }
    }
}

public struct SearchFilterState: Equatable, Sendable {
    public var query: String = ""
    public var contentTypes: Set<ClipboardContentType> = []
    public var sourceApps: Set<String> = []
    public var dateRange: DateRangeFilter? = nil
    public var pinboardIDs: Set<String> = []

    public init(
        query: String = "",
        contentTypes: Set<ClipboardContentType> = [],
        sourceApps: Set<String> = [],
        dateRange: DateRangeFilter? = nil,
        pinboardIDs: Set<String> = []
    ) {
        self.query = query
        self.contentTypes = contentTypes
        self.sourceApps = sourceApps
        self.dateRange = dateRange
        self.pinboardIDs = pinboardIDs
    }

    public var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        contentTypes.isEmpty &&
        sourceApps.isEmpty &&
        dateRange == nil &&
        pinboardIDs.isEmpty
    }
}

public enum HistoryRetentionPeriod: String, Codable, CaseIterable, Sendable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case forever = "Forever"

    public var timeInterval: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .year: return 365 * 86_400
        case .forever: return nil
        }
    }
}

public enum PasteDestinationMode: String, Codable, CaseIterable, Sendable {
    case activeApp = "To active app"
    case clipboard = "To Clipboard"
}

public enum ShortcutModifierChoice: String, Codable, CaseIterable, Sendable {
    case command = "Command"
    case shift = "Shift"
    case control = "Control"
    case option = "Option"

    public var symbol: String {
        switch self {
        case .command: return "⌘"
        case .shift: return "⇧"
        case .control: return "⌃"
        case .option: return "⌥"
        }
    }
}

public enum MCPClientType: String, Codable, CaseIterable, Sendable {
    case claudeDesktop = "Claude Desktop"
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case cursor = "Cursor"
    case vscode = "VS Code"
    case windsurf = "Windsurf"
    case custom = "Custom AI Tool"

    public var iconName: String {
        switch self {
        case .claudeDesktop, .claudeCode: return "sparkles"
        case .codex: return "terminal"
        case .cursor: return "cursorarrow.rays"
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .windsurf: return "wind"
        case .custom: return "server.rack"
        }
    }
}

public struct MCPClientRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var clientType: MCPClientType
    public var clientName: String
    public var tokenHash: String
    public var isApproved: Bool
    public var lastConnectedAt: Date?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        clientType: MCPClientType,
        clientName: String,
        tokenHash: String,
        isApproved: Bool = true,
        lastConnectedAt: Date? = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clientType = clientType
        self.clientName = clientName
        self.tokenHash = tokenHash
        self.isApproved = isApproved
        self.lastConnectedAt = lastConnectedAt
        self.createdAt = createdAt
    }

    public var lastConnectedSummary: String {
        guard let last = lastConnectedAt else { return "Never connected" }
        let elapsed = Date().timeIntervalSince(last)
        if elapsed < 60 { return "Last connected just now" }
        if elapsed < 3600 { return "Last connected \(max(1, Int(elapsed / 60)))m ago" }
        if elapsed < 86400 { return "Last connected \(max(1, Int(elapsed / 3600))) hours ago" }
        return "Last connected yesterday"
    }
}

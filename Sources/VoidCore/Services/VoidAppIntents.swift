import Foundation
import AppIntents

@available(macOS 15.0, *)
public struct GetLatestClipboardItemIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Latest Clipboard Item"
    public static var description = IntentDescription("Returns the plain text of the most recent item in Void's clipboard history.")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let latest = DatabaseManager.shared.fetchItems(limit: 1).first
        let value = latest?.plainText ?? latest?.urlString ?? latest?.ocrText ?? ""
        return .result(value: value)
    }
}

@available(macOS 15.0, *)
public struct SearchClipboardItemsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Search Void Clipboard"
    public static var description = IntentDescription("Searches Void clipboard history (including OCR text inside images) and returns matching snippets.")

    @Parameter(title: "Query")
    public var query: String

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let filter = SearchFilterState(query: query)
        let matches = DatabaseManager.shared.searchItems(filter: filter, limit: 20)
        let texts = matches.compactMap { $0.plainText ?? $0.urlString ?? $0.ocrText ?? $0.title }
        return .result(value: texts)
    }
}

@available(macOS 15.0, *)
public struct GetPinboardItemsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Pinboard Items"
    public static var description = IntentDescription("Returns all items from a named Void Pinboard.")

    @Parameter(title: "Pinboard Name")
    public var pinboardName: String

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let board = DatabaseManager.shared.fetchPinboards().first {
            $0.name.caseInsensitiveCompare(pinboardName) == .orderedSame
        }
        guard let boardID = board?.id else {
            return .result(value: [])
        }
        let items = DatabaseManager.shared.fetchItems(pinboardID: boardID)
        let texts = items.compactMap { $0.plainText ?? $0.urlString ?? $0.title }
        return .result(value: texts)
    }
}

@available(macOS 15.0, *)
public struct AddItemToPinboardIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add Item to Void Pinboard"
    public static var description = IntentDescription("Creates a new clipboard item in Void and optionally pins it to a Pinboard.")

    @Parameter(title: "Text")
    public var text: String

    @Parameter(title: "Pinboard Name")
    public var pinboardName: String?

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var pinboardID: String? = nil
        if let name = pinboardName, !name.isEmpty {
            if let existing = DatabaseManager.shared.fetchPinboards().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                pinboardID = existing.id
            } else {
                let newBoard = Pinboard(name: name)
                DatabaseManager.shared.savePinboard(newBoard)
                pinboardID = newBoard.id
            }
        }
        let saved = PasteboardMonitor.shared.createManualTextItem(text: text, pinboardID: pinboardID)
        return .result(value: saved.id)
    }
}

@available(macOS 15.0, *)
public struct PasteClipboardItemIntent: AppIntent {
    public static var title: LocalizedStringResource = "Paste Clipboard Item by ID"
    public static var description = IntentDescription("Copies or pastes a specific Void clipboard item by ID.")

    @Parameter(title: "Item ID")
    public var itemID: String

    @Parameter(title: "Paste as Plain Text", default: false)
    public var asPlainText: Bool

    public init() {}

    public func perform() async throws -> some IntentResult {
        if let item = DatabaseManager.shared.fetchItem(id: itemID) {
            await MainActor.run {
                PasteService.shared.pasteItems([item], asPlainText: asPlainText)
            }
        }
        return .result()
    }
}

@available(macOS 15.0, *)
public struct VoidShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetLatestClipboardItemIntent(),
            phrases: ["Get latest clipboard item from \(.applicationName)"],
            shortTitle: "Latest Clipboard Item",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: SearchClipboardItemsIntent(),
            phrases: ["Search \(.applicationName) clipboard"],
            shortTitle: "Search Clipboard",
            systemImageName: "magnifyingglass"
        )
    }
}

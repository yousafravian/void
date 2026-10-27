import XCTest
import AppKit
@testable import VoidCore

final class VoidCoreTests: XCTestCase {
    private var tempDir: URL!
    private var assetStore: AssetStore!
    private var database: DatabaseManager!
    private var settings: VoidSettings!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        assetStore = AssetStore(baseDirectory: tempDir)
        let dbURL = tempDir.appendingPathComponent("TestVoid.sqlite")
        database = DatabaseManager(databaseURL: dbURL, seedIfEmpty: false)
        let suite = UserDefaults(suiteName: "VoidTests_\(UUID().uuidString)")!
        settings = VoidSettings(defaults: suite)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testPayloadClassifierTypesAndColors() {
        // Hex color
        let hexItem = PayloadClassifier.classifyString("#FF9400", assetStore: assetStore)
        XCTAssertEqual(hexItem.contentType, .color)
        XCTAssertEqual(hexItem.colorHex, "#FF9400")

        // RGB color
        let rgbItem = PayloadClassifier.classifyString("rgb(255, 178, 80)", assetStore: assetStore)
        XCTAssertEqual(rgbItem.contentType, .color)
        XCTAssertEqual(rgbItem.colorHex, "#FFB250")

        // HSL color
        let hslItem = PayloadClassifier.classifyString("hsl(0, 100%, 50%)", assetStore: assetStore)
        XCTAssertEqual(hslItem.contentType, .color)
        XCTAssertEqual(hslItem.colorHex, "#FF0000")

        // Web link
        let linkItem = PayloadClassifier.classifyString("https://pasteapp.io/help", assetStore: assetStore)
        XCTAssertEqual(linkItem.contentType, .link)
        XCTAssertEqual(linkItem.urlString, "https://pasteapp.io/help")
        XCTAssertEqual(linkItem.linkSummary, "pasteapp.io")

        // Code snippet
        let codeSnippet = """
        import Foundation
        public struct Greeting {
            public func sayHello() -> String {
                return "Hello Void"
            }
        }
        """
        let codeItem = PayloadClassifier.classifyString(codeSnippet, sourceAppBundleID: "com.apple.dt.Xcode", assetStore: assetStore)
        XCTAssertEqual(codeItem.contentType, .code)

        // Regular plain text
        let textItem = PayloadClassifier.classifyString("Meeting notes for Friday afternoon", assetStore: assetStore)
        XCTAssertEqual(textItem.contentType, .text)
        XCTAssertEqual(textItem.wordCount, 5)
    }

    func testDatabaseDeduplicationFTS5AndSmartFilters() {
        let item1 = PayloadClassifier.classifyString(
            "Quarterly revenue report Q4",
            sourceAppBundleID: "com.apple.Notes",
            sourceAppName: "Notes",
            assetStore: assetStore
        )
        let saved1 = database.insertOrPromoteItem(item1)

        // Consecutive duplicate should promote existing item ID rather than creating a second row
        let item1Dup = PayloadClassifier.classifyString(
            "Quarterly revenue report Q4",
            sourceAppBundleID: "com.apple.Notes",
            sourceAppName: "Notes",
            assetStore: assetStore
        )
        let savedDup = database.insertOrPromoteItem(item1Dup)
        XCTAssertEqual(saved1.id, savedDup.id)
        XCTAssertEqual(database.fetchItems().count, 1)

        // Add image item with OCR text
        var imgItem = ClipboardItem(
            contentType: .image,
            title: "Architecture Diagram",
            imageWidth: 1440,
            imageHeight: 900,
            sourceAppBundleID: "com.figma.Desktop",
            sourceAppName: "Figma",
            contentHash: "hash_img_1"
        )
        imgItem = database.insertOrPromoteItem(imgItem)
        database.updateOCR(
            id: imgItem.id,
            ocrText: "PostgreSQL Production Cluster Latency",
            ocrBoxes: [OCRTextRegion(text: "PostgreSQL", x: 0.1, y: 0.2, width: 0.3, height: 0.08)]
        )

        // Search via FTS5 for OCR text inside image
        let ocrMatches = database.searchItems(filter: SearchFilterState(query: "PostgreSQL"))
        XCTAssertEqual(ocrMatches.count, 1)
        XCTAssertEqual(ocrMatches.first?.id, imgItem.id)
        XCTAssertEqual(ocrMatches.first?.ocrBoxes.first?.text, "PostgreSQL")

        // Filter by Content Type (.text)
        let textOnly = database.searchItems(filter: SearchFilterState(contentTypes: [.text]))
        XCTAssertEqual(textOnly.count, 1)
        XCTAssertEqual(textOnly.first?.id, saved1.id)

        // Filter by Source App ("Figma")
        let figmaOnly = database.searchItems(filter: SearchFilterState(sourceApps: ["Figma"]))
        XCTAssertEqual(figmaOnly.count, 1)
        XCTAssertEqual(figmaOnly.first?.id, imgItem.id)
    }

    func testSinglePinboardSemanticsRetentionImmunityAndArchive() {
        let boardA = Pinboard(name: "Board A", colorHex: "#FF9400", sortOrder: 0)
        let boardB = Pinboard(name: "Board B", colorHex: "#0A84FF", sortOrder: 1)
        database.savePinboard(boardA)
        database.savePinboard(boardB)

        let pinnedItem = database.insertOrPromoteItem(
            PayloadClassifier.classifyString("Persistent API Key Format", assetStore: assetStore)
        )
        let unpinnedItem = database.insertOrPromoteItem(
            PayloadClassifier.classifyString("Ephemeral scratch note", assetStore: assetStore)
        )

        // Pin to Board A
        database.pinItem(id: pinnedItem.id, toPinboardID: boardA.id)
        XCTAssertEqual(database.fetchItems(pinboardID: boardA.id).count, 1)

        // Pinning to Board B moves it from Board A to Board B (single-pinboard-per-item semantics)
        database.pinItem(id: pinnedItem.id, toPinboardID: boardB.id)
        XCTAssertEqual(database.fetchItems(pinboardID: boardA.id).count, 0)
        XCTAssertEqual(database.fetchItems(pinboardID: boardB.id).count, 1)

        // Export and re-import Board B (.voidboard archive)
        let archiveData = database.exportPinboardArchive(pinboardID: boardB.id, assetStore: assetStore)
        XCTAssertNotNil(archiveData)
        if let archiveData = archiveData {
            let importedBoard = database.importPinboardArchive(data: archiveData, assetStore: assetStore)
            XCTAssertNotNil(importedBoard)
            XCTAssertEqual(database.fetchItems(pinboardID: importedBoard?.id).count, 1)
        }

        // Erase unpinned history -> unpinnedItem is deleted, pinnedItem is 100% preserved
        let retention = RetentionService(database: database, assetStore: assetStore, settings: settings)
        let result = retention.eraseAllUnpinnedHistory()
        XCTAssertEqual(result.deletedItems, 1)
        XCTAssertNil(database.fetchItem(id: unpinnedItem.id))
        XCTAssertNotNil(database.fetchItem(id: pinnedItem.id))
    }

    func testAssetStoreRotationAndGarbageCollection() {
        let image = NSImage(size: NSSize(width: 120, height: 60))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 120, height: 60)).fill()
        image.unlockFocus()

        guard let saved = assetStore.saveImage(image) else {
            XCTFail("Failed to save image")
            return
        }
        XCTAssertEqual(saved.width, saved.height * 2)

        // Rotate 90 degrees clockwise -> dimensions swap
        guard let rotated = assetStore.rotateImage90Clockwise(imageHash: saved.imageHash) else {
            XCTFail("Failed to rotate image")
            return
        }
        XCTAssertEqual(rotated.width, saved.height)
        XCTAssertEqual(rotated.height, saved.width)

        // Garbage collect keeping only rotated hashes
        let removed = assetStore.garbageCollect(referencedHashes: [rotated.imageHash, rotated.thumbHash])
        XCTAssertGreaterThanOrEqual(removed, 1)
        XCTAssertNotNil(assetStore.loadData(forHash: rotated.imageHash))
    }

    func testVisionOCRExtractionAndWritingTools() {
        // Render an image with clear text for Vision OCR
        let size = NSSize(width: 400, height: 120)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 36),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "VOID CLIPBOARD").draw(at: NSPoint(x: 24, y: 40), withAttributes: attrs)
        img.unlockFocus()

        let ocrResult = VisionOCRService.shared.performOCR(on: img)
        XCTAssertTrue(ocrResult.text.uppercased().contains("VOID"))
        XCTAssertFalse(ocrResult.regions.isEmpty)

        // Test Writing Tools
        let concise = WritingToolsService.shared.apply(.concise, to: "We basically just need to actually ship this feature.")
        XCTAssertFalse(concise.contains("basically"))
        XCTAssertFalse(concise.contains("actually"))
    }

    func testPrivacyFilteringAndUndoService() {
        let monitor = PasteboardMonitor(
            database: database,
            assetStore: assetStore,
            settings: settings
        )

        // Confidential pasteboard marker should be ignored
        XCTAssertTrue(
            monitor.shouldIgnorePasteboard(
                types: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"],
                sourceBundleID: "com.apple.Safari"
            )
        )

        // Ignored application (Passwords) should be ignored
        XCTAssertTrue(
            monitor.shouldIgnorePasteboard(
                types: ["public.utf8-plain-text"],
                sourceBundleID: "com.apple.Passwords"
            )
        )

        // Normal app + normal type should be captured
        XCTAssertFalse(
            monitor.shouldIgnorePasteboard(
                types: ["public.utf8-plain-text"],
                sourceBundleID: "com.apple.Notes"
            )
        )

        // Undo service test
        let undo = UndoManagerService(database: database)
        let item = database.insertOrPromoteItem(
            PayloadClassifier.classifyString("Undoable text", assetStore: assetStore)
        )
        undo.record(.restoreDeletedItems([item]))
        database.deleteItem(id: item.id)
        XCTAssertNil(database.fetchItem(id: item.id))

        _ = undo.undoLast()
        XCTAssertNotNil(database.fetchItem(id: item.id))
    }

    func testMCPServerJSONRPCTools() throws {
        let mcp = MCPServerService(database: database, assetStore: assetStore, settings: settings)

        // 1. Call create_clipboard_item via JSON-RPC 2.0
        let createReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "create_clipboard_item",
                "arguments": [
                    "text": "Void MCP Server Integration Test Payload",
                    "title": "MCP Test"
                ]
            ]
        ]
        let createRespData = mcp.handleJSONRPCRequest(
            bodyData: try JSONSerialization.data(withJSONObject: createReq),
            bypassAuth: true
        )
        let createResp = try JSONSerialization.jsonObject(with: createRespData) as? [String: Any]
        XCTAssertNotNil(createResp?["result"])

        // 2. Call search_clipboard via JSON-RPC 2.0
        let searchReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": [
                "name": "search_clipboard",
                "arguments": [
                    "query": "Integration Test Payload"
                ]
            ]
        ]
        let searchRespData = mcp.handleJSONRPCRequest(
            bodyData: try JSONSerialization.data(withJSONObject: searchReq),
            bypassAuth: true
        )
        let searchJSON = String(data: searchRespData, encoding: .utf8) ?? ""
        XCTAssertTrue(searchJSON.contains("Void MCP Server Integration Test Payload"))
    }
}

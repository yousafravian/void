import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class DatabaseManager: @unchecked Sendable {
    public static let shared = DatabaseManager()

    public let databaseURL: URL
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseURL: URL? = nil, seedIfEmpty: Bool = true) {
        if let databaseURL = databaseURL {
            self.databaseURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Void", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.databaseURL = dir.appendingPathComponent("Void.sqlite")
        }

        openDatabase()
        createSchema()
        if seedIfEmpty {
            seedInitialDataIfNeeded()
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        lock.lock()
        defer { lock.unlock() }
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK {
            executeRaw("PRAGMA journal_mode=WAL;")
            executeRaw("PRAGMA synchronous=NORMAL;")
            executeRaw("PRAGMA foreign_keys=ON;")
        }
    }

    private func executeRaw(_ sql: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                sqlite3_free(errMsg)
            }
        }
    }

    private func createSchema() {
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS pinboards (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color_hex TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            content_type TEXT NOT NULL,
            title TEXT,
            plain_text TEXT,
            rtf_asset_hash TEXT,
            html_asset_hash TEXT,
            image_asset_hash TEXT,
            thumbnail_asset_hash TEXT,
            color_hex TEXT,
            url_string TEXT,
            link_title TEXT,
            link_summary TEXT,
            file_urls_json TEXT NOT NULL DEFAULT '[]',
            file_size_bytes INTEGER,
            image_width INTEGER,
            image_height INTEGER,
            char_count INTEGER NOT NULL DEFAULT 0,
            word_count INTEGER NOT NULL DEFAULT 0,
            line_count INTEGER NOT NULL DEFAULT 0,
            ocr_text TEXT,
            ocr_boxes_json TEXT NOT NULL DEFAULT '[]',
            source_app_bundle_id TEXT,
            source_app_name TEXT,
            source_app_color_hex TEXT,
            content_hash TEXT NOT NULL,
            pinboard_id TEXT REFERENCES pinboards(id) ON DELETE SET NULL,
            pinboard_sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_copied_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_items_last_copied ON clipboard_items(last_copied_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_pinboard ON clipboard_items(pinboard_id, pinboard_sort_order ASC);
        CREATE INDEX IF NOT EXISTS idx_items_content_hash ON clipboard_items(content_hash);

        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5(
            item_id UNINDEXED,
            title,
            plain_text,
            url_string,
            link_title,
            file_names,
            ocr_text,
            source_app_name,
            color_hex,
            tokenize='unicode61 remove_diacritics 2'
        );

        CREATE TABLE IF NOT EXISTS mcp_clients (
            id TEXT PRIMARY KEY,
            client_type TEXT NOT NULL,
            client_name TEXT NOT NULL,
            token_hash TEXT NOT NULL,
            is_approved INTEGER NOT NULL DEFAULT 1,
            last_connected_at REAL,
            created_at REAL NOT NULL
        );
        """
        executeRaw(schemaSQL)
    }

    // MARK: - Seed Data for Out-of-the-Box Rich Experience
    private func seedInitialDataIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        let existingPinboards = fetchPinboards()
        let existingItems = fetchItems(limit: 1)
        guard existingPinboards.isEmpty && existingItems.isEmpty else { return }

        let workBoard = Pinboard(name: "Work", colorHex: "#FF9400", sortOrder: 0)
        let designBoard = Pinboard(name: "Design", colorHex: "#BF5AF2", sortOrder: 1)
        let codeBoard = Pinboard(name: "Snippets", colorHex: "#0A84FF", sortOrder: 2)
        savePinboard(workBoard)
        savePinboard(designBoard)
        savePinboard(codeBoard)

        let now = Date()
        let welcomeText = """
        Welcome to Void — Endless, effortless clipboard for Mac.
        • Press ⇧⌘V anywhere to toggle the bottom Liquid Glass panel
        • Press ⌘1…⌘9 to Quick Paste directly into the active app
        • Press Space to Quick Look, ⌘E to Edit in-place, or ⌘R to Rename
        • Press ⇧⌘C to launch Paste Stack for sequential multi-item pasting
        """
        let item1 = ClipboardItem(
            contentType: .text,
            title: "Welcome to Void",
            plainText: welcomeText,
            charCount: welcomeText.count,
            wordCount: welcomeText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
            lineCount: welcomeText.components(separatedBy: .newlines).count,
            sourceAppBundleID: "com.apple.Notes",
            sourceAppName: "Notes",
            sourceAppColorHex: "#FFCC00",
            contentHash: AssetStore.sha256Hex(of: welcomeText),
            pinboardID: workBoard.id,
            pinboardSortOrder: 0,
            createdAt: now.addingTimeInterval(-3600),
            lastCopiedAt: now.addingTimeInterval(-120)
        )

        let swiftSnippet = """
        @MainActor
        func activateVoidPanel() {
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                panel.animator().alphaValue = 1.0
            }
        }
        """
        let item2 = ClipboardItem(
            contentType: .code,
            title: "VoidPanel Animation",
            plainText: swiftSnippet,
            charCount: swiftSnippet.count,
            wordCount: swiftSnippet.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
            lineCount: swiftSnippet.components(separatedBy: .newlines).count,
            sourceAppBundleID: "com.apple.dt.Xcode",
            sourceAppName: "Xcode",
            sourceAppColorHex: "#0A84FF",
            contentHash: AssetStore.sha256Hex(of: swiftSnippet),
            pinboardID: codeBoard.id,
            pinboardSortOrder: 0,
            createdAt: now.addingTimeInterval(-1800),
            lastCopiedAt: now.addingTimeInterval(-90)
        )

        let item3 = ClipboardItem(
            contentType: .color,
            title: "Void Solar Accent",
            plainText: "#FF9400",
            colorHex: "#FF9400",
            charCount: 7,
            wordCount: 1,
            lineCount: 1,
            sourceAppBundleID: "com.figma.Desktop",
            sourceAppName: "Figma",
            sourceAppColorHex: "#FF375F",
            contentHash: AssetStore.sha256Hex(of: "#FF9400"),
            pinboardID: designBoard.id,
            pinboardSortOrder: 0,
            createdAt: now.addingTimeInterval(-900),
            lastCopiedAt: now.addingTimeInterval(-60)
        )

        let urlStr = "https://developer.apple.com/design/human-interface-guidelines"
        let item4 = ClipboardItem(
            contentType: .link,
            title: "Apple Human Interface Guidelines",
            plainText: urlStr,
            urlString: urlStr,
            linkTitle: "Human Interface Guidelines — Apple Developer",
            linkSummary: "developer.apple.com",
            charCount: urlStr.count,
            wordCount: 1,
            lineCount: 1,
            sourceAppBundleID: "com.apple.Safari",
            sourceAppName: "Safari",
            sourceAppColorHex: "#007AFF",
            contentHash: AssetStore.sha256Hex(of: urlStr),
            pinboardID: workBoard.id,
            pinboardSortOrder: 1,
            createdAt: now.addingTimeInterval(-300),
            lastCopiedAt: now.addingTimeInterval(-15)
        )

        _ = insertOrPromoteItem(item1)
        _ = insertOrPromoteItem(item2)
        _ = insertOrPromoteItem(item3)
        _ = insertOrPromoteItem(item4)
    }

    // MARK: - FTS Synchronization
    private func upsertFTS(for item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }

        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM clipboard_items_fts WHERE item_id = ?;", -1, &delStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(delStmt, 1, item.id, -1, SQLITE_TRANSIENT)
            sqlite3_step(delStmt)
        }
        sqlite3_finalize(delStmt)

        let fileNames = item.fileURLs.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " ")
        let insertSQL = """
        INSERT INTO clipboard_items_fts (
            item_id, title, plain_text, url_string, link_title, file_names, ocr_text, source_app_name, color_hex
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, item.title ?? item.contentType.displayName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, item.plainText ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, item.urlString ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, item.linkTitle ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, fileNames, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, item.ocrText ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, item.sourceAppName ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, item.colorHex ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func deleteFTS(itemID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM clipboard_items_fts WHERE item_id = ?;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, itemID, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Clipboard Items CRUD
    @discardableResult
    public func insertOrPromoteItem(_ newItem: ClipboardItem, deduplicateConsecutive: Bool = true) -> ClipboardItem {
        lock.lock()
        defer { lock.unlock() }

        if deduplicateConsecutive, let existing = fetchItemByContentHash(newItem.contentHash) {
            var promoted = existing
            promoted.lastCopiedAt = Date()
            if promoted.sourceAppBundleID == nil {
                promoted.sourceAppBundleID = newItem.sourceAppBundleID
                promoted.sourceAppName = newItem.sourceAppName
                promoted.sourceAppColorHex = newItem.sourceAppColorHex
            }
            saveItem(promoted)
            return promoted
        }

        saveItem(newItem)
        return newItem
    }

    public func saveItem(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }

        let fileURLsJSON = (try? String(data: encoder.encode(item.fileURLs), encoding: .utf8)) ?? "[]"
        let ocrBoxesJSON = (try? String(data: encoder.encode(item.ocrBoxes), encoding: .utf8)) ?? "[]"

        let sql = """
        INSERT OR REPLACE INTO clipboard_items (
            id, content_type, title, plain_text, rtf_asset_hash, html_asset_hash,
            image_asset_hash, thumbnail_asset_hash, color_hex, url_string, link_title, link_summary,
            file_urls_json, file_size_bytes, image_width, image_height,
            char_count, word_count, line_count, ocr_text, ocr_boxes_json,
            source_app_bundle_id, source_app_name, source_app_color_hex,
            content_hash, pinboard_id, pinboard_sort_order, created_at, last_copied_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?,
            ?, ?, ?, ?, ?,
            ?, ?, ?,
            ?, ?, ?, ?, ?
        );
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, item.contentType.rawValue, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, 3, item.title)
            bindOptionalText(stmt, 4, item.plainText)
            bindOptionalText(stmt, 5, item.rtfAssetHash)
            bindOptionalText(stmt, 6, item.htmlAssetHash)
            bindOptionalText(stmt, 7, item.imageAssetHash)
            bindOptionalText(stmt, 8, item.thumbnailAssetHash)
            bindOptionalText(stmt, 9, item.colorHex)
            bindOptionalText(stmt, 10, item.urlString)
            bindOptionalText(stmt, 11, item.linkTitle)
            bindOptionalText(stmt, 12, item.linkSummary)
            sqlite3_bind_text(stmt, 13, fileURLsJSON, -1, SQLITE_TRANSIENT)
            bindOptionalInt64(stmt, 14, item.fileSizeBytes)
            bindOptionalInt(stmt, 15, item.imageWidth)
            bindOptionalInt(stmt, 16, item.imageHeight)
            sqlite3_bind_int(stmt, 17, Int32(item.charCount))
            sqlite3_bind_int(stmt, 18, Int32(item.wordCount))
            sqlite3_bind_int(stmt, 19, Int32(item.lineCount))
            bindOptionalText(stmt, 20, item.ocrText)
            sqlite3_bind_text(stmt, 21, ocrBoxesJSON, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, 22, item.sourceAppBundleID)
            bindOptionalText(stmt, 23, item.sourceAppName)
            bindOptionalText(stmt, 24, item.sourceAppColorHex)
            sqlite3_bind_text(stmt, 25, item.contentHash, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, 26, item.pinboardID)
            sqlite3_bind_int(stmt, 27, Int32(item.pinboardSortOrder))
            sqlite3_bind_double(stmt, 28, item.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 29, item.lastCopiedAt.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        upsertFTS(for: item)
    }

    public func fetchItem(id: String) -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, "SELECT * FROM clipboard_items WHERE id = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return readClipboardItem(from: stmt)
            }
        }
        return nil
    }

    public func fetchItemByContentHash(_ hash: String) -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, "SELECT * FROM clipboard_items WHERE content_hash = ? ORDER BY last_copied_at DESC LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return readClipboardItem(from: stmt)
            }
        }
        return nil
    }

    public func fetchItems(pinboardID: String? = nil, limit: Int = 500) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        var items: [ClipboardItem] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql: String
        if pinboardID != nil {
            sql = "SELECT * FROM clipboard_items WHERE pinboard_id = ? ORDER BY pinboard_sort_order ASC, last_copied_at DESC LIMIT ?;"
        } else {
            sql = "SELECT * FROM clipboard_items ORDER BY last_copied_at DESC LIMIT ?;"
        }

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let pinboardID = pinboardID {
                sqlite3_bind_text(stmt, 1, pinboardID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = readClipboardItem(from: stmt) {
                    items.append(item)
                }
            }
        }
        return items
    }

    public func searchItems(filter: SearchFilterState, activePinboardID: String? = nil, limit: Int = 500) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }

        let trimmedQuery = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidateItems: [ClipboardItem] = []

        if !trimmedQuery.isEmpty {
            let ftsQuery = buildFTSQuery(from: trimmedQuery)
            let sql = """
            SELECT ci.* FROM clipboard_items ci
            JOIN clipboard_items_fts fts ON ci.id = fts.item_id
            WHERE clipboard_items_fts MATCH ?
            ORDER BY rank, ci.last_copied_at DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let item = readClipboardItem(from: stmt) {
                        candidateItems.append(item)
                    }
                }
            }
            sqlite3_finalize(stmt)

            // Fallback substring match for symbols / hex / partial mid-word matches
            if candidateItems.count < limit {
                let existingIDs = Set(candidateItems.map(\.id))
                let likePattern = "%\(trimmedQuery)%"
                let fallbackSQL = """
                SELECT * FROM clipboard_items
                WHERE plain_text LIKE ? OR title LIKE ? OR url_string LIKE ? OR link_title LIKE ?
                   OR ocr_text LIKE ? OR source_app_name LIKE ? OR color_hex LIKE ? OR file_urls_json LIKE ?
                ORDER BY last_copied_at DESC
                LIMIT ?;
                """
                var fbStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, fallbackSQL, -1, &fbStmt, nil) == SQLITE_OK {
                    for idx in 1...8 {
                        sqlite3_bind_text(fbStmt, Int32(idx), likePattern, -1, SQLITE_TRANSIENT)
                    }
                    sqlite3_bind_int(fbStmt, 9, Int32(limit))
                    while sqlite3_step(fbStmt) == SQLITE_ROW {
                        if let item = readClipboardItem(from: fbStmt), !existingIDs.contains(item.id) {
                            candidateItems.append(item)
                        }
                    }
                }
                sqlite3_finalize(fbStmt)
            }
        } else {
            candidateItems = fetchItems(pinboardID: activePinboardID, limit: limit)
        }

        return candidateItems.filter { item in
            if !filter.contentTypes.isEmpty && !filter.contentTypes.contains(item.contentType) {
                return false
            }
            if !filter.sourceApps.isEmpty {
                let appName = item.sourceAppName ?? ""
                let bundleID = item.sourceAppBundleID ?? ""
                if !filter.sourceApps.contains(appName) && !filter.sourceApps.contains(bundleID) {
                    return false
                }
            }
            if let dateRange = filter.dateRange {
                let (start, end) = dateRange.cutoffDateRange
                if item.lastCopiedAt < start || item.lastCopiedAt > end {
                    return false
                }
            }
            if !filter.pinboardIDs.isEmpty {
                guard let pid = item.pinboardID, filter.pinboardIDs.contains(pid) else {
                    return false
                }
            } else if let activePinboardID = activePinboardID, trimmedQuery.isEmpty {
                if item.pinboardID != activePinboardID {
                    return false
                }
            }
            return true
        }
    }

    public func distinctSourceApps() -> [(name: String, bundleID: String, colorHex: String)] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        let sql = """
        SELECT DISTINCT source_app_name, source_app_bundle_id, source_app_color_hex
        FROM clipboard_items
        WHERE source_app_name IS NOT NULL AND source_app_name != ''
        ORDER BY source_app_name ASC;
        """
        var result: [(String, String, String)] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = columnString(stmt, 0) ?? ""
                let bundleID = columnString(stmt, 1) ?? name
                let color = columnString(stmt, 2) ?? "#8E8E93"
                result.append((name, bundleID, color))
            }
        }
        return result
    }

    public func deleteItem(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        deleteFTS(itemID: id)
    }

    public func deleteItems(ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        for id in ids {
            deleteItem(id: id)
        }
    }

    public func renameItem(id: String, newTitle: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard var item = fetchItem(id: id) else { return }
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = (trimmed?.isEmpty == true) ? nil : trimmed
        saveItem(item)
    }

    public func updateItemText(id: String, newText: String, rtfHash: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard var item = fetchItem(id: id) else { return }
        item.plainText = newText
        if item.contentType == .link {
            item.urlString = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let rtfHash = rtfHash {
            item.rtfAssetHash = rtfHash
        }
        item.charCount = newText.count
        item.wordCount = newText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        item.lineCount = max(1, newText.components(separatedBy: .newlines).count)
        item.contentHash = AssetStore.sha256Hex(of: newText)
        saveItem(item)
    }

    public func updateItemColor(id: String, newColorHex: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var item = fetchItem(id: id) else { return }
        let normalized = newColorHex.hasPrefix("#") ? newColorHex.uppercased() : "#\(newColorHex.uppercased())"
        item.colorHex = normalized
        item.plainText = normalized
        item.charCount = normalized.count
        item.contentHash = AssetStore.sha256Hex(of: normalized)
        saveItem(item)
    }

    public func updateImageAssets(id: String, imageHash: String, thumbHash: String, width: Int, height: Int, byteSize: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard var item = fetchItem(id: id) else { return }
        item.imageAssetHash = imageHash
        item.thumbnailAssetHash = thumbHash
        item.imageWidth = width
        item.imageHeight = height
        item.fileSizeBytes = byteSize
        item.contentHash = imageHash
        saveItem(item)
    }

    public func updateOCR(id: String, ocrText: String, ocrBoxes: [OCRTextRegion]) {
        lock.lock()
        defer { lock.unlock() }
        guard var item = fetchItem(id: id) else { return }
        item.ocrText = ocrText
        item.ocrBoxes = ocrBoxes
        saveItem(item)
    }

    public func updateLinkMetadata(id: String, linkTitle: String?, linkSummary: String?, thumbnailHash: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard var item = fetchItem(id: id) else { return }
        if let linkTitle = linkTitle, !linkTitle.isEmpty {
            item.linkTitle = linkTitle
            if item.title == nil {
                item.title = linkTitle
            }
        }
        if let linkSummary = linkSummary, !linkSummary.isEmpty {
            item.linkSummary = linkSummary
        }
        if let thumbnailHash = thumbnailHash {
            item.thumbnailAssetHash = thumbnailHash
        }
        saveItem(item)
    }

    // MARK: - Single-Pinboard Pinning & Reordering
    public func pinItem(id: String, toPinboardID pinboardID: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard var item = fetchItem(id: id) else { return }
        item.pinboardID = pinboardID
        if let pinboardID = pinboardID {
            let existingPinned = fetchItems(pinboardID: pinboardID)
            let nextOrder = (existingPinned.map(\.pinboardSortOrder).max() ?? -1) + 1
            item.pinboardSortOrder = nextOrder
        } else {
            item.pinboardSortOrder = 0
        }
        saveItem(item)
    }

    public func reorderPinboardItems(pinboardID: String, orderedItemIDs: [String]) {
        lock.lock()
        defer { lock.unlock() }
        for (idx, itemID) in orderedItemIDs.enumerated() {
            if var item = fetchItem(id: itemID), item.pinboardID == pinboardID {
                item.pinboardSortOrder = idx
                saveItem(item)
            }
        }
    }

    // MARK: - Pinboards CRUD
    public func fetchPinboards() -> [Pinboard] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        var boards: [Pinboard] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, "SELECT id, name, color_hex, sort_order, created_at FROM pinboards ORDER BY sort_order ASC, created_at ASC;", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = columnString(stmt, 0) ?? UUID().uuidString
                let name = columnString(stmt, 1) ?? "Pinboard"
                let colorHex = columnString(stmt, 2) ?? "#FF9400"
                let sortOrder = Int(sqlite3_column_int(stmt, 3))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                boards.append(Pinboard(id: id, name: name, colorHex: colorHex, sortOrder: sortOrder, createdAt: createdAt))
            }
        }
        return boards
    }

    public func savePinboard(_ pinboard: Pinboard) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        let sql = "INSERT OR REPLACE INTO pinboards (id, name, color_hex, sort_order, created_at) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, pinboard.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, pinboard.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, pinboard.colorHex, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 4, Int32(pinboard.sortOrder))
            sqlite3_bind_double(stmt, 5, pinboard.createdAt.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    public func deletePinboard(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        var clearStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE clipboard_items SET pinboard_id = NULL, pinboard_sort_order = 0 WHERE pinboard_id = ?;", -1, &clearStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(clearStmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(clearStmt)
        }
        sqlite3_finalize(clearStmt)

        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM pinboards WHERE id = ?;", -1, &delStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(delStmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(delStmt)
        }
        sqlite3_finalize(delStmt)
    }

    public func reorderPinboards(orderedIDs: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let existing = Dictionary(uniqueKeysWithValues: fetchPinboards().map { ($0.id, $0) })
        for (idx, id) in orderedIDs.enumerated() {
            if var board = existing[id] {
                board.sortOrder = idx
                savePinboard(board)
            }
        }
    }

    // MARK: - Pinboard Archive Export / Import (.voidboard)
    public func exportPinboardArchive(pinboardID: String, assetStore: AssetStore = .shared) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let board = fetchPinboards().first(where: { $0.id == pinboardID }) else { return nil }
        let items = fetchItems(pinboardID: pinboardID)
        var embeddedAssets: [PinboardArchive.EmbeddedAsset] = []
        var seenHashes = Set<String>()

        for item in items {
            let hashes = [item.rtfAssetHash, item.htmlAssetHash, item.imageAssetHash, item.thumbnailAssetHash].compactMap { $0 }
            for hash in hashes where !seenHashes.contains(hash) {
                seenHashes.insert(hash)
                if let data = assetStore.loadData(forHash: hash) {
                    let ext = URL(fileURLWithPath: hash).pathExtension
                    embeddedAssets.append(
                        PinboardArchive.EmbeddedAsset(
                            hash: hash,
                            ext: ext,
                            base64Data: data.base64EncodedString()
                        )
                    )
                }
            }
        }

        let archive = PinboardArchive(pinboard: board, items: items, assets: embeddedAssets)
        let prettyEncoder = JSONEncoder()
        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? prettyEncoder.encode(archive)
    }

    @discardableResult
    public func importPinboardArchive(data: Data, assetStore: AssetStore = .shared) -> Pinboard? {
        lock.lock()
        defer { lock.unlock() }
        guard let archive = try? decoder.decode(PinboardArchive.self, from: data) else { return nil }

        for asset in archive.assets {
            if let raw = Data(base64Encoded: asset.base64Data) {
                assetStore.saveExplicitAsset(hash: asset.hash, data: raw)
            }
        }

        let nextSortOrder = (fetchPinboards().map(\.sortOrder).max() ?? -1) + 1
        var newBoard = archive.pinboard
        newBoard.id = UUID().uuidString
        newBoard.sortOrder = nextSortOrder
        savePinboard(newBoard)

        for (index, var item) in archive.items.enumerated() {
            item.id = UUID().uuidString
            item.pinboardID = newBoard.id
            item.pinboardSortOrder = index
            saveItem(item)
        }
        return newBoard
    }

    // MARK: - Retention & Asset References
    @discardableResult
    public func pruneExpiredUnpinnedItems(olderThan cutoffDate: Date) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return 0 }

        var expiredIDs: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id FROM clipboard_items WHERE pinboard_id IS NULL AND last_copied_at < ?;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, cutoffDate.timeIntervalSince1970)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let id = columnString(stmt, 0) {
                    expiredIDs.append(id)
                }
            }
        }
        sqlite3_finalize(stmt)

        deleteItems(ids: expiredIDs)
        return expiredIDs.count
    }

    @discardableResult
    public func eraseAllUnpinnedHistory() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pruneExpiredUnpinnedItems(olderThan: Date.distantFuture)
    }

    public func allReferencedAssetHashes() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        var hashes = Set<String>()
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT rtf_asset_hash, html_asset_hash, image_asset_hash, thumbnail_asset_hash FROM clipboard_items;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                for col in 0...3 {
                    if let h = columnString(stmt, Int32(col)), !h.isEmpty {
                        hashes.insert(h)
                    }
                }
            }
        }
        return hashes
    }

    // MARK: - MCP Clients CRUD
    public func fetchMCPClients() -> [MCPClientRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        var records: [MCPClientRecord] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT id, client_type, client_name, token_hash, is_approved, last_connected_at, created_at FROM mcp_clients ORDER BY created_at DESC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = columnString(stmt, 0) ?? UUID().uuidString
                let typeStr = columnString(stmt, 1) ?? MCPClientType.custom.rawValue
                let clientType = MCPClientType(rawValue: typeStr) ?? .custom
                let clientName = columnString(stmt, 2) ?? clientType.rawValue
                let tokenHash = columnString(stmt, 3) ?? ""
                let isApproved = sqlite3_column_int(stmt, 4) != 0
                let lastConnectedAt: Date? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                records.append(
                    MCPClientRecord(
                        id: id,
                        clientType: clientType,
                        clientName: clientName,
                        tokenHash: tokenHash,
                        isApproved: isApproved,
                        lastConnectedAt: lastConnectedAt,
                        createdAt: createdAt
                    )
                )
            }
        }
        return records
    }

    public func saveMCPClient(_ client: MCPClientRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        let sql = """
        INSERT OR REPLACE INTO mcp_clients (id, client_type, client_name, token_hash, is_approved, last_connected_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, client.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, client.clientType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, client.clientName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, client.tokenHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 5, client.isApproved ? 1 : 0)
            if let last = client.lastConnectedAt {
                sqlite3_bind_double(stmt, 6, last.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_bind_double(stmt, 7, client.createdAt.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    public func deleteMCPClient(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM mcp_clients WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Helpers
    private func buildFTSQuery(from rawQuery: String) -> String {
        let tokens = rawQuery
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if tokens.isEmpty {
            return "\"\(rawQuery.replacingOccurrences(of: "\"", with: ""))\""
        }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }

    private func readClipboardItem(from stmt: OpaquePointer?) -> ClipboardItem? {
        guard let stmt = stmt else { return nil }
        let id = columnString(stmt, 0) ?? UUID().uuidString
        let typeRaw = columnString(stmt, 1) ?? "text"
        let contentType = ClipboardContentType(rawValue: typeRaw) ?? .text
        let title = columnString(stmt, 2)
        let plainText = columnString(stmt, 3)
        let rtfAssetHash = columnString(stmt, 4)
        let htmlAssetHash = columnString(stmt, 5)
        let imageAssetHash = columnString(stmt, 6)
        let thumbnailAssetHash = columnString(stmt, 7)
        let colorHex = columnString(stmt, 8)
        let urlString = columnString(stmt, 9)
        let linkTitle = columnString(stmt, 10)
        let linkSummary = columnString(stmt, 11)
        let fileURLsJSON = columnString(stmt, 12) ?? "[]"
        let fileURLs = (try? decoder.decode([String].self, from: Data(fileURLsJSON.utf8))) ?? []
        let fileSizeBytes: Int64? = sqlite3_column_type(stmt, 13) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 13)
        let imageWidth: Int? = sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 14))
        let imageHeight: Int? = sqlite3_column_type(stmt, 15) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 15))
        let charCount = Int(sqlite3_column_int(stmt, 16))
        let wordCount = Int(sqlite3_column_int(stmt, 17))
        let lineCount = Int(sqlite3_column_int(stmt, 18))
        let ocrText = columnString(stmt, 19)
        let ocrBoxesJSON = columnString(stmt, 20) ?? "[]"
        let ocrBoxes = (try? decoder.decode([OCRTextRegion].self, from: Data(ocrBoxesJSON.utf8))) ?? []
        let sourceAppBundleID = columnString(stmt, 21)
        let sourceAppName = columnString(stmt, 22)
        let sourceAppColorHex = columnString(stmt, 23)
        let contentHash = columnString(stmt, 24) ?? ""
        let pinboardID = columnString(stmt, 25)
        let pinboardSortOrder = Int(sqlite3_column_int(stmt, 26))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 27))
        let lastCopiedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 28))

        return ClipboardItem(
            id: id,
            contentType: contentType,
            title: title,
            plainText: plainText,
            rtfAssetHash: rtfAssetHash,
            htmlAssetHash: htmlAssetHash,
            imageAssetHash: imageAssetHash,
            thumbnailAssetHash: thumbnailAssetHash,
            colorHex: colorHex,
            urlString: urlString,
            linkTitle: linkTitle,
            linkSummary: linkSummary,
            fileURLs: fileURLs,
            fileSizeBytes: fileSizeBytes,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            charCount: charCount,
            wordCount: wordCount,
            lineCount: lineCount,
            ocrText: ocrText,
            ocrBoxes: ocrBoxes,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            sourceAppColorHex: sourceAppColorHex,
            contentHash: contentHash,
            pinboardID: pinboardID,
            pinboardSortOrder: pinboardSortOrder,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt
        )
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let stmt = stmt, sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cStr)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value = value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalInt64(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int64?) {
        if let value = value {
            sqlite3_bind_int64(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

public enum VoidActiveTab: Equatable, Hashable, Sendable {
    case suggestions
    case clipboard
    case pinboard(String)
}

@MainActor
public final class VoidViewModel: ObservableObject {
    public static let shared = VoidViewModel()

    // MARK: - Navigation & Items
    @Published public var activeTab: VoidActiveTab = .clipboard {
        didSet {
            if activeTab != oldValue {
                refreshItems()
            }
        }
    }
    @Published public var pinboards: [Pinboard] = []
    @Published public var displayedItems: [ClipboardItem] = []
    @Published public var distinctApps: [(name: String, bundleID: String, colorHex: String)] = []

    // MARK: - Selection & Focus
    @Published public var selectedItemIDs: Set<String> = []
    @Published public var focusedItemID: String? = nil
    @Published public var scrollTargetID: String? = nil
    @Published public var hoveredItemID: String? = nil

    // MARK: - Search & Smart Filters
    @Published public var filterState: SearchFilterState = SearchFilterState() {
        didSet {
            refreshItems()
        }
    }
    @Published public var isSearchFieldFocused: Bool = false
    @Published public var isFilterBarExpanded: Bool = false

    // MARK: - Modals & Overlays
    @Published public var quickLookItem: ClipboardItem? = nil
    @Published public var editingItem: ClipboardItem? = nil
    @Published public var renamingItem: ClipboardItem? = nil
    @Published public var isShowingNewItemSheet: Bool = false
    @Published public var isShowingPinboardSheet: Bool = false
    @Published public var editingPinboard: Pinboard? = nil

    // MARK: - Paste Stack State
    @Published public var isPasteStackActive: Bool = false
    @Published public var pasteStackItems: [ClipboardItem] = []
    @Published public var pasteStackIsFIFO: Bool = true
    @Published public var pasteStackPlainText: Bool = false
    @Published public var pasteStackPaused: Bool = false

    // MARK: - Target Application Tracking
    @Published public var previousActiveApp: NSRunningApplication? = nil
    private var lastClickedItemID: String? = nil
    private var lastClickTimestamp: TimeInterval = 0
    private var workspaceObserver: NSObjectProtocol? = nil

    public let database: DatabaseManager
    public let assetStore: AssetStore
    public let settings: VoidSettings
    public let monitor: PasteboardMonitor
    public let pasteService: PasteService
    public let undoService: UndoManagerService
    public let retentionService: RetentionService
    public let mcpServer: MCPServerService

    public var onDismissPanelRequested: (() -> Void)?
    public var onShowPasteStackPanel: (() -> Void)?
    public var onHidePasteStackPanel: (() -> Void)?

    public init(
        database: DatabaseManager = .shared,
        assetStore: AssetStore = .shared,
        settings: VoidSettings = .shared,
        monitor: PasteboardMonitor = .shared,
        pasteService: PasteService = .shared,
        undoService: UndoManagerService = .shared
    ) {
        self.database = database
        self.assetStore = assetStore
        self.settings = settings
        self.monitor = monitor
        self.pasteService = pasteService
        self.undoService = undoService
        self.retentionService = RetentionService(database: database, assetStore: assetStore, settings: settings)
        self.mcpServer = MCPServerService.shared

        setupCallbacks()
        recordFrontmostAppBeforeActivation()
        refreshAll()
    }

    private func setupCallbacks() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            if app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               app.bundleIdentifier != Bundle.main.bundleIdentifier,
               app.bundleIdentifier != "com.voidapp.mac" {
                Task { @MainActor [weak self] in
                    self?.previousActiveApp = app
                }
            }
        }

        monitor.onItemCaptured = { [weak self] newItem in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isPasteStackActive && !self.pasteStackPaused {
                    self.pasteStackItems.append(newItem)
                }
                self.refreshAll()
            }
        }

        monitor.onMetadataEnriched = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshItems()
            }
        }

        mcpServer.onDataMutated = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
    }

    public func recordFrontmostAppBeforeActivation() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           front.bundleIdentifier != "com.voidapp.mac" {
            previousActiveApp = front
        }
    }

    public var targetAppDisplayName: String {
        previousActiveApp?.localizedName ?? "Active App"
    }

    public func refreshAll() {
        pinboards = database.fetchPinboards()
        distinctApps = database.distinctSourceApps()
        refreshItems()
    }

    public func refreshItems() {
        let items: [ClipboardItem]
        if !filterState.isEmpty {
            let activePinboardID: String?
            if case .pinboard(let pid) = activeTab {
                activePinboardID = pid
            } else {
                activePinboardID = nil
            }
            items = database.searchItems(filter: filterState, activePinboardID: activePinboardID)
        } else {
            switch activeTab {
            case .suggestions:
                let allRecent = database.fetchItems(limit: 120)
                items = IntelligentClipboardService.shared.suggestedItems(
                    from: allRecent,
                    targetApp: previousActiveApp,
                    settings: settings
                )
            case .clipboard:
                items = database.fetchItems(pinboardID: nil, limit: 500)
            case .pinboard(let pid):
                items = database.fetchItems(pinboardID: pid, limit: 500)
            }
        }

        displayedItems = items

        if let focused = focusedItemID, items.contains(where: { $0.id == focused }) {
            // Keep existing selection
        } else if let first = items.first {
            focusedItemID = first.id
            selectedItemIDs = [first.id]
        } else {
            focusedItemID = nil
            selectedItemIDs = []
        }

        // Refresh Quick Look item if open
        if let ql = quickLookItem, let updated = database.fetchItem(id: ql.id) {
            quickLookItem = updated
        }
    }

    public func pinboard(for id: String?) -> Pinboard? {
        guard let id = id else { return nil }
        return pinboards.first { $0.id == id }
    }

    // MARK: - Selection & Keyboard Navigation
    public func selectItem(
        _ item: ClipboardItem,
        extending: Bool = false,
        toggling: Bool = false,
        scrollToItem: Bool = false
    ) {
        if toggling {
            if selectedItemIDs.contains(item.id) && selectedItemIDs.count > 1 {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
            focusedItemID = item.id
        } else if extending,
                  let currentFocus = focusedItemID,
                  let startIdx = displayedItems.firstIndex(where: { $0.id == currentFocus }),
                  let endIdx = displayedItems.firstIndex(where: { $0.id == item.id }) {
            let range = min(startIdx, endIdx)...max(startIdx, endIdx)
            selectedItemIDs = Set(displayedItems[range].map(\.id))
            focusedItemID = item.id
        } else {
            selectedItemIDs = [item.id]
            focusedItemID = item.id
        }
        if scrollToItem {
            scrollTargetID = item.id
        }
    }

    public func handleCardClick(_ item: ClipboardItem) {
        let now = ProcessInfo.processInfo.systemUptime
        let doubleClickWindow = max(NSEvent.doubleClickInterval, 0.35)
        let eventClickCount = NSApp.currentEvent?.clickCount ?? 1
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            selectItem(item, toggling: true, scrollToItem: false)
            lastClickedItemID = item.id
            lastClickTimestamp = now
            return
        }
        if flags.contains(.shift) {
            selectItem(item, extending: true, scrollToItem: false)
            lastClickedItemID = item.id
            lastClickTimestamp = now
            return
        }

        let isDoubleClick = (eventClickCount >= 2) ||
            (lastClickedItemID == item.id && (now - lastClickTimestamp) <= doubleClickWindow)

        selectItem(item, scrollToItem: false)

        if isDoubleClick {
            lastClickedItemID = nil
            lastClickTimestamp = 0
            pasteSelected(asPlainText: false)
        } else {
            lastClickedItemID = item.id
            lastClickTimestamp = now
        }
    }

    public func moveSelection(delta: Int, extending: Bool = false) {
        guard !displayedItems.isEmpty else { return }
        let currentIndex = displayedItems.firstIndex(where: { $0.id == focusedItemID }) ?? 0
        let nextIndex = max(0, min(displayedItems.count - 1, currentIndex + delta))
        let target = displayedItems[nextIndex]
        selectItem(target, extending: extending, scrollToItem: true)
    }

    public func jumpToFirstItem() {
        guard let first = displayedItems.first else { return }
        selectItem(first, scrollToItem: true)
    }

    public func jumpToLastItem() {
        guard let last = displayedItems.last else { return }
        selectItem(last, scrollToItem: true)
    }

    public func selectAllItems() {
        selectedItemIDs = Set(displayedItems.map(\.id))
    }

    public var selectedItemsOrdered: [ClipboardItem] {
        displayedItems.filter { selectedItemIDs.contains($0.id) }
    }

    public var focusedItem: ClipboardItem? {
        if let id = focusedItemID, let item = displayedItems.first(where: { $0.id == id }) {
            return item
        }
        return displayedItems.first
    }

    // MARK: - Tab Switching
    public func switchToNextTab() {
        let allTabs = buildTabOrder()
        guard let idx = allTabs.firstIndex(of: activeTab) else { return }
        let nextIdx = (idx + 1) % allTabs.count
        activeTab = allTabs[nextIdx]
    }

    public func switchToPreviousTab() {
        let allTabs = buildTabOrder()
        guard let idx = allTabs.firstIndex(of: activeTab) else { return }
        let prevIdx = (idx - 1 + allTabs.count) % allTabs.count
        activeTab = allTabs[prevIdx]
    }

    private func buildTabOrder() -> [VoidActiveTab] {
        var tabs: [VoidActiveTab] = []
        if settings.intelligentClipboardEnabled {
            tabs.append(.suggestions)
        }
        tabs.append(.clipboard)
        for board in pinboards {
            tabs.append(.pinboard(board.id))
        }
        return tabs
    }

    // MARK: - Jump to History (`Command-G` / `Show in Clipboard`)
    public func jumpToHistory(for item: ClipboardItem, inPinboard: Bool = false) {
        filterState = SearchFilterState()
        isSearchFieldFocused = false
        isFilterBarExpanded = false
        if inPinboard, let pid = item.pinboardID {
            activeTab = .pinboard(pid)
        } else {
            activeTab = .clipboard
        }
        refreshItems()
        selectItem(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.scrollTargetID = item.id
        }
    }

    // MARK: - Pasting & Copying Actions
    public func pasteSelected(asPlainText: Bool = false) {
        let items = selectedItemsOrdered
        guard !items.isEmpty else { return }
        onDismissPanelRequested?()
        pasteService.pasteItems(
            items,
            asPlainText: asPlainText,
            forceClipboardOnly: false,
            targetApplication: previousActiveApp
        )
    }

    public func quickPasteIndex(_ oneBasedIndex: Int, asPlainText: Bool = false) {
        let idx = oneBasedIndex - 1
        guard idx >= 0 && idx < displayedItems.count else { return }
        let item = displayedItems[idx]
        onDismissPanelRequested?()
        pasteService.pasteItems(
            [item],
            asPlainText: asPlainText,
            forceClipboardOnly: false,
            targetApplication: previousActiveApp
        )
    }

    public func copySelectedToClipboard(asPlainText: Bool = false) {
        let items = selectedItemsOrdered
        guard !items.isEmpty else { return }
        pasteService.copyToClipboard(items, asPlainText: asPlainText)
    }

    // MARK: - Item Mutations & Undo
    public func deleteItems(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        undoService.record(.restoreDeletedItems(items))
        database.deleteItems(ids: items.map(\.id))
        if let ql = quickLookItem, items.contains(where: { $0.id == ql.id }) {
            quickLookItem = nil
        }
        refreshAll()
    }

    public func deleteSelectedItems() {
        deleteItems(selectedItemsOrdered)
    }

    public func renameItem(_ item: ClipboardItem, newTitle: String?) {
        undoService.record(.restoreItemSnapshot(item))
        database.renameItem(id: item.id, newTitle: newTitle)
        refreshItems()
    }

    public func updateItemText(_ item: ClipboardItem, newText: String, rtfData: Data? = nil) {
        undoService.record(.restoreItemSnapshot(item))
        let rtfHash = rtfData.map { assetStore.saveData($0, ext: "rtf") }
        database.updateItemText(id: item.id, newText: newText, rtfHash: rtfHash)
        refreshItems()
    }

    public func applyWritingTool(_ tool: WritingToolAction, to item: ClipboardItem) {
        guard let text = item.plainText, !text.isEmpty else { return }
        let transformed = WritingToolsService.shared.apply(tool, to: text)
        updateItemText(item, newText: transformed)
    }

    public func updateItemColor(_ item: ClipboardItem, newHex: String) {
        undoService.record(.restoreItemSnapshot(item))
        database.updateItemColor(id: item.id, newColorHex: newHex)
        refreshItems()
    }

    public func rotateImageItem(_ item: ClipboardItem) {
        guard let imageHash = item.imageAssetHash,
              let rotated = assetStore.rotateImage90Clockwise(imageHash: imageHash) else {
            return
        }
        undoService.record(.restoreItemSnapshot(item))
        database.updateImageAssets(
            id: item.id,
            imageHash: rotated.imageHash,
            thumbHash: rotated.thumbHash,
            width: rotated.width,
            height: rotated.height,
            byteSize: rotated.byteSize
        )
        VisionOCRService.shared.enrichImageItemAsync(
            itemID: item.id,
            imageHash: rotated.imageHash,
            database: database,
            assetStore: assetStore
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshItems()
            }
        }
        refreshItems()
    }

    public func pinItems(_ items: [ClipboardItem], toPinboardID pinboardID: String?) {
        for item in items {
            undoService.record(.restoreItemSnapshot(item))
            database.pinItem(id: item.id, toPinboardID: pinboardID)
        }
        refreshItems()
    }

    public func moveItemInActivePinboard(draggedItemID: String, targetItemID: String) {
        guard case .pinboard(let pid) = activeTab,
              draggedItemID != targetItemID else {
            return
        }
        var currentIDs = displayedItems.map(\.id)
        guard let fromIdx = currentIDs.firstIndex(of: draggedItemID),
              let toIdx = currentIDs.firstIndex(of: targetItemID) else {
            return
        }
        currentIDs.remove(at: fromIdx)
        currentIDs.insert(draggedItemID, at: toIdx)
        database.reorderPinboardItems(pinboardID: pid, orderedItemIDs: currentIDs)
        refreshItems()
    }

    public func performUndo() {
        if undoService.undoLast() != nil {
            refreshAll()
        }
    }

    // MARK: - Pinboard Operations
    public func createOrUpdatePinboard(id: String? = nil, name: String, colorHex: String) -> Pinboard {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "New Pinboard" : trimmed
        if let id = id, var existing = pinboards.first(where: { $0.id == id }) {
            existing.name = finalName
            existing.colorHex = colorHex
            database.savePinboard(existing)
            refreshAll()
            return existing
        } else {
            let nextOrder = (pinboards.map(\.sortOrder).max() ?? -1) + 1
            let newBoard = Pinboard(name: finalName, colorHex: colorHex, sortOrder: nextOrder)
            database.savePinboard(newBoard)
            refreshAll()
            return newBoard
        }
    }

    public func deletePinboard(_ board: Pinboard) {
        let pinnedItems = database.fetchItems(pinboardID: board.id)
        undoService.record(.restorePinboard(board, pinnedItems: pinnedItems))
        if activeTab == .pinboard(board.id) {
            activeTab = .clipboard
        }
        database.deletePinboard(id: board.id)
        refreshAll()
    }

    public func movePinboardTab(draggedBoardID: String, targetBoardID: String) {
        guard draggedBoardID != targetBoardID else { return }
        var ids = pinboards.map(\.id)
        guard let fromIdx = ids.firstIndex(of: draggedBoardID),
              let toIdx = ids.firstIndex(of: targetBoardID) else {
            return
        }
        ids.remove(at: fromIdx)
        ids.insert(draggedBoardID, at: toIdx)
        database.reorderPinboards(orderedIDs: ids)
        refreshAll()
    }

    public func exportPinboardToDisk(_ board: Pinboard) {
        guard let archiveData = database.exportPinboardArchive(pinboardID: board.id, assetStore: assetStore) else {
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Pinboard \"\(board.name)\""
        panel.nameFieldStringValue = "\(board.name).voidboard"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? archiveData.write(to: url, options: .atomic)
        }
    }

    public func importPinboardFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Import Pinboard (.voidboard)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK,
           let url = panel.url,
           let data = try? Data(contentsOf: url),
           let imported = database.importPinboardArchive(data: data, assetStore: assetStore) {
            refreshAll()
            activeTab = .pinboard(imported.id)
        }
    }

    // MARK: - Paste Stack Operations
    public func togglePasteStack() {
        if isPasteStackActive {
            closePasteStack()
        } else {
            activatePasteStack(withInitialItems: [])
        }
    }

    public func activatePasteStack(withInitialItems items: [ClipboardItem] = []) {
        isPasteStackActive = true
        pasteStackPaused = false
        if !items.isEmpty {
            pasteStackItems = items
        }
        onShowPasteStackPanel?()
    }

    public func closePasteStack() {
        isPasteStackActive = false
        pasteStackItems.removeAll()
        onHidePasteStackPanel?()
    }

    public func removePasteStackItem(id: String) {
        pasteStackItems.removeAll { $0.id == id }
        if pasteStackItems.isEmpty {
            // Keep stack open for next copy unless closed manually
        }
    }

    public func popAndPasteNextStackItem() {
        guard isPasteStackActive, !pasteStackItems.isEmpty else { return }
        let nextItem: ClipboardItem
        if pasteStackIsFIFO {
            nextItem = pasteStackItems.removeFirst()
        } else {
            nextItem = pasteStackItems.removeLast()
        }

        pasteService.pasteItems(
            [nextItem],
            asPlainText: pasteStackPlainText,
            forceClipboardOnly: false,
            targetApplication: previousActiveApp
        )

        if pasteStackItems.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.closePasteStack()
            }
        }
    }
}

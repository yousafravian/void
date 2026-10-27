import AppKit
import SwiftUI
import Combine

public final class VoidFloatingPanel: NSPanel, NSServicesMenuRequestor {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        if let returnType = returnType,
           [NSPasteboard.PasteboardType.png, .tiff, .pdf, .string].contains(returnType) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    public func readSelection(from pboard: NSPasteboard) -> Bool {
        if let item = PayloadClassifier.classifyPasteboard(
            pboard,
            sourceAppBundleID: "com.apple.ContinuityCamera",
            sourceAppName: "Continuity Camera",
            sourceAppColorHex: "#FF9400"
        ) {
            let saved = DatabaseManager.shared.insertOrPromoteItem(item, deduplicateConsecutive: false)
            if saved.contentType == .image, let imageHash = saved.imageAssetHash {
                VisionOCRService.shared.enrichImageItemAsync(itemID: saved.id, imageHash: imageHash)
            }
            Task { @MainActor in
                VoidViewModel.shared.refreshAll()
            }
            return true
        }
        return false
    }
}

@MainActor
public final class VoidPanelController {
    public static let shared = VoidPanelController()

    public private(set) var panel: VoidFloatingPanel?
    public private(set) var isVisible: Bool = false

    private let viewModel: VoidViewModel
    private let settings: VoidSettings
    private let pasteStackController: PasteStackPanelController
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    public init(
        viewModel: VoidViewModel? = nil,
        settings: VoidSettings = .shared
    ) {
        let resolvedVM = viewModel ?? .shared
        self.viewModel = resolvedVM
        self.settings = settings
        self.pasteStackController = PasteStackPanelController(viewModel: resolvedVM)

        resolvedVM.onDismissPanelRequested = { [weak self] in
            self?.hidePanel(immediately: true)
        }
        resolvedVM.onShowPasteStackPanel = { [weak self] in
            self?.pasteStackController.show()
        }
        resolvedVM.onHidePasteStackPanel = { [weak self] in
            self?.pasteStackController.hide()
        }

        settings.$showDuringScreenSharing
            .receive(on: RunLoop.main)
            .sink { [weak self] allowSharing in
                self?.panel?.sharingType = allowSharing ? .readOnly : .none
            }
            .store(in: &cancellables)
    }

    public func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    public func showPanel() {
        viewModel.recordFrontmostAppBeforeActivation()
        viewModel.refreshAll()

        if panel == nil {
            createPanel()
        }

        guard let panel = panel,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let targetFrame = computePanelFrame(for: screen, height: CGFloat(settings.panelHeight))
        var startFrame = targetFrame
        startFrame.origin.y = screen.frame.minY - targetFrame.height

        panel.sharingType = settings.showDuringScreenSharing ? .readOnly : .none
        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        installKeyboardMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1.0
        }
    }

    public func hidePanel(immediately: Bool = false) {
        guard let panel = panel, isVisible else { return }
        isVisible = false
        removeKeyboardMonitor()
        viewModel.quickLookItem = nil
        viewModel.editingItem = nil
        viewModel.renamingItem = nil
        viewModel.isShowingNewItemSheet = false
        viewModel.isShowingPinboardSheet = false
        viewModel.isSearchFieldFocused = false
        viewModel.hoveredItemID = nil

        if immediately {
            panel.alphaValue = 0.0
            panel.resignKey()
            panel.orderOut(nil)
            return
        }

        let currentFrame = panel.frame
        var endFrame = currentFrame
        endFrame.origin.y -= (currentFrame.height + 20)

        panel.resignKey()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func createPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = computePanelFrame(for: screen, height: CGFloat(settings.panelHeight))

        let p = VoidFloatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.sharingType = settings.showDuringScreenSharing ? .readOnly : .none

        let rootView = MainPanelView(
            viewModel: viewModel,
            settings: settings,
            monitor: PasteboardMonitor.shared,
            onOpenSettings: {
                SettingsWindowController.shared.show()
            },
            onResizeHeight: { [weak self] newHeight in
                guard let self = self,
                      let panel = self.panel,
                      let scr = panel.screen ?? NSScreen.main else { return }
                let updatedFrame = self.computePanelFrame(for: scr, height: CGFloat(newHeight))
                panel.setFrame(updatedFrame, display: true)
            }
        )
        p.contentView = NSHostingView(rootView: rootView)
        self.panel = p
    }

    private func computePanelFrame(for screen: NSScreen, height: CGFloat) -> NSRect {
        let visible = screen.visibleFrame
        let margin: CGFloat = 14
        let effectiveHeight = settings.isCompactMode ? min(height, 255) : height
        return NSRect(
            x: visible.minX + margin,
            y: visible.minY + margin,
            width: visible.width - (margin * 2),
            height: effectiveHeight
        )
    }

    // MARK: - Keyboard Navigation & Shortcuts Monitor
    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self,
                  self.isVisible,
                  event.window == self.panel else {
                return event
            }
            if self.handleMouseDown(event) {
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let mouseMonitor = localMouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            localMouseMonitor = nil
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> Bool {
        let hasActiveOverlay = viewModel.quickLookItem != nil
            || viewModel.editingItem != nil
            || viewModel.renamingItem != nil
            || viewModel.isShowingNewItemSheet
            || viewModel.isShowingPinboardSheet
        guard !hasActiveOverlay else { return false }

        guard let hoveredID = viewModel.hoveredItemID,
              let item = viewModel.displayedItems.first(where: { $0.id == hoveredID }) else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.clickCount >= 2 {
            viewModel.selectItem(item, scrollToItem: false)
            viewModel.pasteSelected(asPlainText: flags.contains(.shift))
            return true
        }

        return false
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Let modal editors handle their own typing unless Escape
        let hasActiveSheet = viewModel.editingItem != nil
            || viewModel.renamingItem != nil
            || viewModel.isShowingNewItemSheet
            || viewModel.isShowingPinboardSheet

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode
        let chars = event.charactersIgnoringModifiers ?? ""

        // Escape (53)
        if keyCode == 53 {
            if viewModel.quickLookItem != nil {
                viewModel.quickLookItem = nil
                return true
            }
            if hasActiveSheet {
                viewModel.editingItem = nil
                viewModel.renamingItem = nil
                viewModel.isShowingNewItemSheet = false
                viewModel.isShowingPinboardSheet = false
                return true
            }
            if !viewModel.filterState.isEmpty || viewModel.isSearchFieldFocused {
                viewModel.filterState = SearchFilterState()
                viewModel.isSearchFieldFocused = false
                viewModel.isFilterBarExpanded = false
                return true
            }
            hidePanel()
            return true
        }

        if hasActiveSheet {
            return false
        }

        // Command shortcuts
        if flags.contains(.command) {
            // Quick Paste Command-1 ... Command-9
            if let digit = Int(chars), (1...9).contains(digit) {
                let plain = flags.contains(.shift)
                viewModel.quickPasteIndex(digit, asPlainText: plain)
                return true
            }

            switch chars.lowercased() {
            case "f":
                if viewModel.isSearchFieldFocused {
                    viewModel.isFilterBarExpanded.toggle()
                } else {
                    viewModel.isSearchFieldFocused = true
                }
                return true
            case "g":
                if let item = viewModel.focusedItem {
                    viewModel.jumpToHistory(for: item, inPinboard: false)
                    return true
                }
            case "e":
                if let item = viewModel.focusedItem,
                   (item.contentType == .text || item.contentType == .code || item.contentType == .link) {
                    viewModel.editingItem = item
                    return true
                }
            case "r":
                if let item = viewModel.focusedItem {
                    viewModel.renamingItem = item
                    return true
                }
            case "o":
                if let item = viewModel.focusedItem {
                    viewModel.pasteService.openItem(item)
                    return true
                }
            case "n":
                if flags.contains(.shift) {
                    viewModel.editingPinboard = nil
                    viewModel.isShowingPinboardSheet = true
                } else {
                    viewModel.isShowingNewItemSheet = true
                }
                return true
            case "t":
                if PasteboardMonitor.shared.isPaused {
                    PasteboardMonitor.shared.resume()
                } else {
                    PasteboardMonitor.shared.pause(for: .fifteenMinutes)
                }
                return true
            case "c":
                if flags.contains(.shift) {
                    viewModel.togglePasteStack()
                } else {
                    viewModel.copySelectedToClipboard(asPlainText: false)
                }
                return true
            case "z":
                viewModel.performUndo()
                return true
            case "a":
                if !viewModel.isSearchFieldFocused {
                    viewModel.selectAllItems()
                    return true
                }
            case ",":
                SettingsWindowController.shared.show()
                return true
            default:
                break
            }

            // Command-Left / Command-Right -> Pinboard tab switching
            if keyCode == 124 { // Right arrow
                viewModel.switchToNextTab()
                return true
            }
            if keyCode == 123 { // Left arrow
                viewModel.switchToPreviousTab()
                return true
            }
            // Command-Up -> First item, Command-Down -> Last item
            if keyCode == 126 { // Up arrow
                viewModel.jumpToFirstItem()
                return true
            }
            if keyCode == 125 { // Down arrow
                viewModel.jumpToLastItem()
                return true
            }
        }

        // Tab (48) switches focus between search bar and cards
        if keyCode == 48 {
            viewModel.isSearchFieldFocused.toggle()
            return true
        }

        // If user is actively typing in the search field, let arrow/text keys go to TextField except Return
        if viewModel.isSearchFieldFocused {
            if keyCode == 36 || keyCode == 76 { // Return / Enter
                viewModel.isSearchFieldFocused = false
                return true
            }
            return false
        }

        // Left / Right arrow card navigation
        if keyCode == 123 { // Left arrow
            viewModel.moveSelection(delta: -1, extending: flags.contains(.shift))
            return true
        }
        if keyCode == 124 { // Right arrow
            viewModel.moveSelection(delta: 1, extending: flags.contains(.shift))
            return true
        }

        // Return / Enter (36 / 76) -> Paste
        if keyCode == 36 || keyCode == 76 {
            let asPlain = flags.contains(.shift)
            viewModel.pasteSelected(asPlainText: asPlain)
            return true
        }

        // Space (49) -> Toggle Quick Look
        if keyCode == 49 {
            if viewModel.quickLookItem != nil {
                viewModel.quickLookItem = nil
            } else {
                viewModel.quickLookItem = viewModel.focusedItem
            }
            return true
        }

        // Delete / Backspace (51 / 117) -> Delete selected items
        if keyCode == 51 || keyCode == 117 {
            viewModel.deleteSelectedItems()
            return true
        }

        // Instant Type-to-Search: alphanumeric characters without modifiers focus search & append character
        if flags.isEmpty,
           let scalar = chars.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) {
            viewModel.isSearchFieldFocused = true
            viewModel.filterState.query.append(chars)
            return true
        }

        return false
    }
}

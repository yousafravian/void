import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct MainPanelView: View {
    @ObservedObject public var viewModel: VoidViewModel
    @ObservedObject public var settings: VoidSettings
    @ObservedObject public var monitor: PasteboardMonitor

    public var onOpenSettings: (() -> Void)?
    public var onResizeHeight: ((Double) -> Void)?

    @FocusState private var searchFocused: Bool
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    @MainActor
    public init(
        viewModel: VoidViewModel? = nil,
        settings: VoidSettings = .shared,
        monitor: PasteboardMonitor = .shared,
        onOpenSettings: (() -> Void)? = nil,
        onResizeHeight: ((Double) -> Void)? = nil
    ) {
        self.viewModel = viewModel ?? .shared
        self.settings = settings
        self.monitor = monitor
        self.onOpenSettings = onOpenSettings
        self.onResizeHeight = onResizeHeight
    }

    public var body: some View {
        ZStack {
            // Liquid Glass Backdrop
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topResizeHandle
                topNavigationBar
                if viewModel.isFilterBarExpanded || !viewModel.filterState.isEmpty {
                    smartFilterBar
                }
                cardsHorizontalScroller
            }

            // Overlays for Quick Look, Editor, Rename, New Item, Pinboard Sheet
            overlayLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .onChange(of: viewModel.isSearchFieldFocused) { _, focused in
            searchFocused = focused
        }
        .onChange(of: searchFocused) { _, newValue in
            viewModel.isSearchFieldFocused = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = AXIsProcessTrusted()
        }
        .onChange(of: viewModel.displayedItems.count) { _, _ in
            isAccessibilityTrusted = AXIsProcessTrusted()
        }
    }

    // MARK: - Top Resize Handle
    private var topResizeHandle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 44, height: 4)
                .padding(.top, 5)
                .padding(.bottom, 2)
            Spacer()
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let newHeight = max(230, min(560, settings.panelHeight - Double(value.translation.height)))
                    settings.panelHeight = newHeight
                    onResizeHeight?(newHeight)
                }
        )
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack(spacing: 10) {
            // Left: Suggestions + Clipboard + Pinboards + '+'
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if settings.intelligentClipboardEnabled {
                        tabPillButton(
                            title: "Suggestions",
                            icon: "sparkles",
                            accentColor: Color.voidYellow,
                            isSelected: viewModel.activeTab == .suggestions && viewModel.filterState.isEmpty
                        ) {
                            viewModel.filterState = SearchFilterState()
                            viewModel.activeTab = .suggestions
                        }
                    }

                    tabPillButton(
                        title: "Clipboard",
                        icon: "doc.on.clipboard",
                        accentColor: Color.voidOrange,
                        isSelected: viewModel.activeTab == .clipboard && viewModel.filterState.isEmpty
                    ) {
                        viewModel.filterState = SearchFilterState()
                        viewModel.activeTab = .clipboard
                    }

                    ForEach(viewModel.pinboards) { board in
                        pinboardTabView(board)
                    }

                    Button {
                        viewModel.editingPinboard = nil
                        viewModel.isShowingPinboardSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Create Pinboard (⇧⌘N)")
                }
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 8)

            // Right: Accessibility Prompt (if needed), Pause Indicator, New Item, Paste Stack, Compact Mode, Power Search, Settings
            HStack(spacing: 8) {
                if !isAccessibilityTrusted && settings.pasteDestination == .activeApp {
                    Button {
                        _ = PasteService.shared.requestAccessibilityPermission(prompt: true)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 12))
                            Text("Enable Auto-Paste")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(Color.voidYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Grant Accessibility permission in System Settings so Void can paste directly into active text fields")
                }

                pauseMenuButton

                Button {
                    viewModel.isShowingNewItemSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("New Text Item (⌘N)")

                Button {
                    viewModel.togglePasteStack()
                } label: {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(viewModel.isPasteStackActive ? Color.voidOrange : .secondary)
                        .frame(width: 28, height: 28)
                        .background(viewModel.isPasteStackActive ? Color.voidOrange.opacity(0.18) : Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Toggle Paste Stack (⇧⌘C)")

                Button {
                    settings.isCompactMode.toggle()
                } label: {
                    Image(systemName: settings.isCompactMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(settings.isCompactMode ? Color.voidYellow : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Toggle Compact Mode")

                powerSearchBar

                Button {
                    onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func tabPillButton(
        title: String,
        icon: String?,
        dotColor: Color? = nil,
        accentColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dotColor = dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(isSelected ? accentColor : .secondary)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? accentColor.opacity(0.65) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func pinboardTabView(_ board: Pinboard) -> some View {
        let isSelected = (viewModel.activeTab == .pinboard(board.id)) && viewModel.filterState.isEmpty
        return tabPillButton(
            title: board.name,
            icon: nil,
            dotColor: Color(hex: board.colorHex),
            accentColor: Color(hex: board.colorHex),
            isSelected: isSelected
        ) {
            viewModel.filterState = SearchFilterState()
            viewModel.activeTab = .pinboard(board.id)
        }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let first = providers.first else { return false }
            _ = first.loadObject(ofClass: NSString.self) { str, _ in
                if let itemID = str as? String {
                    Task { @MainActor in
                        if let item = viewModel.database.fetchItem(id: itemID) {
                            viewModel.pinItems([item], toPinboardID: board.id)
                        } else if !viewModel.selectedItemsOrdered.isEmpty {
                            viewModel.pinItems(viewModel.selectedItemsOrdered, toPinboardID: board.id)
                        }
                    }
                }
            }
            return true
        }
        .contextMenu {
            Button("Edit Pinboard…") {
                viewModel.editingPinboard = board
                viewModel.isShowingPinboardSheet = true
            }
            Menu("Color") {
                ForEach(Pinboard.presetColors, id: \.hex) { preset in
                    Button(preset.name) {
                        _ = viewModel.createOrUpdatePinboard(id: board.id, name: board.name, colorHex: preset.hex)
                    }
                }
            }
            Divider()
            Button("Export Pinboard (.voidboard)…") {
                viewModel.exportPinboardToDisk(board)
            }
            Button("Import Pinboard (.voidboard)…") {
                viewModel.importPinboardFromDisk()
            }
            Divider()
            Button(role: .destructive) {
                viewModel.deletePinboard(board)
            } label: {
                Text("Delete Pinboard")
            }
        }
    }

    private var pauseMenuButton: some View {
        Menu {
            if monitor.isPaused {
                Button("Resume Void (⌘T)") {
                    monitor.resume()
                }
                Divider()
            }
            ForEach(PauseDuration.allCases, id: \.self) { duration in
                Button("Pause for \(duration.rawValue)") {
                    monitor.pause(for: duration)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: monitor.isPaused ? "pause.circle.fill" : "pause.circle")
                    .font(.system(size: 13))
                    .foregroundColor(monitor.isPaused ? Color.voidOrange : .secondary)
                if monitor.isPaused {
                    Text("Paused")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.voidOrange)
                }
            }
            .padding(.horizontal, monitor.isPaused ? 8 : 6)
            .frame(height: 28)
            .background(monitor.isPaused ? Color.voidOrange.opacity(0.18) : Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Pause / Resume Clipboard Capture (⌘T)")
    }

    private var powerSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(searchFocused ? Color.voidOrange : .secondary)

            TextField("Search clipboard & OCR (⌘F)…", text: $viewModel.filterState.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .frame(width: searchFocused || !viewModel.filterState.query.isEmpty ? 210 : 155)
                .animation(.easeInOut(duration: 0.16), value: searchFocused)

            if !viewModel.filterState.isEmpty {
                Button {
                    viewModel.filterState = SearchFilterState()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.isFilterBarExpanded.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle\(viewModel.isFilterBarExpanded ? ".fill" : "")")
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.isFilterBarExpanded ? Color.voidOrange : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Smart Filters (Press ⌘F twice)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(searchFocused ? Color.voidOrange.opacity(0.8) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Smart Filter Bar (Content Type, Source App, Date Range, Pinboards)
    private var smartFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Content Types
                ForEach(ClipboardContentType.allCases, id: \.self) { cType in
                    let active = viewModel.filterState.contentTypes.contains(cType)
                    filterChip(
                        title: cType.displayName,
                        icon: cType.systemImage,
                        isActive: active
                    ) {
                        if active {
                            viewModel.filterState.contentTypes.remove(cType)
                        } else {
                            viewModel.filterState.contentTypes.insert(cType)
                        }
                    }
                }

                Divider()
                    .frame(height: 16)

                // Source App Dropdown
                Menu {
                    Button("All Applications") {
                        viewModel.filterState.sourceApps.removeAll()
                    }
                    Divider()
                    ForEach(viewModel.distinctApps, id: \.bundleID) { app in
                        let selected = viewModel.filterState.sourceApps.contains(app.name)
                        Button {
                            if selected {
                                viewModel.filterState.sourceApps.remove(app.name)
                            } else {
                                viewModel.filterState.sourceApps.insert(app.name)
                            }
                        } label: {
                            HStack {
                                Text(app.name)
                                if selected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    let appLabel = viewModel.filterState.sourceApps.isEmpty
                        ? "App"
                        : viewModel.filterState.sourceApps.joined(separator: ", ")
                    filterChipLabel(
                        title: appLabel,
                        icon: "app.badge",
                        isActive: !viewModel.filterState.sourceApps.isEmpty
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Date Range Dropdown
                Menu {
                    Button("Any Time") {
                        viewModel.filterState.dateRange = nil
                    }
                    Divider()
                    ForEach(DateRangeFilter.allCases, id: \.self) { range in
                        Button {
                            viewModel.filterState.dateRange = range
                        } label: {
                            HStack {
                                Text(range.rawValue)
                                if viewModel.filterState.dateRange == range {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChipLabel(
                        title: viewModel.filterState.dateRange?.rawValue ?? "Date",
                        icon: "calendar",
                        isActive: viewModel.filterState.dateRange != nil
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Pinboard Filter Dropdown
                Menu {
                    Button("All Pinboards") {
                        viewModel.filterState.pinboardIDs.removeAll()
                    }
                    Divider()
                    ForEach(viewModel.pinboards) { board in
                        let selected = viewModel.filterState.pinboardIDs.contains(board.id)
                        Button {
                            if selected {
                                viewModel.filterState.pinboardIDs.remove(board.id)
                            } else {
                                viewModel.filterState.pinboardIDs.insert(board.id)
                            }
                        } label: {
                            HStack {
                                Text(board.name)
                                if selected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChipLabel(
                        title: viewModel.filterState.pinboardIDs.isEmpty ? "Pinboard" : "\(viewModel.filterState.pinboardIDs.count) Pinboards",
                        icon: "pin",
                        isActive: !viewModel.filterState.pinboardIDs.isEmpty
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if !viewModel.filterState.isEmpty {
                    Button("Reset") {
                        viewModel.filterState = SearchFilterState()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.voidOrange)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func filterChip(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            filterChipLabel(title: title, icon: icon, isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    private func filterChipLabel(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(isActive ? .black : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(isActive ? Color.voidYellow : Color.primary.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Horizontal Cards Scroller
    private var cardsHorizontalScroller: some View {
        ScrollViewReader { proxy in
            Group {
                if viewModel.displayedItems.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(viewModel.displayedItems.enumerated()), id: \.element.id) { idx, item in
                                ClipboardCardView(
                                    item: item,
                                    index: idx,
                                    isSelected: viewModel.selectedItemIDs.contains(item.id),
                                    isFocused: viewModel.focusedItemID == item.id,
                                    isCompact: settings.isCompactMode,
                                    searchQuery: viewModel.filterState.query,
                                    viewModel: viewModel
                                )
                                .id(item.id)
                                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                                    guard case .pinboard = viewModel.activeTab,
                                          let first = providers.first else {
                                        return false
                                    }
                                    _ = first.loadObject(ofClass: NSString.self) { str, _ in
                                        if let draggedID = str as? String {
                                            Task { @MainActor in
                                                viewModel.moveItemInActivePinboard(draggedItemID: draggedID, targetItemID: item.id)
                                            }
                                        }
                                    }
                                    return true
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.scrollTargetID) { _, targetID in
                guard let targetID = targetID else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.filterState.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            Text(viewModel.filterState.isEmpty ? "No items in this list yet" : "No matching clipboard items")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            Text(viewModel.filterState.isEmpty
                 ? "Copy anything with ⌘C or press ⌘N to create a new item."
                 : "Try clearing some filters or searching for different keywords.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overlay Layer
    @ViewBuilder
    private var overlayLayer: some View {
        if let qlItem = viewModel.quickLookItem {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.quickLookItem = nil
                    }
                QuickLookPreviewView(item: qlItem, viewModel: viewModel)
            }
        } else if let editItem = viewModel.editingItem {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.editingItem = nil
                    }
                InPlaceEditorView(item: editItem, viewModel: viewModel)
            }
        } else if let renameItem = viewModel.renamingItem {
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.renamingItem = nil
                    }
                RenameItemSheetView(item: renameItem, viewModel: viewModel)
            }
        } else if viewModel.isShowingNewItemSheet {
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.isShowingNewItemSheet = false
                    }
                NewTextItemSheetView(viewModel: viewModel)
            }
        } else if viewModel.isShowingPinboardSheet {
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.isShowingPinboardSheet = false
                    }
                PinboardEditorSheetView(viewModel: viewModel)
            }
        }
    }
}

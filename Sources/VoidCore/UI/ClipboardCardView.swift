import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ClipboardCardView: View {
    public let item: ClipboardItem
    public let index: Int
    public let isSelected: Bool
    public let isFocused: Bool
    public let isCompact: Bool
    public let searchQuery: String
    @ObservedObject public var viewModel: VoidViewModel

    @State private var isHovered: Bool = false

    public init(
        item: ClipboardItem,
        index: Int,
        isSelected: Bool,
        isFocused: Bool,
        isCompact: Bool,
        searchQuery: String,
        viewModel: VoidViewModel
    ) {
        self.item = item
        self.index = index
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isCompact = isCompact
        self.searchQuery = searchQuery
        self.viewModel = viewModel
    }

    private var headerColor: Color {
        if item.contentType == .color, let hex = item.colorHex {
            return Color(hex: hex)
        }
        return Color(hex: item.sourceAppColorHex ?? "#FF9400")
    }

    private var cardWidth: CGFloat {
        isCompact ? 205 : 248
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footerBar
        }
        .frame(width: cardWidth)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? LinearGradient(
                            colors: [Color.voidYellow, Color.voidOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          )
                        : LinearGradient(
                            colors: [Color.white.opacity(isHovered ? 0.28 : 0.12), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                          ),
                    lineWidth: isSelected ? 2.5 : 1.0
                )
        )
        .shadow(
            color: Color.black.opacity(isSelected ? 0.38 : 0.22),
            radius: isSelected ? 12 : 6,
            x: 0,
            y: isSelected ? 6 : 3
        )
        .scaleEffect(isSelected ? 1.015 : (isHovered ? 1.005 : 1.0))
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                viewModel.hoveredItemID = item.id
            } else if viewModel.hoveredItemID == item.id {
                viewModel.hoveredItemID = nil
            }
        }
        .onTapGesture {
            viewModel.handleCardClick(item)
        }
        .onDrag {
            createDragItemProvider()
        }
        .contextMenu {
            cardContextMenu
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayHeaderTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(item.relativeTimeString)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            sourceAppIconView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                headerColor
                LinearGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }

    @ViewBuilder
    private var sourceAppIconView: some View {
        if let icon = AppIconColorExtractor.shared.appIcon(forBundleID: item.sourceAppBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
        } else {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: - Content Body by Type
    @ViewBuilder
    private var contentBody: some View {
        switch item.contentType {
        case .color:
            colorCardBody
        case .image:
            imageCardBody
        case .link:
            linkCardBody
        case .file:
            fileCardBody
        case .code:
            codeCardBody
        case .text:
            textCardBody
        }
    }

    private var textCardBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            let rawText = item.plainText ?? ""
            Text(TextHighlightHelper.highlightedAttributedString(text: rawText, searchQuery: searchQuery, isCode: false))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(.primary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
    }

    private var codeCardBody: some View {
        let rawCode = item.plainText ?? ""
        let lines = rawCode.components(separatedBy: .newlines).prefix(10)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                    Text("\(idx + 1)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.55))
                }
            }
            .padding(.top, 1)

            Text(TextHighlightHelper.highlightedAttributedString(text: rawCode, searchQuery: searchQuery, isCode: true))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Color.black.opacity(0.22))
    }

    private var linkCardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbHash = item.thumbnailAssetHash,
               let nsImg = viewModel.assetStore.loadImage(forHash: thumbHash) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 64 : 88)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                HStack {
                    Image(systemName: "globe")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.accentColor)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let pageTitle = item.linkTitle, !pageTitle.isEmpty {
                Text(pageTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Text(
                TextHighlightHelper.highlightedAttributedString(
                    text: item.urlString ?? item.plainText ?? "",
                    searchQuery: searchQuery
                )
            )
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private var imageCardBody: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.14)
                if let hash = item.thumbnailAssetHash ?? item.imageAssetHash,
                   let nsImg = viewModel.assetStore.loadImage(forHash: hash) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width - 12, height: geo.size.height - 12)
                        .overlay(
                            ocrHighlightOverlay(in: CGSize(width: geo.size.width - 12, height: geo.size.height - 12))
                        )
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        if let ocr = item.ocrText, !ocr.isEmpty {
                            Text(ocr)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func ocrHighlightOverlay(in size: CGSize) -> some View {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty && !item.ocrBoxes.isEmpty {
            let matchingBoxes = item.ocrBoxes.filter {
                $0.text.localizedCaseInsensitiveContains(query)
            }
            ZStack(alignment: .topLeading) {
                ForEach(Array(matchingBoxes.enumerated()), id: \.offset) { _, region in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.voidYellow.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.voidOrange, lineWidth: 1.5)
                        )
                        .frame(
                            width: max(12, size.width * region.width),
                            height: max(10, size.height * region.height)
                        )
                        .offset(
                            x: size.width * region.x,
                            y: size.height * region.y
                        )
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    private var fileCardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let firstPath = item.fileURLs.first {
                let icon = NSWorkspace.shared.icon(forFile: firstPath)
                HStack(spacing: 10) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: firstPath).lastPathComponent)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(2)
                        Text(URL(fileURLWithPath: firstPath).deletingLastPathComponent().path)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if item.fileURLs.count > 1 {
                Divider()
                ForEach(item.fileURLs.dropFirst().prefix(3), id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var colorCardBody: some View {
        let hex = item.colorHex ?? "#FF9400"
        return ZStack {
            Color(hex: hex)
            VStack(spacing: 4) {
                Text(hex.uppercased())
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.32))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack(spacing: 6) {
            Text(item.cardFooterMetadata)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let board = viewModel.pinboard(for: item.pinboardID) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: board.colorHex))
                        .frame(width: 7, height: 7)
                    Text(board.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }

            if index < 9 {
                let modSymbol = viewModel.settings.quickPasteModifier.symbol
                Text("\(modSymbol)\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
    }

    private var cardBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            Color(nsColor: .controlBackgroundColor).opacity(0.68)
        }
    }

    // MARK: - Drag Provider
    private func createDragItemProvider() -> NSItemProvider {
        if item.contentType == .image,
           let hash = item.imageAssetHash,
           let fileURL = viewModel.assetStore.exportTemporaryPNGFile(forHash: hash, preferredName: item.title) {
            let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: item.id as NSString)
            provider.SuggestedName = fileURL.lastPathComponent
            return provider
        }
        if item.contentType == .file, let firstPath = item.fileURLs.first {
            let fileURL = URL(fileURLWithPath: firstPath)
            if let provider = NSItemProvider(contentsOf: fileURL) {
                return provider
            }
        }
        let payload = item.plainText ?? item.urlString ?? item.id
        return NSItemProvider(object: payload as NSString)
    }

    // MARK: - Full Paste 6 Context Menu
    @ViewBuilder
    private var cardContextMenu: some View {
        if !viewModel.filterState.isEmpty {
            Button("Show in Clipboard (⌘G)") {
                viewModel.jumpToHistory(for: item, inPinboard: false)
            }
            if let board = viewModel.pinboard(for: item.pinboardID) {
                Button("Show in \(board.name)") {
                    viewModel.jumpToHistory(for: item, inPinboard: true)
                }
            }
            Divider()
        }

        if item.contentType == .link || item.contentType == .file || item.contentType == .image {
            Button("Open (⌘O)") {
                viewModel.pasteService.openItem(item)
            }
        }

        if item.contentType == .file || item.contentType == .image {
            Button("Reveal in Finder") {
                viewModel.pasteService.revealInFinder(item)
            }
            Divider()
        }

        Button("Paste to \(viewModel.targetAppDisplayName) (↩)") {
            viewModel.selectItem(item)
            viewModel.pasteSelected(asPlainText: false)
        }

        Button("Paste as Plain Text (⇧↩)") {
            viewModel.selectItem(item)
            viewModel.pasteSelected(asPlainText: true)
        }

        Button("Copy (⌘C)") {
            viewModel.selectItem(item)
            viewModel.copySelectedToClipboard(asPlainText: false)
        }

        Divider()

        if item.contentType == .text || item.contentType == .code || item.contentType == .link {
            Button("Edit (⌘E)") {
                viewModel.editingItem = item
            }

            Menu("Writing Tools") {
                ForEach(WritingToolAction.allCases, id: \.self) { tool in
                    Button {
                        viewModel.applyWritingTool(tool, to: item)
                    } label: {
                        Label(tool.rawValue, systemImage: tool.systemImage)
                    }
                }
            }
        }

        if item.contentType == .image {
            Button("Rotate 90°") {
                viewModel.rotateImageItem(item)
            }
        }

        Button("Rename (⌘R)") {
            viewModel.renamingItem = item
        }

        Button("Quick Look (Space)") {
            viewModel.quickLookItem = item
        }

        Menu("Pin") {
            ForEach(viewModel.pinboards) { board in
                Button {
                    let targets = viewModel.selectedItemIDs.contains(item.id)
                        ? viewModel.selectedItemsOrdered
                        : [item]
                    viewModel.pinItems(targets, toPinboardID: board.id)
                } label: {
                    HStack {
                        Text(board.name)
                        if item.pinboardID == board.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if item.pinboardID != nil {
                Divider()
                Button("Unpin from Pinboard") {
                    viewModel.pinItems([item], toPinboardID: nil)
                }
            }
            Divider()
            Button("+ Create Pinboard…") {
                viewModel.editingPinboard = nil
                viewModel.isShowingPinboardSheet = true
            }
        }

        Button("Share…") {
            presentShareSheet(for: item)
        }

        Divider()

        Button(role: .destructive) {
            let targets = viewModel.selectedItemIDs.contains(item.id)
                ? viewModel.selectedItemsOrdered
                : [item]
            viewModel.deleteItems(targets)
        } label: {
            Text("Delete (⌫)")
        }
    }

    private func presentShareSheet(for item: ClipboardItem) {
        var shareItems: [Any] = []
        if let urlStr = item.urlString, let url = URL(string: urlStr) {
            shareItems.append(url)
        } else if item.contentType == .image,
                  let img = viewModel.assetStore.loadImage(forHash: item.imageAssetHash) {
            shareItems.append(img)
        } else if !item.fileURLs.isEmpty {
            shareItems.append(contentsOf: item.fileURLs.map { URL(fileURLWithPath: $0) })
        } else if let text = item.plainText {
            shareItems.append(text)
        }
        guard !shareItems.isEmpty,
              let window = NSApp.keyWindow ?? NSApp.windows.first,
              let contentView = window.contentView else {
            return
        }
        let picker = NSSharingServicePicker(items: shareItems)
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }
}

public extension NSItemProvider {
    var SuggestedName: String? {
        get { suggestedName }
        set { suggestedName = newValue }
    }
}

public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

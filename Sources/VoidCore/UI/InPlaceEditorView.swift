import SwiftUI
import AppKit

public struct InPlaceEditorView: View {
    public let item: ClipboardItem
    @ObservedObject public var viewModel: VoidViewModel

    @State private var draftTitle: String
    @State private var draftText: String
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var isUnderline: Bool = false
    @State private var isStrikethrough: Bool = false

    public init(item: ClipboardItem, viewModel: VoidViewModel) {
        self.item = item
        self.viewModel = viewModel
        _draftTitle = State(initialValue: item.title ?? "")
        _draftText = State(initialValue: item.plainText ?? item.urlString ?? "")
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                TextField("Title (optional)", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Divider()
                    .frame(height: 18)

                // B / I / U / S formatting buttons matching Paste 6 editor
                HStack(spacing: 4) {
                    formatToggleButton(label: "B", weight: .bold, isActive: $isBold) {
                        wrapSelectionOrDocument(prefix: "**", suffix: "**")
                    }
                    formatToggleButton(label: "I", italic: true, isActive: $isItalic) {
                        wrapSelectionOrDocument(prefix: "_", suffix: "_")
                    }
                    formatToggleButton(label: "U", underline: true, isActive: $isUnderline) {
                        wrapSelectionOrDocument(prefix: "<u>", suffix: "</u>")
                    }
                    formatToggleButton(label: "S", strikethrough: true, isActive: $isStrikethrough) {
                        wrapSelectionOrDocument(prefix: "~~", suffix: "~~")
                    }
                }

                Divider()
                    .frame(height: 18)

                Menu {
                    ForEach(WritingToolAction.allCases, id: \.self) { tool in
                        Button {
                            draftText = WritingToolsService.shared.apply(tool, to: draftText)
                        } label: {
                            Label(tool.rawValue, systemImage: tool.systemImage)
                        }
                    }
                } label: {
                    Label("Writing Tools", systemImage: "wand.and.stars")
                }
                .controlSize(.small)

                Spacer()

                Button("Cancel") {
                    viewModel.editingItem = nil
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            TextEditor(text: $draftText)
                .font(item.contentType == .code
                      ? .system(size: 13, design: .monospaced)
                      : .system(size: 13.5))
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                let words = draftText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                let lines = max(1, draftText.components(separatedBy: .newlines).count)
                Text("\(draftText.count) characters • \(words) words • \(lines) lines")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Press ⌘↩ to Save")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 600, height: 360)
        .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.voidOrange.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 10)
    }

    private func formatToggleButton(
        label: String,
        weight: Font.Weight = .semibold,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        isActive: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            isActive.wrappedValue.toggle()
            action()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: weight))
                .italic(italic)
                .underline(underline)
                .strikethrough(strikethrough)
                .frame(width: 26, height: 22)
                .background(isActive.wrappedValue ? Color.voidOrange.opacity(0.28) : Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func wrapSelectionOrDocument(prefix: String, suffix: String) {
        if draftText.hasPrefix(prefix) && draftText.hasSuffix(suffix) {
            draftText = String(draftText.dropFirst(prefix.count).dropLast(suffix.count))
        } else {
            draftText = prefix + draftText + suffix
        }
    }

    private func saveChanges() {
        let rtfAttr = NSAttributedString(
            string: draftText,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        let rtfData = try? rtfAttr.data(
            from: NSRange(location: 0, length: rtfAttr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        viewModel.renameItem(item, newTitle: draftTitle)
        viewModel.updateItemText(item, newText: draftText, rtfData: rtfData)
        viewModel.editingItem = nil
    }
}

public struct RenameItemSheetView: View {
    public let item: ClipboardItem
    @ObservedObject public var viewModel: VoidViewModel
    @State private var name: String

    public init(item: ClipboardItem, viewModel: VoidViewModel) {
        self.item = item
        self.viewModel = viewModel
        _name = State(initialValue: item.title ?? item.displayHeaderTitle)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Item")
                .font(.system(size: 14, weight: .semibold))

            TextField("Custom Title", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitRename()
                }

            HStack {
                Button("Reset to Default") {
                    viewModel.renameItem(item, newTitle: nil)
                    viewModel.renamingItem = nil
                }
                .controlSize(.small)

                Spacer()

                Button("Cancel") {
                    viewModel.renamingItem = nil
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") {
                    commitRename()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(radius: 16)
    }

    private func commitRename() {
        viewModel.renameItem(item, newTitle: name)
        viewModel.renamingItem = nil
    }
}

public struct NewTextItemSheetView: View {
    @ObservedObject public var viewModel: VoidViewModel
    @State private var title: String = ""
    @State private var text: String = ""

    public init(viewModel: VoidViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("New Clipboard Item (⌘N)", systemImage: "plus.rectangle.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(height: 150)
                .padding(6)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.isShowingNewItemSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Create Item") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let targetPinboardID: String?
                    if case .pinboard(let pid) = viewModel.activeTab {
                        targetPinboardID = pid
                    } else {
                        targetPinboardID = nil
                    }
                    let created = viewModel.monitor.createManualTextItem(
                        text: text,
                        title: title.isEmpty ? nil : title,
                        pinboardID: targetPinboardID
                    )
                    viewModel.isShowingNewItemSheet = false
                    viewModel.refreshAll()
                    viewModel.selectItem(created)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(radius: 20)
    }
}

public struct PinboardEditorSheetView: View {
    @ObservedObject public var viewModel: VoidViewModel
    @State private var name: String
    @State private var selectedColorHex: String

    public init(viewModel: VoidViewModel) {
        self.viewModel = viewModel
        _name = State(initialValue: viewModel.editingPinboard?.name ?? "")
        _selectedColorHex = State(initialValue: viewModel.editingPinboard?.colorHex ?? "#FF9400")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.editingPinboard == nil ? "Create Pinboard" : "Edit Pinboard")
                .font(.system(size: 14, weight: .semibold))

            TextField("Pinboard Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("Color")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ForEach(Pinboard.presetColors, id: \.hex) { preset in
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: selectedColorHex == preset.hex ? 2.5 : 0)
                        )
                        .onTapGesture {
                            selectedColorHex = preset.hex
                        }
                }
            }

            HStack {
                if viewModel.editingPinboard == nil {
                    Button("Import .voidboard…") {
                        viewModel.isShowingPinboardSheet = false
                        viewModel.importPinboardFromDisk()
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    viewModel.isShowingPinboardSheet = false
                    viewModel.editingPinboard = nil
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(viewModel.editingPinboard == nil ? "Create" : "Save") {
                    let saved = viewModel.createOrUpdatePinboard(
                        id: viewModel.editingPinboard?.id,
                        name: name,
                        colorHex: selectedColorHex
                    )
                    viewModel.isShowingPinboardSheet = false
                    viewModel.editingPinboard = nil
                    viewModel.activeTab = .pinboard(saved.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(18)
        .frame(width: 370)
        .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(radius: 18)
    }
}

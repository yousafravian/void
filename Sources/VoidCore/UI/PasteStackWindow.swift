import SwiftUI
import AppKit

public struct PasteStackView: View {
    @ObservedObject public var viewModel: VoidViewModel

    @MainActor
    public init(viewModel: VoidViewModel? = nil) {
        self.viewModel = viewModel ?? .shared
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    viewModel.closePasteStack()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("Paste Stack")
                    .font(.system(size: 13.5, weight: .semibold))

                Spacer()

                // FIFO / LIFO order toggle
                Button {
                    viewModel.pasteStackIsFIFO.toggle()
                } label: {
                    Image(systemName: viewModel.pasteStackIsFIFO ? "arrow.down.to.line" : "arrow.up.to.line")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 26, height: 24)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(viewModel.pasteStackIsFIFO ? "Order: First In, First Out (FIFO)" : "Order: Last In, First Out (LIFO)")

                // Plain Text ('T') toggle
                Button {
                    viewModel.pasteStackPlainText.toggle()
                } label: {
                    Text("T")
                        .font(.system(size: 12.5, weight: .bold, design: .serif))
                        .foregroundColor(viewModel.pasteStackPlainText ? .black : .primary)
                        .frame(width: 26, height: 24)
                        .background(viewModel.pasteStackPlainText ? Color.voidYellow : Color.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Paste as Plain Text")

                // Pause / Resume stack capture
                Button {
                    viewModel.pasteStackPaused.toggle()
                } label: {
                    Image(systemName: viewModel.pasteStackPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11.5))
                        .foregroundColor(viewModel.pasteStackPaused ? Color.voidOrange : .primary)
                        .frame(width: 26, height: 24)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(viewModel.pasteStackPaused ? "Resume Stack Capture" : "Pause Stack Capture")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if viewModel.pasteStackItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(Color.voidOrange)
                    Text("Copy items with ⌘C")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Each copy is added to the stack.\nPress Paste Next to pop items in order.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    let ordered = viewModel.pasteStackIsFIFO
                        ? viewModel.pasteStackItems
                        : Array(viewModel.pasteStackItems.reversed())
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(idx == 0 ? .black : .secondary)
                                .frame(width: 20, height: 20)
                                .background(idx == 0 ? Color.voidYellow : Color.primary.opacity(0.08))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.plainText ?? item.urlString ?? item.displayHeaderTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(2)
                                Text(item.cardFooterMetadata)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                viewModel.removePasteStackItem(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.removePasteStackItem(id: item.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removePasteStackItem(id: item.id)
                            } label: {
                                Text("Remove from Stack")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Text("\(viewModel.pasteStackItems.count) in stack")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear") {
                    viewModel.pasteStackItems.removeAll()
                }
                .controlSize(.small)
                .disabled(viewModel.pasteStackItems.isEmpty)

                Button("Paste Next (↩)") {
                    viewModel.popAndPasteNextStackItem()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)
                .controlSize(.small)
                .disabled(viewModel.pasteStackItems.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 310, height: 360)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.voidOrange.opacity(0.45), lineWidth: 1)
        )
    }
}

@MainActor
public final class PasteStackPanelController {
    private var panel: NSPanel?
    private let viewModel: VoidViewModel

    @MainActor
    public init(viewModel: VoidViewModel? = nil) {
        self.viewModel = viewModel ?? .shared
    }

    public func show() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 310, height: 360),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .statusBar
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: PasteStackView(viewModel: viewModel))
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: frame.maxX - 340, y: frame.maxY - 400))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }
}

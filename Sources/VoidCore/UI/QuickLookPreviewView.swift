import SwiftUI
import AppKit
import WebKit
import PDFKit
import AVKit

public struct QuickLookPreviewView: View {
    public let item: ClipboardItem
    @ObservedObject public var viewModel: VoidViewModel

    @State private var showExtractedOCRText: Bool = false
    @State private var pickedColor: Color

    public init(item: ClipboardItem, viewModel: VoidViewModel) {
        self.item = item
        self.viewModel = viewModel
        _pickedColor = State(initialValue: Color(hex: item.colorHex ?? "#FF9400"))
    }

    public var body: some View {
        VStack(spacing: 0) {
            previewHeader
            Divider()
            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            previewFooter
        }
        .frame(width: 680, height: 440)
        .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 10)
    }

    private var previewHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: item.sourceAppColorHex ?? "#FF9400"))
                .frame(width: 10, height: 10)

            Text(item.displayHeaderTitle)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Text("• \(item.relativeTimeString)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            // Type-specific action buttons in header
            if item.contentType == .image {
                Button {
                    viewModel.rotateImageItem(item)
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showExtractedOCRText.toggle()
                } label: {
                    Label(showExtractedOCRText ? "Show Image" : "Extract Text", systemImage: "text.viewfinder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if item.contentType == .text || item.contentType == .code || item.contentType == .link {
                Button {
                    let target = item
                    viewModel.quickLookItem = nil
                    viewModel.editingItem = target
                } label: {
                    Label("Edit (⌘E)", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if item.contentType == .link || item.contentType == .file {
                Button {
                    viewModel.pasteService.openItem(item)
                } label: {
                    Label("Open (⌘O)", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                viewModel.quickLookItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var previewBody: some View {
        switch item.contentType {
        case .text, .code:
            ScrollView {
                Text(item.plainText ?? "")
                    .font(item.contentType == .code
                          ? .system(size: 12.5, design: .monospaced)
                          : .system(size: 13.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }

        case .link:
            if let urlStr = item.urlString, let url = URL(string: urlStr) {
                WebPreviewRepresentable(url: url)
            } else {
                Text(item.plainText ?? "")
                    .padding()
            }

        case .image:
            if showExtractedOCRText {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Extracted OCR Text (Vision)", systemImage: "text.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Copy Extracted Text") {
                            if let ocr = item.ocrText {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ocr, forType: .string)
                                viewModel.monitor.markInternalWrite(changeCount: NSPasteboard.general.changeCount)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    ScrollView {
                        Text(item.ocrText?.isEmpty == false ? item.ocrText! : "No text detected in this image.")
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            } else if let hash = item.imageAssetHash,
                      let img = viewModel.assetStore.loadImage(forHash: hash) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            }

        case .file:
            fileQuickLookBody

        case .color:
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(pickedColor)
                    .frame(width: 240, height: 140)
                    .shadow(radius: 8)

                Text((item.colorHex ?? "#FF9400").uppercased())
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)

                ColorPicker("Adjust Color:", selection: $pickedColor, supportsOpacity: false)
                    .onChange(of: pickedColor) { _, newColor in
                        let nsColor = NSColor(newColor)
                        viewModel.updateItemColor(item, newHex: nsColor.hexString)
                    }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var fileQuickLookBody: some View {
        if let firstPath = item.fileURLs.first {
            let url = URL(fileURLWithPath: firstPath)
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                PDFPreviewRepresentable(url: url)
            } else if ["mp4", "mov", "m4v", "mp3", "m4a", "wav"].contains(ext) {
                AVPlayerPreviewRepresentable(url: url)
            } else if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext),
                      let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            } else if let textContent = try? String(contentsOf: url, encoding: .utf8) {
                ScrollView {
                    Text(textContent.prefix(8000))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: firstPath))
                        .resizable()
                        .frame(width: 72, height: 72)
                    Text(url.lastPathComponent)
                        .font(.system(size: 15, weight: .semibold))
                    Text(firstPath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(24)
            }
        }
    }

    private var previewFooter: some View {
        HStack {
            Text(item.detailedPreviewMetadata)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            if item.contentType == .file || item.contentType == .image {
                Button("Reveal in Finder") {
                    viewModel.pasteService.revealInFinder(item)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Paste (↩)") {
                let target = item
                viewModel.quickLookItem = nil
                viewModel.selectItem(target)
                viewModel.pasteSelected(asPlainText: false)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.voidOrange)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

public struct WebPreviewRepresentable: NSViewRepresentable {
    public let url: URL

    public func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}

public struct PDFPreviewRepresentable: NSViewRepresentable {
    public let url: URL

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    public func updateNSView(_ nsView: PDFView, context: Context) {}
}

public struct AVPlayerPreviewRepresentable: NSViewRepresentable {
    public let url: URL

    public func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .inline
        return playerView
    }

    public func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

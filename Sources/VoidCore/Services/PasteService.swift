import Foundation
import AppKit
import ApplicationServices

public final class PasteService: @unchecked Sendable {
    public static let shared = PasteService()

    private let pasteboard: NSPasteboard
    private let assetStore: AssetStore
    private let settings: VoidSettings
    private let monitor: PasteboardMonitor

    public init(
        pasteboard: NSPasteboard = .general,
        assetStore: AssetStore = .shared,
        settings: VoidSettings = .shared,
        monitor: PasteboardMonitor = .shared
    ) {
        self.pasteboard = pasteboard
        self.assetStore = assetStore
        self.settings = settings
        self.monitor = monitor
    }

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public func requestAccessibilityPermission(prompt: Bool = true) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func copyToClipboard(_ items: [ClipboardItem], asPlainText: Bool = false) {
        guard !items.isEmpty else { return }
        let forcePlain = asPlainText || settings.alwaysPasteAsPlainText

        pasteboard.clearContents()

        if items.count == 1, let item = items.first {
            writeSingleItemToPasteboard(item, forcePlainText: forcePlain)
        } else {
            let joinedText = items.compactMap { item -> String? in
                if let text = item.plainText, !text.isEmpty { return text }
                if let url = item.urlString { return url }
                if !item.fileURLs.isEmpty { return item.fileURLs.joined(separator: "\n") }
                return item.ocrText
            }.joined(separator: "\n")
            pasteboard.setString(joinedText, forType: .string)
        }

        monitor.markInternalWrite(changeCount: pasteboard.changeCount)
    }

    public func pasteItems(
        _ items: [ClipboardItem],
        asPlainText: Bool = false,
        forceClipboardOnly: Bool = false,
        targetApplication: NSRunningApplication? = nil
    ) {
        guard !items.isEmpty else { return }
        copyToClipboard(items, asPlainText: asPlainText)

        if settings.soundEffects {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }

        let shouldDirectPaste = !forceClipboardOnly && (settings.pasteDestination == .activeApp)
        guard shouldDirectPaste else { return }

        if !AXIsProcessTrusted() {
            _ = requestAccessibilityPermission(prompt: true)
        }

        if let targetApp = targetApplication {
            NSApp.yieldActivation(to: targetApp)
            _ = targetApp.activate()
        } else {
            NSApp.deactivate()
        }

        waitForTargetAppAndPaste(targetApp: targetApplication, attempt: 0)
    }

    private func waitForTargetAppAndPaste(targetApp: NSRunningApplication?, attempt: Int) {
        if let targetApp = targetApp {
            let isFrontmost = targetApp.isActive ||
                (NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier)
            if !isFrontmost && attempt < 15 {
                if attempt == 4 || attempt == 9 {
                    NSApp.yieldActivation(to: targetApp)
                    _ = targetApp.activate()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                    self?.waitForTargetAppAndPaste(targetApp: targetApp, attempt: attempt + 1)
                }
                return
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.synthesizeCommandV()
        }
    }

    public func synthesizeCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    public func openItem(_ item: ClipboardItem) {
        switch item.contentType {
        case .link:
            if let urlStr = item.urlString, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        case .file:
            for path in item.fileURLs {
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.open(url)
            }
        case .image:
            if let hash = item.imageAssetHash,
               let tempURL = assetStore.exportTemporaryPNGFile(forHash: hash, preferredName: item.title) {
                NSWorkspace.shared.open(tempURL)
            }
        default:
            break
        }
    }

    public func revealInFinder(_ item: ClipboardItem) {
        if !item.fileURLs.isEmpty {
            let urls = item.fileURLs.map { URL(fileURLWithPath: $0) }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if item.contentType == .image,
                  let hash = item.imageAssetHash,
                  let tempURL = assetStore.exportTemporaryPNGFile(forHash: hash, preferredName: item.title) {
            NSWorkspace.shared.activateFileViewerSelecting([tempURL])
        }
    }

    private func writeSingleItemToPasteboard(_ item: ClipboardItem, forcePlainText: Bool) {
        if forcePlainText {
            let text = item.plainText ?? item.urlString ?? item.colorHex ?? item.ocrText ?? ""
            pasteboard.setString(text, forType: .string)
            return
        }

        switch item.contentType {
        case .file:
            let urls = item.fileURLs.map { NSURL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls)
            if let text = item.plainText {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let hash = item.imageAssetHash,
               let data = assetStore.loadData(forHash: hash) {
                pasteboard.setData(data, forType: .png)
                if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
                // Also materialize a temporary .png file URL so pasting into Finder or file inputs works seamlessly
                if let tempURL = assetStore.exportTemporaryPNGFile(forHash: hash, preferredName: item.title) {
                    pasteboard.writeObjects([tempURL as NSURL])
                }
            }
        case .link:
            if let urlStr = item.urlString {
                pasteboard.setString(urlStr, forType: .string)
                if let url = URL(string: urlStr) {
                    pasteboard.writeObjects([url as NSURL])
                }
            }
        case .text, .code, .color:
            if let text = item.plainText {
                pasteboard.setString(text, forType: .string)
            }
            if let rtfHash = item.rtfAssetHash, let rtfData = assetStore.loadData(forHash: rtfHash) {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let htmlHash = item.htmlAssetHash, let htmlData = assetStore.loadData(forHash: htmlHash) {
                pasteboard.setData(htmlData, forType: .html)
            }
        }
    }
}

import Foundation
import AppKit
import ApplicationServices

public final class IntelligentClipboardService: @unchecked Sendable {
    public static let shared = IntelligentClipboardService()

    public init() {}

    public func suggestedItems(
        from allItems: [ClipboardItem],
        targetApp: NSRunningApplication?,
        settings: VoidSettings = .shared,
        limit: Int = 12
    ) -> [ClipboardItem] {
        guard settings.intelligentClipboardEnabled, !allItems.isEmpty else {
            return []
        }

        let bundleID = targetApp?.bundleIdentifier ?? ""
        let appName = targetApp?.localizedName ?? ""
        let windowTitle = activeWindowTitle(for: targetApp) ?? ""

        let isIDE = [
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.exafunction.windsurf",
            "com.apple.Terminal",
            "com.googlecode.iterm2"
        ].contains(bundleID)

        let isDesignApp = [
            "com.figma.Desktop",
            "com.bohemiancoding.sketch3",
            "com.adobe.Photoshop"
        ].contains(bundleID)

        let isBrowser = [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "org.mozilla.firefox"
        ].contains(bundleID)

        let now = Date()

        let scored: [(item: ClipboardItem, score: Double)] = allItems.map { item in
            var score: Double = 0

            // Recency boost
            let ageMinutes = max(1.0, now.timeIntervalSince(item.lastCopiedAt) / 60.0)
            score += 20.0 / sqrt(ageMinutes)

            // Pinned items are frequently reused
            if item.pinboardID != nil {
                score += 12.0
            }

            // Context affinity with target application
            if isIDE {
                if item.contentType == .code { score += 35.0 }
                if item.contentType == .color { score += 18.0 }
                if item.contentType == .text { score += 10.0 }
            } else if isDesignApp {
                if item.contentType == .color { score += 40.0 }
                if item.contentType == .image { score += 30.0 }
                if item.contentType == .link { score += 15.0 }
            } else if isBrowser {
                if item.contentType == .link { score += 30.0 }
                if item.contentType == .text { score += 20.0 }
            } else {
                if item.contentType == .text { score += 20.0 }
                if item.contentType == .link { score += 18.0 }
            }

            // Cross-app transfer bonus (copied from a different app into target app)
            if let src = item.sourceAppBundleID, !bundleID.isEmpty, src != bundleID {
                score += 8.0
            }

            // Window title keyword overlap
            if !windowTitle.isEmpty {
                let words = windowTitle.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                let itemCorpus = [item.title, item.plainText, item.linkTitle, item.ocrText]
                    .compactMap { $0?.lowercased() }
                    .joined(separator: " ")
                for w in words where w.count >= 4 && itemCorpus.contains(w) {
                    score += 15.0
                }
            }

            if !appName.isEmpty, item.title?.localizedCaseInsensitiveContains(appName) == true {
                score += 10.0
            }

            return (item, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.item)
    }

    private func activeWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier, AXIsProcessTrusted() else { return nil }
        let appElem = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else {
            return nil
        }
        var titleVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleVal) == .success,
           let title = titleVal as? String {
            return title
        }
        return nil
    }
}

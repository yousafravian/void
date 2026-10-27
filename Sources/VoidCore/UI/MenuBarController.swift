import AppKit
import SwiftUI

@MainActor
public final class MenuBarController: NSObject {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private let panelController: VoidPanelController
    private let viewModel: VoidViewModel
    private let monitor: PasteboardMonitor

    public override init() {
        self.panelController = .shared
        self.viewModel = .shared
        self.monitor = .shared
        super.init()
    }

    public func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "Void")
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            panelController.togglePanel()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentContextMenu(from: sender)
        } else {
            panelController.togglePanel()
        }
    }

    private func presentContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Show Void", action: #selector(toggleVoidPanel), keyEquivalent: "V")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        let stackItem = NSMenuItem(title: "Paste Stack", action: #selector(togglePasteStack), keyEquivalent: "C")
        stackItem.keyEquivalentModifierMask = [.command, .shift]
        stackItem.target = self
        menu.addItem(stackItem)

        menu.addItem(.separator())

        // Pause Submenu
        let pauseMenu = NSMenu()
        if monitor.isPaused {
            let resumeItem = NSMenuItem(title: "Resume Capture", action: #selector(resumeCapture), keyEquivalent: "")
            resumeItem.target = self
            pauseMenu.addItem(resumeItem)
            pauseMenu.addItem(.separator())
        }
        for (idx, duration) in PauseDuration.allCases.enumerated() {
            let item = NSMenuItem(title: duration.rawValue, action: #selector(pauseForDuration(_:)), keyEquivalent: "")
            item.tag = idx
            item.target = self
            pauseMenu.addItem(item)
        }

        let pauseRoot = NSMenuItem(
            title: monitor.isPaused ? "Paused (Resume…)" : "Pause Void",
            action: nil,
            keyEquivalent: ""
        )
        pauseRoot.submenu = pauseMenu
        menu.addItem(pauseRoot)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About Void", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let helpItem = NSMenuItem(title: "Help & Shortcuts", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Void", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleVoidPanel() {
        panelController.togglePanel()
    }

    @objc private func togglePasteStack() {
        viewModel.togglePasteStack()
    }

    @objc private func resumeCapture() {
        monitor.resume()
    }

    @objc private func pauseForDuration(_ sender: NSMenuItem) {
        let all = PauseDuration.allCases
        guard sender.tag >= 0 && sender.tag < all.count else { return }
        monitor.pause(for: all[sender.tag])
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Void",
            .applicationVersion: "1.0.0 (Paste 6 Native Clone)",
            .credits: NSAttributedString(
                string: "Endless, effortless clipboard manager for macOS with Liquid Glass UI, Vision OCR, Pinboards, Paste Stack, and Local MCP Server."
            )
        ])
    }

    @objc private func showHelp() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

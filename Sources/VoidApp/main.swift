import AppKit
import SwiftUI
import VoidCore

@MainActor
final class VoidAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize core services
        _ = DatabaseManager.shared
        _ = AssetStore.shared
        let viewModel = VoidViewModel.shared
        let settings = VoidSettings.shared

        // Start clipboard monitoring & retention cleanup
        PasteboardMonitor.shared.startMonitoring(interval: 0.2)
        viewModel.retentionService.startPeriodicCleanup()

        // Start local MCP Server on 127.0.0.1:39725/mcp
        MCPServerService.shared.startIfNeeded()

        // Setup Menu Bar Status Item
        MenuBarController.shared.setupStatusItem()

        // Register Global Hotkeys (Shift-Command-V & Shift-Command-C)
        GlobalHotkeyManager.shared.onActivateVoid = {
            Task { @MainActor in
                VoidPanelController.shared.togglePanel()
            }
        }
        GlobalHotkeyManager.shared.onActivatePasteStack = {
            Task { @MainActor in
                VoidViewModel.shared.togglePasteStack()
            }
        }
        GlobalHotkeyManager.shared.registerHotkeys(settings: settings)

        // Prompt for Accessibility permission on launch if not yet granted so Direct Paste (⌘V synthesis) works
        if !PasteService.shared.isAccessibilityTrusted {
            _ = PasteService.shared.requestAccessibilityPermission(prompt: true)
        }

        // Present the bottom Liquid Glass panel on initial launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            VoidPanelController.shared.showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        VoidPanelController.shared.showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        PasteboardMonitor.shared.stopMonitoring()
        MCPServerService.shared.stop()
        GlobalHotkeyManager.shared.unregisterHotkeys()
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { VoidAppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

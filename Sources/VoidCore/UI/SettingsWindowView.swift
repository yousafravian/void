import SwiftUI
import AppKit

public struct SettingsWindowView: View {
    @ObservedObject public var settings: VoidSettings
    @ObservedObject public var viewModel: VoidViewModel
    @ObservedObject public var mcpServer: MCPServerService

    @State private var selectedTab: Int = 0
    @State private var showEraseConfirmation: Bool = false
    @State private var showConnectAIWizard: Bool = false
    @State private var showMCPAdvancedSheet: Bool = false
    @State private var selectedWizardClient: MCPClientType = .claudeDesktop

    @MainActor
    public init(
        settings: VoidSettings = .shared,
        viewModel: VoidViewModel? = nil,
        mcpServer: MCPServerService = .shared
    ) {
        self.settings = settings
        self.viewModel = viewModel ?? .shared
        self.mcpServer = mcpServer
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
                .tag(1)

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(2)

            mcpAndAIToolsTab
                .tabItem {
                    Label("MCP & AI Tools", systemImage: "sparkles")
                }
                .tag(3)
        }
        .frame(width: 560, height: 470)
        .padding(8)
    }

    // MARK: - 1. General Tab
    private var generalTab: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $settings.openAtLogin)
                Toggle("Run in background (menu bar icon)", isOn: $settings.runInBackground)
                Toggle("Sound effects", isOn: $settings.soundEffects)
                Toggle("Intelligent Clipboard (Suggestions tab)", isOn: $settings.intelligentClipboardEnabled)
            }

            Divider()
                .padding(.vertical, 6)

            Section {
                Picker("Paste Items:", selection: $settings.pasteDestination) {
                    ForEach(PasteDestinationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.pasteService.isAccessibilityTrusted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.pasteService.isAccessibilityTrusted
                         ? "Accessibility permission granted for Direct Paste"
                         : "Direct Paste requires Accessibility permission")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    if !viewModel.pasteService.isAccessibilityTrusted {
                        Button("Grant Access…") {
                            _ = viewModel.pasteService.requestAccessibilityPermission(prompt: true)
                        }
                        .controlSize(.small)
                    }
                }

                Toggle("Always paste as Plain Text", isOn: $settings.alwaysPasteAsPlainText)
            }

            Divider()
                .padding(.vertical, 6)

            Section {
                Picker("Keep History:", selection: $settings.retentionPeriod) {
                    ForEach(HistoryRetentionPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .onChange(of: settings.retentionPeriod) { _, _ in
                    _ = viewModel.retentionService.runCleanupNow()
                    viewModel.refreshAll()
                }

                HStack {
                    Text("Pinned items on Pinboards are never auto-deleted.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showEraseConfirmation = true
                    } label: {
                        Text("Erase History…")
                    }
                }
            }
        }
        .padding(18)
        .alert("Erase Clipboard History?", isPresented: $showEraseConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Erase Unpinned History", role: .destructive) {
                _ = viewModel.retentionService.eraseAllUnpinnedHistory()
                viewModel.refreshAll()
            }
        } message: {
            Text("This will permanently remove all unpinned clipboard history items. Items pinned to your Pinboards will be preserved.")
        }
    }

    // MARK: - 2. Privacy Tab
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Show during screen sharing", isOn: $settings.showDuringScreenSharing)
            Toggle("Generate link previews", isOn: $settings.generateLinkPreviews)
            Toggle("Ignore confidential content (Passwords, 1Password, ConcealedType)", isOn: $settings.ignoreConfidentialContent)
            Toggle("Ignore transient content (Text expanders, AutoGeneratedType)", isOn: $settings.ignoreTransientContent)

            Divider()

            Text("Ignore Applications:")
                .font(.system(size: 12.5, weight: .semibold))

            List {
                ForEach(settings.ignoredAppBundleIDs, id: \.self) { bundleID in
                    HStack {
                        if let icon = AppIconColorExtractor.shared.appIcon(forBundleID: bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app.fill")
                                .frame(width: 20, height: 20)
                        }
                        Text(bundleID)
                            .font(.system(size: 12))
                        Spacer()
                        Button {
                            settings.ignoredAppBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 145)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("+ Add Application…") {
                    chooseApplicationToIgnore()
                }
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(18)
    }

    private func chooseApplicationToIgnore() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application to Ignore"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK,
           let url = panel.url,
           let bundle = Bundle(url: url),
           let bundleID = bundle.bundleIdentifier {
            if !settings.ignoredAppBundleIDs.contains(bundleID) {
                settings.ignoredAppBundleIDs.append(bundleID)
            }
        }
    }

    // MARK: - 3. Shortcuts Tab
    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Global & Navigation Shortcuts") {
                VStack(spacing: 10) {
                    shortcutRow(title: "Activate Void", shortcut: $settings.activateVoidShortcut)
                    shortcutRow(title: "Activate Paste Stack", shortcut: $settings.activatePasteStackShortcut)
                    shortcutRow(title: "Next Pinboard", shortcut: $settings.nextPinboardShortcut)
                    shortcutRow(title: "Previous Pinboard", shortcut: $settings.prevPinboardShortcut)
                }
                .padding(8)
            }

            GroupBox("Paste Modifiers") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Quick Paste (1…9):", selection: $settings.quickPasteModifier) {
                        ForEach(ShortcutModifierChoice.allCases, id: \.self) { choice in
                            Text("\(choice.rawValue) (\(choice.symbol)1…9)").tag(choice)
                        }
                    }

                    Picker("Paste as Plain Text:", selection: $settings.plainTextModifier) {
                        ForEach(ShortcutModifierChoice.allCases, id: \.self) { choice in
                            Text("\(choice.rawValue) (\(choice.symbol)↩)").tag(choice)
                        }
                    }
                }
                .padding(8)
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetShortcutsToDefaults()
                    GlobalHotkeyManager.shared.registerHotkeys(settings: settings)
                }
            }
        }
        .padding(18)
    }

    private func shortcutRow(title: String, shortcut: Binding<CustomShortcut>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5))
            Spacer()
            Text(shortcut.wrappedValue.keyDisplay)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - 4. MCP & AI Tools Tab (Matching Paste 6 Screenshot)
    private var mcpAndAIToolsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Enable MCP card
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable MCP")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(mcpServer.endpointURLString)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Advanced…") {
                    showMCPAdvancedSheet = true
                }
                .controlSize(.small)

                Toggle("", isOn: $settings.mcpEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: settings.mcpEnabled) { _, _ in
                        mcpServer.startIfNeeded()
                    }
            }
            .padding(14)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Connected AI Tools")
                .font(.system(size: 13, weight: .semibold))

            List {
                if mcpServer.connectedClients.isEmpty {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.secondary)
                        Text("No AI tools connected yet. Click \"Connect AI Tool…\" below to set up Claude, Codex, Cursor, or VS Code.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(mcpServer.connectedClients) { client in
                        HStack(spacing: 12) {
                            Image(systemName: client.clientType.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.voidOrange)
                                .frame(width: 28, height: 28)
                                .background(Color.voidOrange.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 7))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.clientName)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(client.lastConnectedSummary)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Menu {
                                Button("Copy Configuration Snippet") {
                                    let snippet = mcpServer.configurationSnippet(for: client.clientType)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(snippet, forType: .string)
                                    viewModel.monitor.markInternalWrite(changeCount: NSPasteboard.general.changeCount)
                                }
                                Divider()
                                Button(role: .destructive) {
                                    mcpServer.disconnectClient(id: client.id)
                                } label: {
                                    Text("Disconnect")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 195)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button("Connect AI Tool…") {
                    showConnectAIWizard = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(mcpServer.isRunning ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(mcpServer.isRunning ? "Server listening on port \(mcpServer.activePort)" : "Server stopped")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(18)
        .sheet(isPresented: $showConnectAIWizard) {
            connectAIWizardSheet
        }
        .sheet(isPresented: $showMCPAdvancedSheet) {
            mcpAdvancedSheet
        }
    }

    private var connectAIWizardSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect AI Tool to Void MCP")
                .font(.system(size: 15, weight: .semibold))

            Picker("AI Tool:", selection: $selectedWizardClient) {
                ForEach(MCPClientType.allCases, id: \.self) { cType in
                    Text(cType.rawValue).tag(cType)
                }
            }

            Text("Configuration Snippet:")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            let snippet = mcpServer.configurationSnippet(for: selectedWizardClient)
            ScrollView {
                Text(snippet)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 150)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Copy Snippet") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    viewModel.monitor.markInternalWrite(changeCount: NSPasteboard.general.changeCount)
                }

                Spacer()

                Button("Cancel") {
                    showConnectAIWizard = false
                }

                Button("Register & Connect") {
                    _ = mcpServer.registerOrConnectClient(type: selectedWizardClient)
                    showConnectAIWizard = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var mcpAdvancedSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Advanced MCP Settings")
                .font(.system(size: 15, weight: .semibold))

            HStack {
                Text("Localhost Port:")
                TextField("39725", value: $settings.mcpPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bearer Auth Token:")
                    .font(.system(size: 12))
                HStack {
                    Text(settings.mcpAuthToken)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button("Regenerate") {
                        settings.regenerateMCPToken()
                    }
                    .controlSize(.small)
                }
            }

            Toggle("Require approval prompt for new clients", isOn: $settings.mcpRequireApproval)

            HStack {
                Spacer()
                Button("Done") {
                    mcpServer.startIfNeeded()
                    showMCPAdvancedSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voidOrange)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

@MainActor
public final class SettingsWindowController {
    public static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    public func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Void Settings"
            w.center()
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsWindowView())
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

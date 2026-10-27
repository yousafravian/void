import Foundation
import ServiceManagement
import Combine

public struct CustomShortcut: Codable, Equatable, Sendable {
    public var keyDisplay: String
    public var keyCode: UInt32
    public var modifiers: UInt32 // Carbon modifier flags or NSEvent.ModifierFlags raw value

    public init(keyDisplay: String, keyCode: UInt32, modifiers: UInt32) {
        self.keyDisplay = keyDisplay
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultActivateVoid = CustomShortcut(keyDisplay: "⇧⌘V", keyCode: 9, modifiers: 0x0100 | 0x0200) // cmdKey | shiftKey, kVK_ANSI_V = 9
    public static let defaultActivatePasteStack = CustomShortcut(keyDisplay: "⇧⌘C", keyCode: 8, modifiers: 0x0100 | 0x0200) // cmdKey | shiftKey, kVK_ANSI_C = 8
    public static let defaultNextPinboard = CustomShortcut(keyDisplay: "⌘→", keyCode: 124, modifiers: 0x0100) // cmdKey, kVK_RightArrow = 124
    public static let defaultPrevPinboard = CustomShortcut(keyDisplay: "⌘←", keyCode: 123, modifiers: 0x0100) // cmdKey, kVK_LeftArrow = 123
}

public final class VoidSettings: ObservableObject, @unchecked Sendable {
    public static let shared = VoidSettings()

    private let defaults: UserDefaults

    // MARK: - General
    @Published public var openAtLogin: Bool {
        didSet {
            defaults.set(openAtLogin, forKey: "openAtLogin")
            updateLoginItem(enabled: openAtLogin)
        }
    }

    @Published public var runInBackground: Bool {
        didSet { defaults.set(runInBackground, forKey: "runInBackground") }
    }

    @Published public var soundEffects: Bool {
        didSet { defaults.set(soundEffects, forKey: "soundEffects") }
    }

    @Published public var pasteDestination: PasteDestinationMode {
        didSet { defaults.set(pasteDestination.rawValue, forKey: "pasteDestination") }
    }

    @Published public var alwaysPasteAsPlainText: Bool {
        didSet { defaults.set(alwaysPasteAsPlainText, forKey: "alwaysPasteAsPlainText") }
    }

    @Published public var retentionPeriod: HistoryRetentionPeriod {
        didSet { defaults.set(retentionPeriod.rawValue, forKey: "retentionPeriod") }
    }

    // MARK: - Privacy
    @Published public var showDuringScreenSharing: Bool {
        didSet { defaults.set(showDuringScreenSharing, forKey: "showDuringScreenSharing") }
    }

    @Published public var generateLinkPreviews: Bool {
        didSet { defaults.set(generateLinkPreviews, forKey: "generateLinkPreviews") }
    }

    @Published public var ignoreConfidentialContent: Bool {
        didSet { defaults.set(ignoreConfidentialContent, forKey: "ignoreConfidentialContent") }
    }

    @Published public var ignoreTransientContent: Bool {
        didSet { defaults.set(ignoreTransientContent, forKey: "ignoreTransientContent") }
    }

    @Published public var ignoredAppBundleIDs: [String] {
        didSet { defaults.set(ignoredAppBundleIDs, forKey: "ignoredAppBundleIDs") }
    }

    // MARK: - Shortcuts
    @Published public var activateVoidShortcut: CustomShortcut {
        didSet { saveCodable(activateVoidShortcut, forKey: "activateVoidShortcut") }
    }

    @Published public var activatePasteStackShortcut: CustomShortcut {
        didSet { saveCodable(activatePasteStackShortcut, forKey: "activatePasteStackShortcut") }
    }

    @Published public var nextPinboardShortcut: CustomShortcut {
        didSet { saveCodable(nextPinboardShortcut, forKey: "nextPinboardShortcut") }
    }

    @Published public var prevPinboardShortcut: CustomShortcut {
        didSet { saveCodable(prevPinboardShortcut, forKey: "prevPinboardShortcut") }
    }

    @Published public var quickPasteModifier: ShortcutModifierChoice {
        didSet { defaults.set(quickPasteModifier.rawValue, forKey: "quickPasteModifier") }
    }

    @Published public var plainTextModifier: ShortcutModifierChoice {
        didSet { defaults.set(plainTextModifier.rawValue, forKey: "plainTextModifier") }
    }

    // MARK: - Intelligent Clipboard & MCP
    @Published public var intelligentClipboardEnabled: Bool {
        didSet { defaults.set(intelligentClipboardEnabled, forKey: "intelligentClipboardEnabled") }
    }

    @Published public var mcpEnabled: Bool {
        didSet { defaults.set(mcpEnabled, forKey: "mcpEnabled") }
    }

    @Published public var mcpPort: UInt16 {
        didSet { defaults.set(Int(mcpPort), forKey: "mcpPort") }
    }

    @Published public var mcpAuthToken: String {
        didSet { defaults.set(mcpAuthToken, forKey: "mcpAuthToken") }
    }

    @Published public var mcpRequireApproval: Bool {
        didSet { defaults.set(mcpRequireApproval, forKey: "mcpRequireApproval") }
    }

    // MARK: - Window Appearance
    @Published public var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: "panelHeight") }
    }

    @Published public var isCompactMode: Bool {
        didSet { defaults.set(isCompactMode, forKey: "isCompactMode") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.openAtLogin = defaults.object(forKey: "openAtLogin") as? Bool ?? false
        self.runInBackground = defaults.object(forKey: "runInBackground") as? Bool ?? true
        self.soundEffects = defaults.object(forKey: "soundEffects") as? Bool ?? true
        self.pasteDestination = PasteDestinationMode(rawValue: defaults.string(forKey: "pasteDestination") ?? "") ?? .activeApp
        self.alwaysPasteAsPlainText = defaults.object(forKey: "alwaysPasteAsPlainText") as? Bool ?? false
        self.retentionPeriod = HistoryRetentionPeriod(rawValue: defaults.string(forKey: "retentionPeriod") ?? "") ?? .month

        self.showDuringScreenSharing = defaults.object(forKey: "showDuringScreenSharing") as? Bool ?? false
        self.generateLinkPreviews = defaults.object(forKey: "generateLinkPreviews") as? Bool ?? true
        self.ignoreConfidentialContent = defaults.object(forKey: "ignoreConfidentialContent") as? Bool ?? true
        self.ignoreTransientContent = defaults.object(forKey: "ignoreTransientContent") as? Bool ?? true
        self.ignoredAppBundleIDs = defaults.stringArray(forKey: "ignoredAppBundleIDs") ?? [
            "com.apple.Passwords",
            "com.1password.1password",
            "com.bitwarden.desktop",
            "com.agilebits.onepassword7"
        ]

        self.activateVoidShortcut = Self.loadCodable(from: defaults, forKey: "activateVoidShortcut") ?? .defaultActivateVoid
        self.activatePasteStackShortcut = Self.loadCodable(from: defaults, forKey: "activatePasteStackShortcut") ?? .defaultActivatePasteStack
        self.nextPinboardShortcut = Self.loadCodable(from: defaults, forKey: "nextPinboardShortcut") ?? .defaultNextPinboard
        self.prevPinboardShortcut = Self.loadCodable(from: defaults, forKey: "prevPinboardShortcut") ?? .defaultPrevPinboard

        self.quickPasteModifier = ShortcutModifierChoice(rawValue: defaults.string(forKey: "quickPasteModifier") ?? "") ?? .command
        self.plainTextModifier = ShortcutModifierChoice(rawValue: defaults.string(forKey: "plainTextModifier") ?? "") ?? .shift

        self.intelligentClipboardEnabled = defaults.object(forKey: "intelligentClipboardEnabled") as? Bool ?? true
        self.mcpEnabled = defaults.object(forKey: "mcpEnabled") as? Bool ?? true
        let savedPort = defaults.integer(forKey: "mcpPort")
        self.mcpPort = savedPort > 0 ? UInt16(savedPort) : 39725

        if let existingToken = defaults.string(forKey: "mcpAuthToken"), !existingToken.isEmpty {
            self.mcpAuthToken = existingToken
        } else {
            let newToken = "void_mcp_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            defaults.set(newToken, forKey: "mcpAuthToken")
            self.mcpAuthToken = newToken
        }
        self.mcpRequireApproval = defaults.object(forKey: "mcpRequireApproval") as? Bool ?? false

        let savedHeight = defaults.double(forKey: "panelHeight")
        self.panelHeight = savedHeight >= 220 ? savedHeight : 330
        self.isCompactMode = defaults.object(forKey: "isCompactMode") as? Bool ?? false
    }

    public func resetShortcutsToDefaults() {
        activateVoidShortcut = .defaultActivateVoid
        activatePasteStackShortcut = .defaultActivatePasteStack
        nextPinboardShortcut = .defaultNextPinboard
        prevPinboardShortcut = .defaultPrevPinboard
        quickPasteModifier = .command
        plainTextModifier = .shift
    }

    public func regenerateMCPToken() {
        mcpAuthToken = "void_mcp_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func updateLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Ignore in non-signed / development environment
            }
        }
    }

    private func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(from defaults: UserDefaults, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

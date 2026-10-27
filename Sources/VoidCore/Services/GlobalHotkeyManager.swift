import Foundation
import Carbon
import AppKit

public final class GlobalHotkeyManager: @unchecked Sendable {
    public static let shared = GlobalHotkeyManager()

    private var activateVoidHotKeyRef: EventHotKeyRef?
    private var activateStackHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    public var onActivateVoid: (() -> Void)?
    public var onActivatePasteStack: (() -> Void)?

    private init() {}

    public func registerHotkeys(settings: VoidSettings = .shared) {
        unregisterHotkeys()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event = event, let userData = userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    DispatchQueue.main.async {
                        if hotKeyID.id == 1 {
                            manager.onActivateVoid?()
                        } else if hotKeyID.id == 2 {
                            manager.onActivatePasteStack?()
                        }
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        let voidHotKeyID = EventHotKeyID(signature: OSType(0x564F4944), id: 1) // 'VOID', 1
        RegisterEventHotKey(
            settings.activateVoidShortcut.keyCode,
            settings.activateVoidShortcut.modifiers,
            voidHotKeyID,
            GetApplicationEventTarget(),
            0,
            &activateVoidHotKeyRef
        )

        let stackHotKeyID = EventHotKeyID(signature: OSType(0x564F4944), id: 2) // 'VOID', 2
        RegisterEventHotKey(
            settings.activatePasteStackShortcut.keyCode,
            settings.activatePasteStackShortcut.modifiers,
            stackHotKeyID,
            GetApplicationEventTarget(),
            0,
            &activateStackHotKeyRef
        )
    }

    public func unregisterHotkeys() {
        if let ref = activateVoidHotKeyRef {
            UnregisterEventHotKey(ref)
            activateVoidHotKeyRef = nil
        }
        if let ref = activateStackHotKeyRef {
            UnregisterEventHotKey(ref)
            activateStackHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}

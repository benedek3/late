import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var shortcutObserver: NSObjectProtocol?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        installEventHandler()
        registerHotKey()
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .appearanceShortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerHotKey()
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

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

                guard status == noErr, hotKeyID.signature == HotKeyManager.signature, hotKeyID.id == HotKeyManager.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.action()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func registerHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: HotKeyManager.hotKeyID)
        let shortcut = AppearanceShortcut(rawValue: UserDefaults.standard.string(forKey: "selected-shortcut") ?? "") ?? .optionTab
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

private extension HotKeyManager {
    static let signature: OSType = 0x4C415445
    static let hotKeyID: UInt32 = 1
}

private extension AppearanceShortcut {
    var keyCode: UInt32 {
        switch self {
        case .optionTab:
            return UInt32(kVK_Tab)
        case .optionSpace, .commandOptionSpace, .commandShiftSpace:
            return UInt32(kVK_Space)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionTab, .optionSpace:
            return UInt32(optionKey)
        case .commandOptionSpace:
            return UInt32(cmdKey | optionKey)
        case .commandShiftSpace:
            return UInt32(cmdKey | shiftKey)
        }
    }
}

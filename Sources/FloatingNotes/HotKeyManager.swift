import Carbon.HIToolbox
import Cocoa

/// Registers one system-wide hotkey via Carbon's RegisterEventHotKey, which (unlike an NSEvent
/// global monitor) does not require Accessibility/Input Monitoring permission.
final class HotKeyManager {
    static let keyCode = UInt32(kVK_ANSI_Period)
    static let modifiers = UInt32(optionKey)
    static let displayString = "⌥."

    private static let signature: OSType = 0x464E4F54  // "FNOT"

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        register()
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    private func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.signature == HotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(Self.keyCode, Self.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

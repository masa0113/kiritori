import Carbon.HIToolbox

/// Carbon の RegisterEventHotKey によるグローバルホットキー。
/// アクセシビリティ許可なしで動作する。
final class HotKeyManager {
    static let shared = HotKeyManager()

    static let cmdShift = UInt32(cmdKey | shiftKey)

    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x4B49_5249 /* 'KIRI' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            handlers[id] = handler
        }
    }

    fileprivate func handle(id: UInt32) {
        handlers[id]?()
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
}

private func hotKeyEventCallback(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hkID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().handle(id: hkID.id)
    return noErr
}

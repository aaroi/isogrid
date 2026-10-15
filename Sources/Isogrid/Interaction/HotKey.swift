import Carbon.HIToolbox

/// A system-wide shortcut. Carbon's hot keys need no Accessibility or Input Monitoring
/// permission and never see other keystrokes.
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// `keyCode` is a `kVK_` constant, `modifiers` a combination of `controlKey`, `optionKey`, `cmdKey`, `shiftKey`.
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x4953_4752), id: id) // "ISGR"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { log.error("could not register shortcut \(keyCode) with modifiers \(modifiers): \(status)") }
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
        if status != noErr { log.error("could not install the shortcut handler: \(status)") }
    }

    fileprivate static func fire(_ id: UInt32) {
        actions[id]?()
    }
}

private nonisolated func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let id = hotKeyID.id
    // Carbon delivers application-target events on the main run loop.
    MainActor.assumeIsolated { HotKey.fire(id) }
    return noErr
}

import AppKit
import Carbon

/// 基于 Carbon RegisterEventHotKey 的全局快捷键，无需辅助功能权限
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    static let statusDidChange = Notification.Name("VeilHotKeyStatusDidChange")

    var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var isSuspended = false
    private var current: HotKey?

    /// 设置了组合键、没在录制、却没注册上：被别的应用占用了
    var registrationFailed: Bool { current != nil && !isSuspended && hotKeyRef == nil }

    /// 返回是否注册成功；暂停期间不真正注册，视为成功
    @discardableResult
    func register(_ key: HotKey) -> Bool {
        removeSystemHotKey()
        current = key
        defer { NotificationCenter.default.post(name: Self.statusDidChange, object: nil) }
        guard !isSuspended else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5645_494C), id: 1) // 'VEIL'
        // 不加 Exclusive 时，别的应用已占用的组合键也照样返回成功（实测），冲突就无从得知
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
        return status == noErr
    }

    func unregister() {
        removeSystemHotKey()
        current = nil
        NotificationCenter.default.post(name: Self.statusDidChange, object: nil)
    }

    /// 录制新快捷键时暂停，避免触发旧的
    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        if suspended { removeSystemHotKey() } else if let current { register(current) }
        NotificationCenter.default.post(name: Self.statusDidChange, object: nil)
    }

    private func removeSystemHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func display(_ flags: NSEvent.ModifierFlags, keyCode: UInt16, characters: String?) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        let special: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                         122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
                                         98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        s += special[keyCode] ?? (characters ?? "?").uppercased()
        return s
    }
}

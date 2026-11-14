import AppKit
import Combine
import CoreGraphics

final class HotkeyMonitor {
    private let settings: SettingsStore
    private let controller: SwitcherController
    private let state = HotkeyState()
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventRunLoop: CFRunLoop?
    private var eventThread: Thread?
    private var settingsSink: AnyCancellable?
    private var holdWork: DispatchWorkItem?
    private var holding = false
    private var holdForward = true

    init(settings: SettingsStore, controller: SwitcherController) {
        self.settings = settings
        self.controller = controller
        settingsSink = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.mirrorSettings() }
        }
        mirrorSettings()
    }

    func setPanelVisible(_ visible: Bool) {
        state.setPanelVisible(visible)
    }

    func start() {
        guard eventThread == nil else { return }
        guard Permissions.accessibilityGranted else { return }
        mirrorSettings()
        let thread = Thread { [weak self] in
            self?.runEventLoop()
        }
        thread.name = "TaberHotkeys"
        eventThread = thread
        thread.start()
    }

    func stop() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
        }
        if let eventRunLoop {
            CFRunLoopStop(eventRunLoop)
        }
        eventThread = nil
        machPort = nil
        runLoopSource = nil
        eventRunLoop = nil
    }

    private func runEventLoop() {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        guard let tap = locations.lazy.compactMap({ location in
            CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: HotkeyMonitor.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        }).first else { return }
        machPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        let loop = CFRunLoopGetCurrent()
        eventRunLoop = loop
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            return false
        }
        let snapshot = state.snapshot()
        if snapshot.recording { return false }
        let flags = event.flags.deviceModifiers

        if type == .flagsChanged {
            DispatchQueue.main.async { [weak self] in
                self?.modifierChanged(flags)
            }
            return false
        }
        guard type == .keyDown || type == .keyUp else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if snapshot.panelVisible {
            if type == .keyDown {
                DispatchQueue.main.async { [weak self] in
                    self?.panelKey(keyCode, flags: flags)
                }
            }
            return true
        }
        if type == .keyDown && ShortcutMatcher.matches(keyCode: keyCode, flags: flags, shortcut: snapshot.shortcut) {
            let forward = !ShortcutMatcher.isReverse(flags)
            DispatchQueue.main.async { [weak self] in
                self?.trigger(forward: forward)
            }
            return true
        }
        return false
    }

    private func trigger(forward: Bool) {
        if controller.isVisible {
            controller.cycle(forward: forward)
            return
        }
        if holding {
            holdWork?.cancel()
            holdWork = nil
            holding = false
            controller.show(forward: holdForward)
            controller.cycle(forward: forward)
            return
        }
        holding = true
        holdForward = forward
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.holding else { return }
            self.holding = false
            self.controller.show(forward: forward)
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func modifierChanged(_ flags: NSEvent.ModifierFlags) {
        let shortcut = state.snapshot().shortcut
        guard !ShortcutMatcher.requiredStillHeld(flags, shortcut: shortcut) else { return }
        holdWork?.cancel()
        holdWork = nil
        if controller.isVisible {
            holding = false
            controller.confirm()
        } else if holding {
            holding = false
            controller.quickSwitch(forward: holdForward)
        }
    }

    private func panelKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let shortcut = state.snapshot().shortcut
        if keyCode == 53 {
            if controller.clearQueryIfNeeded() { return }
            controller.cancel()
            return
        }
        if keyCode == 51 {
            controller.deleteQueryCharacter()
            return
        }
        if keyCode == shortcut.keyCode && ShortcutMatcher.requiredStillHeld(flags, shortcut: shortcut) {
            controller.cycle(forward: !ShortcutMatcher.isReverse(flags))
            return
        }
        if flags.contains(.command), keyCode == 13 {
            controller.closeSelected()
            return
        }
        if flags.contains(.command), keyCode == 46 {
            controller.minimizeSelected()
            return
        }
        guard !flags.contains(.option), !flags.contains(.control),
              let character = SwitcherTyping.character(for: keyCode) else { return }
        controller.appendQuery(character)
    }

    private func mirrorSettings() {
        state.set(shortcut: settings.shortcut, recording: settings.isRecordingShortcut)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }
}

private final class HotkeyState {
    private let lock = NSLock()
    private var shortcut = Shortcut.default
    private var recording = false
    private var panelVisible = false

    func set(shortcut: Shortcut, recording: Bool) {
        lock.lock()
        self.shortcut = shortcut
        self.recording = recording
        lock.unlock()
    }

    func setPanelVisible(_ visible: Bool) {
        lock.lock()
        panelVisible = visible
        lock.unlock()
    }

    func snapshot() -> (shortcut: Shortcut, recording: Bool, panelVisible: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (shortcut, recording, panelVisible)
    }
}

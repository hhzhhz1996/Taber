import AppKit
import CoreGraphics

final class HotkeyMonitor {
    private let settings: SettingsStore
    private let controller: SwitcherController
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var latestFlags: NSEvent.ModifierFlags = []
    private var session = 0
    private var sessionArmed = false
    private var sessionForward = true
    private var queuedMoves = 0

    init(settings: SettingsStore, controller: SwitcherController) {
        self.settings = settings
        self.controller = controller
    }

    func start() {
        guard machPort == nil else { return }
        guard Permissions.accessibilityGranted else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        // Command+Tab 在窗口服务器里触发系统切换器。HID 层更靠前，先吞掉按键系统就收不到。
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        let tap = locations.lazy.compactMap { location in
            CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: HotkeyMonitor.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        }.first
        guard let tap else { return }
        machPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        machPort = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            return false
        }

        let flags = event.flags.deviceModifiers
        latestFlags = flags
        if settings.isRecordingShortcut {
            return false
        }

        let shortcut = settings.shortcut
        let active = controller.isVisible || sessionArmed
        if type == .flagsChanged {
            if sessionArmed && !ShortcutMatcher.requiredStillHeld(flags, shortcut: shortcut) {
                let activeSession = session
                sessionArmed = false
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.session == activeSession else { return }
                    if self.controller.isVisible {
                        self.controller.confirm()
                    }
                }
            }
            return false
        }

        guard type == .keyDown || type == .keyUp else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if active && type == .keyDown && keyCode == 53 {
            session += 1
            sessionArmed = false
            queuedMoves = 0
            DispatchQueue.main.async { [weak self] in
                self?.controller.cancel()
            }
            return true
        }

        let trigger = keyCode == shortcut.keyCode
        if active && trigger && type == .keyDown && ShortcutMatcher.requiredStillHeld(flags, shortcut: shortcut) {
            let forward = !ShortcutMatcher.isReverse(flags)
            if controller.isVisible {
                DispatchQueue.main.async { [weak self] in
                    self?.controller.cycle(forward: forward)
                }
            } else if sessionArmed {
                queuedMoves += forward ? 1 : -1
            } else {
                arm(forward: forward)
            }
            return true
        }

        if active && (type == .keyDown || type == .keyUp) {
            return true
        }

        if type == .keyDown && ShortcutMatcher.matches(keyCode: keyCode, flags: flags, shortcut: shortcut) {
            arm(forward: !ShortcutMatcher.isReverse(flags))
            return true
        }

        return false
    }

    private func arm(forward: Bool) {
        session += 1
        sessionArmed = true
        sessionForward = forward
        queuedMoves = 0
        let activeSession = session
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session == activeSession else { return }
            self.controller.show(forward: self.sessionForward)
            guard self.controller.isVisible else {
                self.sessionArmed = false
                self.queuedMoves = 0
                return
            }
            self.applyQueuedMoves()
            if !self.sessionArmed {
                self.controller.confirm()
            }
        }
    }

    private func applyQueuedMoves() {
        let moves = queuedMoves
        queuedMoves = 0
        if moves > 0 {
            for _ in 0..<moves { controller.cycle(forward: true) }
        } else if moves < 0 {
            for _ in 0..<(-moves) { controller.cycle(forward: false) }
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }
}

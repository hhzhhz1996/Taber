import AppKit
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var shortcut: Shortcut {
        didSet { persistShortcut() }
    }

    @Published var currentDisplayOnly: Bool {
        didSet { defaults.set(currentDisplayOnly, forKey: Key.currentDisplayOnly) }
    }

    @Published var includeMinimized: Bool {
        didSet { defaults.set(includeMinimized, forKey: Key.includeMinimized) }
    }

    @Published var includeWindowless: Bool {
        didSet { defaults.set(includeWindowless, forKey: Key.includeWindowless) }
    }

    @Published var includeFullscreen: Bool {
        didSet { defaults.set(includeFullscreen, forKey: Key.includeFullscreen) }
    }

    @Published var includeOtherSpaces: Bool {
        didSet { defaults.set(includeOtherSpaces, forKey: Key.includeOtherSpaces) }
    }

    @Published var includeDashboards: Bool {
        didSet { defaults.set(includeDashboards, forKey: Key.includeDashboards) }
    }

    @Published var includeHidden: Bool {
        didSet { defaults.set(includeHidden, forKey: Key.includeHidden) }
    }

    @Published var isRecordingShortcut = false

    private let defaults = UserDefaults.standard
    private var monitor: Any?

    private enum Key {
        static let keyCode = "shortcut.keyCode"
        static let modifiers = "shortcut.modifiers"
        static let currentDisplayOnly = "filter.currentDisplayOnly"
        static let includeMinimized = "filter.includeMinimized"
        static let includeWindowless = "filter.includeWindowless"
        static let includeFullscreen = "filter.includeFullscreen"
        static let includeOtherSpaces = "filter.includeOtherSpaces"
        static let includeDashboards = "filter.includeDashboards"
        static let includeHidden = "filter.includeHidden"
    }

    private init() {
        defaults.register(defaults: [
            Key.keyCode: Int(Shortcut.default.keyCode),
            Key.modifiers: Int(Shortcut.default.modifiers),
            Key.currentDisplayOnly: false,
            Key.includeMinimized: true,
            Key.includeWindowless: true,
            Key.includeFullscreen: true,
            Key.includeOtherSpaces: true,
            Key.includeDashboards: true,
            Key.includeHidden: true,
        ])
        let keyCode = UInt16(defaults.integer(forKey: Key.keyCode))
        let modifiers = UInt(defaults.integer(forKey: Key.modifiers))
        let stored = Shortcut(keyCode: keyCode, modifiers: modifiers)
        shortcut = stored.required.isEmpty ? .default : stored
        currentDisplayOnly = defaults.bool(forKey: Key.currentDisplayOnly)
        includeMinimized = defaults.bool(forKey: Key.includeMinimized)
        includeWindowless = defaults.bool(forKey: Key.includeWindowless)
        includeFullscreen = defaults.bool(forKey: Key.includeFullscreen)
        includeOtherSpaces = defaults.bool(forKey: Key.includeOtherSpaces)
        includeDashboards = defaults.bool(forKey: Key.includeDashboards)
        includeHidden = defaults.bool(forKey: Key.includeHidden)
    }

    func beginRecording() {
        endRecording()
        isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecordingShortcut else { return event }
            if event.keyCode == 53 {
                self.endRecording()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control])
            guard !modifiers.isEmpty else { return nil }
            self.shortcut = Shortcut(keyCode: event.keyCode, modifiers: modifiers.rawValue)
            self.endRecording()
            return nil
        }
    }

    func endRecording() {
        isRecordingShortcut = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func persistShortcut() {
        defaults.set(Int(shortcut.keyCode), forKey: Key.keyCode)
        defaults.set(Int(shortcut.modifiers), forKey: Key.modifiers)
    }
}

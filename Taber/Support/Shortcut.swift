import AppKit

struct Shortcut: Equatable, Codable {
    var keyCode: UInt16
    var modifiers: UInt

    static let `default` = Shortcut(
        keyCode: 48,
        modifiers: NSEvent.ModifierFlags.command.rawValue
    )

    var required: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .control])
    }
}

enum ShortcutMatcher {
    static func matches(keyCode: UInt16, flags: NSEvent.ModifierFlags, shortcut: Shortcut) -> Bool {
        guard keyCode == shortcut.keyCode else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control]
        return flags.intersection(relevant) == shortcut.required && !shortcut.required.isEmpty
    }

    static func requiredStillHeld(_ flags: NSEvent.ModifierFlags, shortcut: Shortcut) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control]
        return shortcut.required.isSubset(of: flags.intersection(relevant)) && !shortcut.required.isEmpty
    }

    static func isReverse(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.shift)
    }
}

enum ShortcutText {
    static func describe(_ shortcut: Shortcut) -> String {
        modifierSummary(shortcut) + keyName(shortcut.keyCode)
    }

    static func modifierSummary(_ shortcut: Shortcut) -> String {
        let flags = shortcut.required
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    static func keyName(_ keyCode: UInt16) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let letter = letters[keyCode] { return letter.uppercased() }
        return "键\(keyCode)"
    }

    private static let letters: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
        34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
    ]

    private static let namedKeys: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        48: "⇥", 49: "空格", 36: "↩", 53: "⎋", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

extension CGEventFlags {
    var deviceModifiers: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if contains(.maskCommand) { flags.insert(.command) }
        if contains(.maskAlternate) { flags.insert(.option) }
        if contains(.maskControl) { flags.insert(.control) }
        if contains(.maskShift) { flags.insert(.shift) }
        return flags
    }
}

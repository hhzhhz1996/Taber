import Foundation

enum SwitcherQuery {
    static func filter(_ items: [SwitchItem], query: String) -> [SwitchItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || $0.appName.localizedCaseInsensitiveContains(needle)
        }
    }
}

enum SwitcherTyping {
    static func character(for keyCode: UInt16) -> Character? {
        if let letter = letters[keyCode] { return letter }
        if let digit = digits[keyCode] { return digit }
        if keyCode == 49 { return " " }
        return nil
    }

    private static let letters: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
        34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
    ]

    private static let digits: [UInt16: Character] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]
}

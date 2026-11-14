import Foundation

enum TrayMenu {
    /// 状态栏菜单里用来打开主界面的项。避开「打开目录」「规则模式」这类会改设置或打开文件夹的项。
    static func isShowItem(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if exact.contains(folded) || exact.contains(trimmed) { return true }
        if trimmed.contains("仪表板") || folded.contains("dashboard") { return true }
        if trimmed.contains("主窗口") || trimmed.contains("主界面") { return true }
        if folded.contains("main window") { return true }
        return false
    }

    private static let exact: Set<String> = [
        "仪表板", "dashboard", "show", "open", "显示",
        "show window", "open window", "show main window",
        "打开主窗口", "显示主窗口", "显示窗口", "打开窗口", "主界面",
    ]
}

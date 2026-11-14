import AppKit
import CoreGraphics

/// 列表里的每一种条目都有自己的开关。类型在收集窗口时定下来，后面只按类型过滤。
enum WindowCategory: Equatable {
    case currentSpace
    case fullscreen
    case otherSpace
    case minimized
    case dashboard
    case background
    case hiddenApp

    /// 全屏优先。已经分配到某个桌面的窗口是其他空间，不能因为辅助功能树是空的就算成仪表盘。
    static func classify(
        onScreen: Bool,
        minimized: Bool,
        fullscreen: Bool,
        assignedToSpace: Bool,
        hasMenuExtra: Bool
    ) -> WindowCategory? {
        if minimized { return .minimized }
        if fullscreen { return .fullscreen }
        if onScreen { return .currentSpace }
        if assignedToSpace { return .otherSpace }
        if hasMenuExtra { return .dashboard }
        return nil
    }

    func included(fullscreen: Bool, otherSpaces: Bool, minimized: Bool, dashboards: Bool) -> Bool {
        switch self {
        case .currentSpace:
            return true
        case .fullscreen:
            return fullscreen
        case .otherSpace:
            return otherSpaces
        case .minimized:
            return minimized
        case .dashboard:
            return dashboards
        case .background, .hiddenApp:
            return false
        }
    }
}

struct WindowSeed {
    var windowID: CGWindowID
    var pid: pid_t
    var appName: String
    var title: String
    var cocoaFrame: CGRect
    var icon: NSImage?
    var bundleURL: URL?
    var zOrder: Int
    var minimized: Bool
    var displayID: UInt32?
    var offscreen: Bool = false
    var category: WindowCategory = .currentSpace
}

struct AppSeed {
    var pid: pid_t
    var appName: String
    var icon: NSImage?
    var bundleURL: URL?
    var hidden: Bool
}

struct SwitchItem: Identifiable {
    enum Kind {
        case window(CGWindowID)
        case windowlessApp
        case hiddenApp
    }

    let id: String
    let kind: Kind
    let pid: pid_t
    let appName: String
    let title: String
    let badge: String
    let icon: NSImage?
    let bundleURL: URL?
    var category: WindowCategory = .currentSpace

    var offscreen: Bool {
        category == .otherSpace || category == .dashboard || category == .fullscreen
    }

    var fullscreen: Bool { category == .fullscreen }

    var windowID: CGWindowID? {
        if case .window(let id) = kind { return id }
        return nil
    }
}

enum InventoryAssembler {
    static func assemble(
        onScreen: [WindowSeed],
        minimized: [WindowSeed],
        appsWithoutListedWindows: [AppSeed],
        mru: [CGWindowID],
        screens: [ScreenFrame],
        filterScreenID: UInt32?,
        includeMinimized: Bool,
        includeWindowless: Bool,
        includeFullscreen: Bool = true,
        includeOtherSpaces: Bool = true,
        includeDashboards: Bool = true,
        includeHidden: Bool = true,
        hidden: [WindowSeed] = []
    ) -> [SwitchItem] {
        let hiddenKept = hidden.filter {
            keep($0, fullscreen: includeFullscreen, otherSpaces: includeOtherSpaces, minimized: includeMinimized, dashboards: includeDashboards)
        }

        var byID: [CGWindowID: WindowSeed] = [:]
        for seed in onScreen where keep(seed, fullscreen: includeFullscreen, otherSpaces: includeOtherSpaces, minimized: includeMinimized, dashboards: includeDashboards) {
            byID[seed.windowID] = seed
        }
        for seed in hiddenKept where byID[seed.windowID] == nil {
            byID[seed.windowID] = seed
        }
        if includeMinimized {
            for seed in minimized where byID[seed.windowID] == nil {
                var seed = seed
                if seed.category == .currentSpace { seed.category = .minimized }
                byID[seed.windowID] = seed
            }
        }

        let zOrder = onScreen.sorted { $0.zOrder < $1.zOrder }.map(\.windowID)
        let extraIDs = hiddenKept.map(\.windowID) + (includeMinimized ? minimized.map(\.windowID) : [])
        var orderedIDs = MRUOrder.orderedWindowIDs(
            zOrderFrontToBack: zOrder,
            mru: mru,
            extras: extraIDs
        )
        if let filterScreenID {
            orderedIDs = orderedIDs.filter { id in
                guard let seed = byID[id] else { return false }
                if seed.category == .dashboard { return true }
                return seed.displayID == filterScreenID
            }
        }

        var items: [SwitchItem] = orderedIDs.compactMap { id in
            guard let seed = byID[id] else { return nil }
            let title = seed.title.isEmpty ? seed.appName : seed.title
            return SwitchItem(
                id: "w-\(id)",
                kind: .window(id),
                pid: seed.pid,
                appName: seed.appName,
                title: title,
                badge: badge(for: seed, screens: screens),
                icon: seed.icon,
                bundleURL: seed.bundleURL,
                category: seed.minimized ? .minimized : seed.category
            )
        }

        if includeWindowless || includeHidden {
            let apps = appsWithoutListedWindows.sorted {
                $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            for app in apps {
                let hiddenApp = app.hidden
                if hiddenApp && !includeHidden { continue }
                if !hiddenApp && !includeWindowless { continue }
                let kind: SwitchItem.Kind = hiddenApp ? .hiddenApp : .windowlessApp
                items.append(
                    SwitchItem(
                        id: "p-\(app.pid)",
                        kind: kind,
                        pid: app.pid,
                        appName: app.appName,
                        title: app.appName,
                        badge: hiddenApp ? "已隐藏" : "后台",
                        icon: app.icon,
                        bundleURL: app.bundleURL,
                        category: hiddenApp ? .hiddenApp : .background
                    )
                )
            }
        }

        return items
    }

    private static func keep(
        _ seed: WindowSeed,
        fullscreen: Bool,
        otherSpaces: Bool,
        minimized: Bool,
        dashboards: Bool
    ) -> Bool {
        if isSpareOffscreenWindow(seed) { return false }
        if seed.offscreen, seed.cocoaFrame.width < 400 || seed.cocoaFrame.height < 320 { return false }
        let category: WindowCategory = seed.minimized ? .minimized : seed.category
        return category.included(fullscreen: fullscreen, otherSpaces: otherSpaces, minimized: minimized, dashboards: dashboards)
    }

    private static func badge(for seed: WindowSeed, screens: [ScreenFrame]) -> String {
        switch seed.minimized ? WindowCategory.minimized : seed.category {
        case .fullscreen:
            return "全屏"
        case .otherSpace:
            return "其他空间"
        case .minimized:
            return "最小化"
        case .dashboard:
            return "仪表盘"
        case .background:
            return "后台"
        case .hiddenApp:
            return "已隐藏"
        case .currentSpace:
            return DisplayLayout.label(displayID: seed.displayID, screens: screens, minimized: false)
        }
    }

    /// 微信会预创建一个标题为「微信 (窗口)」的空窗口，并没有真正打开。
    private static func isSpareOffscreenWindow(_ seed: WindowSeed) -> Bool {
        guard seed.offscreen else { return false }
        return seed.title == "\(seed.appName) (窗口)" || seed.title == "\(seed.appName)（窗口）"
    }
}

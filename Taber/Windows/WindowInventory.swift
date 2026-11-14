import AppKit
import CoreGraphics

final class WindowInventory {
    private(set) var mru: [CGWindowID] = []
    var focusUpdatesSuspended = false
    var warmRequest: (() -> Void)?
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cachedKey: String?
    private var cachedAt: Date?
    private var cachedItems: [SwitchItem]?

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.observeFrontmost()
            self?.warmRequest?()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeWorkspace()
        observeFrontmost()
    }

    func invalidateCache() {
        cachedKey = nil
        cachedAt = nil
        cachedItems = nil
    }

    func noteFocused(_ windowID: CGWindowID) {
        guard windowID != 0 else { return }
        mru.removeAll { $0 == windowID }
        mru.insert(windowID, at: 0)
        if mru.count > 80 {
            mru.removeLast(mru.count - 80)
        }
        invalidateCache()
    }

    func makeItems(
        filterScreenID: UInt32?,
        includeMinimized: Bool,
        includeWindowless: Bool,
        includeFullscreen: Bool,
        includeOtherSpaces: Bool,
        includeDashboards: Bool,
        includeHidden: Bool
    ) -> [SwitchItem] {
        let cacheKey = [
            filterScreenID.map(String.init) ?? "-",
            includeMinimized ? "1" : "0",
            includeWindowless ? "1" : "0",
            includeFullscreen ? "1" : "0",
            includeOtherSpaces ? "1" : "0",
            includeDashboards ? "1" : "0",
            includeHidden ? "1" : "0",
        ].joined(separator: "|")
        if let cachedItems, cachedKey == cacheKey, let cachedAt, Date().timeIntervalSince(cachedAt) < 1.5 {
            return cachedItems
        }
        let items = buildItems(
            filterScreenID: filterScreenID,
            includeMinimized: includeMinimized,
            includeWindowless: includeWindowless,
            includeFullscreen: includeFullscreen,
            includeOtherSpaces: includeOtherSpaces,
            includeDashboards: includeDashboards,
            includeHidden: includeHidden
        )
        cachedKey = cacheKey
        cachedAt = Date()
        cachedItems = items
        return items
    }

    private func buildItems(
        filterScreenID: UInt32?,
        includeMinimized: Bool,
        includeWindowless: Bool,
        includeFullscreen: Bool,
        includeOtherSpaces: Bool,
        includeDashboards: Bool,
        includeHidden: Bool
    ) -> [SwitchItem] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != selfPID
        }
        let appsByPID = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })
        let screens = NSScreen.screens.map(\.screenFrame)
        let primaryTop = NSScreen.primaryTop

        let listed = WindowList.onScreenWindows(appsByPID: appsByPID, selfPID: selfPID)
        let onScreen: [WindowSeed] = listed.enumerated().map { index, window in
            let resolved = DisplayLayout.resolvedFrame(
                quartz: window.quartzBounds,
                primaryTop: primaryTop,
                screens: screens
            )
            let app = appsByPID[window.pid]
            let fullscreen = DisplayLayout.coversScreen(size: resolved.frame.size, screens: screens)
            return WindowSeed(
                windowID: window.windowID,
                pid: window.pid,
                appName: app?.localizedName ?? window.ownerName,
                title: window.title,
                cocoaFrame: resolved.frame,
                icon: app?.icon,
                bundleURL: app?.bundleURL,
                zOrder: index,
                minimized: false,
                displayID: resolved.screen?.id,
                category: fullscreen ? .fullscreen : .currentSpace
            )
        }

        var minimized: [WindowSeed] = []
        if includeMinimized {
            let known = Set(onScreen.map(\.windowID))
            for window in WindowAX.minimizedWindows(apps: running) where !known.contains(window.windowID) {
                guard let app = appsByPID[window.pid] else { continue }
                let quartz = window.quartzFrame ?? .zero
                let resolved = DisplayLayout.resolvedFrame(quartz: quartz, primaryTop: primaryTop, screens: screens)
                minimized.append(
                    WindowSeed(
                        windowID: window.windowID,
                        pid: window.pid,
                        appName: app.localizedName ?? "应用",
                        title: window.title,
                        cocoaFrame: resolved.frame,
                        icon: app.icon,
                        bundleURL: app.bundleURL,
                        zOrder: 10_000 + minimized.count,
                        minimized: true,
                        displayID: resolved.screen?.id,
                        category: .minimized
                    )
                )
            }
        }

        let knownIDs = Set(onScreen.map(\.windowID)).union(minimized.map(\.windowID))
        let offscreen = WindowList.offScreenMainWindows(appsByPID: appsByPID, selfPID: selfPID, excluding: knownIDs)
        let assignedIDs = WindowSpaces.assignedWindowIDs(offscreen.map(\.windowID))
        var menuExtraByPID: [pid_t: Bool] = [:]
        var hidden = offscreen
            .enumerated()
            .compactMap { index, window -> WindowSeed? in
                let resolved = DisplayLayout.resolvedFrame(
                    quartz: window.quartzBounds,
                    primaryTop: primaryTop,
                    screens: screens
                )
                let app = appsByPID[window.pid]
                let fullscreen = DisplayLayout.coversScreen(size: resolved.frame.size, screens: screens)
                let assigned = assignedIDs.contains(window.windowID)
                let hasMenu: Bool = {
                    guard !fullscreen, !assigned else { return false }
                    if let cached = menuExtraByPID[window.pid] { return cached }
                    let value = WindowAX.hasDashboardMenu(pid: window.pid)
                    menuExtraByPID[window.pid] = value
                    return value
                }()
                guard let category = WindowCategory.classify(
                    onScreen: false,
                    minimized: false,
                    fullscreen: fullscreen,
                    assignedToSpace: assigned,
                    hasMenuExtra: hasMenu
                ) else { return nil }
                return WindowSeed(
                    windowID: window.windowID,
                    pid: window.pid,
                    appName: app?.localizedName ?? window.ownerName,
                    title: window.title,
                    cocoaFrame: resolved.frame,
                    icon: app?.icon,
                    bundleURL: app?.bundleURL,
                    zOrder: 5_000 + index,
                    minimized: false,
                    displayID: resolved.screen?.id,
                    offscreen: true,
                    category: category
                )
            }

        if includeDashboards {
            let accessory = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .accessory && !$0.isTerminated && $0.processIdentifier != selfPID
            }
            let accessoryByPID = Dictionary(uniqueKeysWithValues: accessory.map { ($0.processIdentifier, $0) })
            let panels = WindowList.offScreenMainWindows(appsByPID: accessoryByPID, selfPID: selfPID, excluding: knownIDs)
            for (index, window) in panels.enumerated() {
                let resolved = DisplayLayout.resolvedFrame(
                    quartz: window.quartzBounds,
                    primaryTop: primaryTop,
                    screens: screens
                )
                let app = accessoryByPID[window.pid]
                hidden.append(
                    WindowSeed(
                        windowID: window.windowID,
                        pid: window.pid,
                        appName: app?.localizedName ?? window.ownerName,
                        title: window.title,
                        cocoaFrame: resolved.frame,
                        icon: app?.icon,
                        bundleURL: app?.bundleURL,
                        zOrder: 8_000 + index,
                        minimized: false,
                        displayID: resolved.screen?.id,
                        offscreen: true,
                        category: .dashboard
                    )
                )
            }
        }

        let pidsWithWindows = Set(onScreen.map(\.pid))
            .union(minimized.map(\.pid))
            .union(hidden.map(\.pid))
        let appsWithoutWindows: [AppSeed] = running.compactMap { app in
            guard !pidsWithWindows.contains(app.processIdentifier) else { return nil }
            if deniedBundleIDs.contains(app.bundleIdentifier ?? "") { return nil }
            return AppSeed(
                pid: app.processIdentifier,
                appName: app.localizedName ?? "应用",
                icon: app.icon,
                bundleURL: app.bundleURL,
                hidden: app.isHidden
            )
        }

        return InventoryAssembler.assemble(
            onScreen: onScreen,
            minimized: minimized,
            appsWithoutListedWindows: appsWithoutWindows,
            mru: mru,
            screens: screens,
            filterScreenID: filterScreenID,
            includeMinimized: includeMinimized,
            includeWindowless: includeWindowless,
            includeFullscreen: includeFullscreen,
            includeOtherSpaces: includeOtherSpaces,
            includeDashboards: includeDashboards,
            includeHidden: includeHidden,
            hidden: hidden
        )
    }

    private func observeWorkspace() {
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        let center = NSWorkspace.shared.notificationCenter
        for name in names {
            workspaceObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.invalidateCache()
                }
            )
        }
    }

    private func observeFrontmost() {
        guard !focusUpdatesSuspended else { return }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != selfPID
        }
        let appsByPID = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })
        guard let front = WindowList.onScreenWindows(appsByPID: appsByPID, selfPID: selfPID).first else { return }
        guard front.windowID != mru.first else { return }
        noteFocused(front.windowID)
    }
}

private struct ListedWindow {
    var windowID: CGWindowID
    var pid: pid_t
    var ownerName: String
    var title: String
    var quartzBounds: CGRect
}

private enum WindowList {
    static func onScreenWindows(appsByPID: [pid_t: NSRunningApplication], selfPID: pid_t) -> [ListedWindow] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var windows: [ListedWindow] = []
        for info in raw {
            guard let window = parse(info), window.pid != selfPID else { continue }
            guard let app = appsByPID[window.pid] else { continue }
            if deniedBundleIDs.contains(app.bundleIdentifier ?? "") { continue }
            guard window.quartzBounds.width >= 80, window.quartzBounds.height >= 60 else { continue }
            windows.append(window)
        }
        return windows
    }

    static func offScreenMainWindows(
        appsByPID: [pid_t: NSRunningApplication],
        selfPID: pid_t,
        excluding: Set<CGWindowID>
    ) -> [ListedWindow] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var windows: [ListedWindow] = []
        for info in raw {
            guard let window = parse(info, requireOnScreen: false), !excluding.contains(window.windowID) else { continue }
            guard window.pid != selfPID, appsByPID[window.pid] != nil else { continue }
            if deniedBundleIDs.contains(appsByPID[window.pid]?.bundleIdentifier ?? "") { continue }
            let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            guard !onScreen else { continue }
            guard !window.title.isEmpty else { continue }
            guard window.quartzBounds.width >= 400, window.quartzBounds.height >= 320 else { continue }
            windows.append(window)
        }
        return windows
    }

    private static func parse(_ info: [String: Any], requireOnScreen: Bool = true) -> ListedWindow? {
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer == 0 else { return nil }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0.01 else { return nil }
        guard let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value, windowNumber != 0 else {
            return nil
        }
        guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid > 0 else { return nil }
        let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        if requireOnScreen && !onScreen { return nil }
        guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        var rect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(bounds, &rect), rect.width > 1, rect.height > 1 else { return nil }
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        let title = info[kCGWindowName as String] as? String ?? ""
        return ListedWindow(windowID: windowNumber, pid: pid, ownerName: owner, title: title, quartzBounds: rect)
    }
}

private let deniedBundleIDs: Set<String> = [
    "com.apple.dock",
    "com.apple.systemuiserver",
    "com.apple.controlcenter",
    "com.apple.notificationcenterui",
    "com.apple.WindowManager",
    "com.apple.spotlight",
    "com.apple.universalcontrol",
    "com.apple.TextInputMenuAgent",
    "com.apple.screencaptureui",
]

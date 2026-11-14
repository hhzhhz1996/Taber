import ApplicationServices
import AppKit
import CoreGraphics

enum WindowAX {
    struct MinimizedWindow {
        var windowID: CGWindowID
        var pid: pid_t
        var title: String
        var quartzFrame: CGRect?
    }

    static func minimizedWindows(apps: [NSRunningApplication]) -> [MinimizedWindow] {
        var found: [MinimizedWindow] = []
        for app in apps {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.12)
            guard let windows = copyElements(element, kAXWindowsAttribute) else { continue }
            for window in windows {
                guard copyBool(window, kAXMinimizedAttribute) == true else { continue }
                var windowID: CGWindowID = 0
                guard _AXUIElementGetWindow(window, &windowID) == .success, windowID != 0 else { continue }
                found.append(
                    MinimizedWindow(
                        windowID: windowID,
                        pid: app.processIdentifier,
                        title: copyString(window, kAXTitleAttribute) ?? "",
                        quartzFrame: copyQuartzFrame(window)
                    )
                )
            }
        }
        return found
    }

    struct AccessibilityWindows {
        var ids: Set<CGWindowID>
        var count: Int
    }

    /// 另一个空间里的普通窗口仍在辅助功能树里。被 orderOut 的仪表盘通常不在。
    static func accessibilityWindows(pids: [pid_t]) -> [pid_t: AccessibilityWindows] {
        var result: [pid_t: AccessibilityWindows] = [:]
        for pid in pids {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.12)
            guard let windows = copyElements(element, kAXWindowsAttribute) else {
                result[pid] = AccessibilityWindows(ids: [], count: 0)
                continue
            }
            var ids = Set<CGWindowID>()
            for window in windows {
                var windowID: CGWindowID = 0
                if _AXUIElementGetWindow(window, &windowID) == .success, windowID != 0 {
                    ids.insert(windowID)
                }
            }
            result[pid] = AccessibilityWindows(ids: ids, count: windows.count)
        }
        return result
    }

    static func isOnScreen(_ windowID: CGWindowID) -> Bool {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }
    }

    /// 托盘应用把主窗口 orderOut 之后，辅助功能树里往往没有这个窗口。点状态栏菜单里的「仪表板 / Show」才能把它打开。
    private static var menuExtraCache: [pid_t: Bool] = [:]

    /// 只看菜单栏上有没有状态项，不展开菜单，避免每次列出窗口时把菜单弹出来。
    static func hasDashboardMenu(pid: pid_t) -> Bool {
        if let cached = menuExtraCache[pid] { return cached }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var found = false
        if let children = copyElements(application, kAXChildrenAttribute) {
            for child in children where copyString(child, kAXRoleAttribute) == "AXMenuBar" {
                guard let items = copyElements(child, kAXChildrenAttribute) else { continue }
                if items.contains(where: { copyString($0, kAXSubroleAttribute) == "AXMenuExtra" }) {
                    found = true
                    break
                }
            }
        }
        menuExtraCache[pid] = found
        return found
    }

    static func revealHiddenInterface(pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.4)
        guard let children = copyElements(application, kAXChildrenAttribute) else { return false }
        for child in children where copyString(child, kAXRoleAttribute) == "AXMenuBar" {
            guard let items = copyElements(child, kAXChildrenAttribute) else { continue }
            for item in items where copyString(item, kAXSubroleAttribute) == "AXMenuExtra" {
                if pressShowItem(in: item) { return true }
            }
        }
        return false
    }

    static func makeFrontmost(pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        setBool(application, kAXFrontmostAttribute, true)
    }

    static func focusFullscreen(pid: pid_t, windowID: CGWindowID) {
        guard let window = element(pid: pid, windowID: windowID) else { return }
        setBool(window, "AXFullScreen", true)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        setBool(window, kAXMainAttribute, true)
        setBool(window, kAXFocusedAttribute, true)
    }

    static func close(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let window = element(pid: pid, windowID: windowID) else { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    static func minimize(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let window = element(pid: pid, windowID: windowID) else { return false }
        setBool(window, kAXMinimizedAttribute, true)
        return copyBool(window, kAXMinimizedAttribute) == true
    }

    static func focus(pid: pid_t, windowID: CGWindowID) {
        guard let window = element(pid: pid, windowID: windowID) else { return }
        setBool(window, kAXMinimizedAttribute, false)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        setBool(window, kAXMainAttribute, true)
        setBool(window, kAXFocusedAttribute, true)
    }

    private static func element(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let windows = copyElements(application, kAXWindowsAttribute) else { return nil }
        for window in windows {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(window, &id) == .success, id == windowID {
                return window
            }
        }
        return nil
    }

    private static func copyElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func copyBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private static func setBool(_ element: AXUIElement, _ attribute: String, _ flag: Bool) {
        let value: CFBoolean = flag ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    private static func copyQuartzFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = copyValue(element, kAXPositionAttribute),
              let size = copyValue(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private static func pressShowItem(in extra: AXUIElement) -> Bool {
        guard let entry = showMenuItem(in: extra) else { return false }
        return AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success
    }

    private static func showMenuItem(in extra: AXUIElement) -> AXUIElement? {
        guard let menus = copyElements(extra, kAXChildrenAttribute) else { return nil }
        for menu in menus {
            guard let entries = copyElements(menu, kAXChildrenAttribute) else { continue }
            if let entry = entries.first(where: { TrayMenu.isShowItem(copyString($0, kAXTitleAttribute) ?? "") }) {
                return entry
            }
        }
        return nil
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        guard let typed = value, CFGetTypeID(typed) == AXValueGetTypeID() else { return nil }
        return (typed as! AXValue)
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

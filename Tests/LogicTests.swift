import AppKit
import CoreGraphics
import Foundation

@main
enum LogicTests {
    static func main() {
        var failed = 0
        func check(_ condition: Bool, _ name: String) {
            if condition {
                print("ok  \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        let primaryTop: CGFloat = 1080
        let topLeft = DisplayLayout.cocoaFrame(fromQuartz: CGRect(x: 0, y: 0, width: 100, height: 50), primaryTop: primaryTop)
        check(topLeft == CGRect(x: 0, y: 1030, width: 100, height: 50), "quartz 顶边窗口翻转到 Cocoa")

        let screens = [
            ScreenFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ScreenFrame(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
        ]
        check(DisplayLayout.ordered(screens).map(\.id) == [1, 2], "显示器从左到右编号")
        let mostlyRight = CGRect(x: 1700, y: 100, width: 500, height: 400)
        check(DisplayLayout.match(window: mostlyRight, screens: screens)?.id == 2, "跨屏窗口归到重叠更大的显示器")
        check(DisplayLayout.label(displayID: 2, screens: screens, minimized: false) == "显示器 2", "显示器标记")
        check(DisplayLayout.label(displayID: nil, screens: screens, minimized: true) == "最小化", "找不到屏幕时标最小化")

        let shortcut = Shortcut.default
        let command = NSEvent.ModifierFlags.command
        check(ShortcutMatcher.matches(keyCode: 48, flags: command, shortcut: shortcut), "Command+Tab 命中")
        check(ShortcutMatcher.matches(keyCode: 48, flags: [command, .shift], shortcut: shortcut), "Shift 不破坏匹配")
        check(!ShortcutMatcher.matches(keyCode: 48, flags: .option, shortcut: shortcut), "Option+Tab 不是默认")
        check(ShortcutMatcher.isReverse([command, .shift]), "Shift 表示反向")
        check(!ShortcutMatcher.requiredStillHeld([], shortcut: shortcut), "松开 Command 视为确认")
        check(ShortcutText.describe(shortcut) == "⌘⇥", "默认快捷键文案")
        let searchable = [
            SwitchItem(id: "w-1", kind: .window(1), pid: 1, appName: "微信", title: "文件传输助手", badge: "", icon: nil, bundleURL: nil),
            SwitchItem(id: "w-2", kind: .window(2), pid: 2, appName: "Cursor", title: "Cursor Agents", badge: "", icon: nil, bundleURL: nil),
        ]
        check(SwitcherQuery.filter(searchable, query: " 微 ").map(\.id) == ["w-1"], "按应用名筛选")
        check(SwitcherQuery.filter(searchable, query: "agents").map(\.id) == ["w-2"], "按窗口标题筛选")
        check(SwitcherQuery.filter(searchable, query: "").count == 2, "空白筛选保留全部")
        check(SwitcherTyping.character(for: 13) == "w", "W 键可以输入筛选")

        let order = MRUOrder.orderedWindowIDs(zOrderFrontToBack: [1, 2, 3], mru: [2, 1], extras: [4])
        check(order == [2, 1, 3, 4], "最近使用优先，其余按 Z 序，最小化在后")

        let chromeLeft = WindowSeed(
            windowID: 10, pid: 1, appName: "Chrome", title: "左屏",
            cocoaFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            icon: nil, bundleURL: nil, zOrder: 0, minimized: false, displayID: 1
        )
        let chromeRight = WindowSeed(
            windowID: 11, pid: 1, appName: "Chrome", title: "右屏",
            cocoaFrame: CGRect(x: 1920, y: 0, width: 800, height: 600),
            icon: nil, bundleURL: nil, zOrder: 1, minimized: false, displayID: 2
        )
        let minimized = WindowSeed(
            windowID: 12, pid: 2, appName: "Notes", title: "备忘",
            cocoaFrame: .zero, icon: nil, bundleURL: nil, zOrder: 5, minimized: true, displayID: nil
        )
        let finder = AppSeed(pid: 3, appName: "Finder", icon: nil, bundleURL: nil, hidden: false)
        let all = InventoryAssembler.assemble(
            onScreen: [chromeLeft, chromeRight],
            minimized: [minimized],
            appsWithoutListedWindows: [finder],
            mru: [10],
            screens: screens,
            filterScreenID: nil,
            includeMinimized: true,
            includeWindowless: true
        )
        check(all.map(\.id) == ["w-10", "w-11", "w-12", "p-3"], "多屏窗口、最小化、无窗口应用都在列表里")
        check(all[1].badge == "显示器 2", "右屏窗口标出所在显示器")
        check(all[3].badge == "后台", "无窗口应用单独成项")

        let currentOnly = InventoryAssembler.assemble(
            onScreen: [chromeLeft, chromeRight],
            minimized: [minimized],
            appsWithoutListedWindows: [finder],
            mru: [],
            screens: screens,
            filterScreenID: 1,
            includeMinimized: true,
            includeWindowless: true
        )
        check(currentOnly.map(\.id) == ["w-10", "p-3"], "只显示当前显示器时滤掉另一块屏")
        check(currentOnly.contains { $0.id == "w-11" } == false, "当前显示器过滤不包含另一块屏的窗口")
        check(TrayMenu.isShowItem("仪表板"), "托盘菜单仪表板会打开主界面")
        check(TrayMenu.isShowItem("打开目录") == false, "打开目录不是显示窗口")
        check(TrayMenu.isShowItem("规则模式") == false, "规则模式不会被当成打开窗口")
        let hidden = InventoryAssembler.assemble(
            onScreen: [chromeLeft],
            minimized: [],
            appsWithoutListedWindows: [finder],
            mru: [],
            screens: screens,
            filterScreenID: nil,
            includeMinimized: true,
            includeWindowless: true,
            hidden: [
                WindowSeed(
                    windowID: 20, pid: 9, appName: "Clash Verge", title: "Clash Verge",
                    cocoaFrame: CGRect(x: 100, y: 100, width: 900, height: 700),
                    icon: nil, bundleURL: nil, zOrder: 8, minimized: false, displayID: 1, offscreen: true,
                    category: .dashboard
                ),
            ]
        )
        check(hidden.contains { $0.title == "Clash Verge" && $0.badge == "仪表盘" && $0.category == .dashboard }, "收起的主窗口单独列出")
        let wechat = InventoryAssembler.assemble(
            onScreen: [
                WindowSeed(
                    windowID: 30, pid: 8, appName: "微信", title: "微信",
                    cocoaFrame: CGRect(x: 2000, y: 200, width: 1071, height: 849),
                    icon: nil, bundleURL: nil, zOrder: 0, minimized: false, displayID: 2
                ),
            ],
            minimized: [],
            appsWithoutListedWindows: [],
            mru: [],
            screens: screens,
            filterScreenID: nil,
            includeMinimized: true,
            includeWindowless: true,
            hidden: [
                WindowSeed(
                    windowID: 31, pid: 8, appName: "微信", title: "微信 (窗口)",
                    cocoaFrame: CGRect(x: 0, y: 31, width: 920, height: 890),
                    icon: nil, bundleURL: nil, zOrder: 6, minimized: false, displayID: 1, offscreen: true
                ),
                WindowSeed(
                    windowID: 32, pid: 8, appName: "微信", title: "微信",
                    cocoaFrame: CGRect(x: 1500, y: 400, width: 280, height: 380),
                    icon: nil, bundleURL: nil, zOrder: 7, minimized: false, displayID: 1, offscreen: true
                ),
            ]
        )
        check(wechat.map(\.id) == ["w-30"], "微信已有可见窗口时不列出隐藏副本")
        let ultrawide = [ScreenFrame(id: 2, frame: CGRect(x: 0, y: 0, width: 3440, height: 1440))]
        let fullscreenCursor = InventoryAssembler.assemble(
            onScreen: [],
            minimized: [],
            appsWithoutListedWindows: [],
            mru: [],
            screens: ultrawide,
            filterScreenID: nil,
            includeMinimized: true,
            includeWindowless: false,
            includeDashboards: false,
            hidden: [
                WindowSeed(
                    windowID: 40, pid: 4, appName: "Cursor", title: "Cursor Agents",
                    cocoaFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                    icon: nil, bundleURL: nil, zOrder: 1, minimized: false, displayID: 2,
                    offscreen: true, category: .fullscreen
                ),
                WindowSeed(
                    windowID: 41, pid: 5, appName: "Clash Verge", title: "Clash Verge",
                    cocoaFrame: CGRect(x: 100, y: 100, width: 940, height: 700),
                    icon: nil, bundleURL: nil, zOrder: 2, minimized: false, displayID: 2,
                    offscreen: true, category: .dashboard
                ),
            ]
        )
        check(fullscreenCursor.map(\.id) == ["w-40"], "关掉仪表盘后仍保留全屏的 Cursor")
        check(fullscreenCursor.first?.badge == "全屏", "全屏窗口标成全屏")
        check(
            WindowCategory.classify(onScreen: false, minimized: false, fullscreen: false, assignedToSpace: true, hasMenuExtra: true) == .otherSpace,
            "已经在某个桌面里的窗口是其他空间"
        )
        check(
            WindowCategory.classify(onScreen: false, minimized: false, fullscreen: false, assignedToSpace: false, hasMenuExtra: true) == .dashboard,
            "没有桌面、又有状态栏的才是仪表盘"
        )
        check(
            WindowCategory.classify(onScreen: false, minimized: false, fullscreen: false, assignedToSpace: false, hasMenuExtra: false) == nil,
            "没有桌面也没有状态栏的隐藏窗口丢掉"
        )
        let wechatOnAnotherSpace = InventoryAssembler.assemble(
            onScreen: [],
            minimized: [],
            appsWithoutListedWindows: [],
            mru: [],
            screens: ultrawide,
            filterScreenID: nil,
            includeMinimized: true,
            includeWindowless: false,
            includeDashboards: false,
            hidden: [
                WindowSeed(
                    windowID: 50, pid: 8, appName: "微信", title: "微信",
                    cocoaFrame: CGRect(x: 2120, y: 200, width: 1071, height: 849),
                    icon: nil, bundleURL: nil, zOrder: 1, minimized: false, displayID: 2,
                    offscreen: true, category: .otherSpace
                ),
            ]
        )
        check(wechatOnAnotherSpace.map(\.id) == ["w-50"], "关掉仪表盘后仍保留其他空间的微信")
        check(wechatOnAnotherSpace.first?.badge == "其他空间", "其他空间窗口标成其他空间")
        let wide = ThumbnailSizing.pixelSize(fitting: CGSize(width: 1071, height: 849))
        check(abs(Double(wide.width) / Double(wide.height) - 1071.0 / 849.0) < 0.02, "缩略图画布跟随窗口比例")
        let tall = ThumbnailSizing.pixelSize(fitting: CGSize(width: 400, height: 900))
        check(tall.height >= tall.width, "竖窗口不会被压成横图")
        check(hidden.contains { $0.id == "p-3" }, "别的无窗口应用仍然保留")

        if failed > 0 {
            print("\(failed) failed")
            exit(1)
        }
        print("all passed")
    }
}

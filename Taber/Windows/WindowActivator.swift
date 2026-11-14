import AppKit
import Carbon
import Foundation

enum WindowActivator {
    static func activate(_ item: SwitchItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        switch item.kind {
        case .window(let windowID):
            app.unhide()
            WindowSpaces.orderFront(windowID)
            WindowAX.focus(pid: item.pid, windowID: windowID)
            bringForward(app, allWindows: item.category == .otherSpace)
            WindowAX.focus(pid: item.pid, windowID: windowID)
            WindowSpaces.orderFront(windowID)
            if item.category == .fullscreen {
                WindowAX.focusFullscreen(pid: item.pid, windowID: windowID)
            } else if item.category == .dashboard, !WindowAX.isOnScreen(windowID) {
                _ = WindowAX.revealHiddenInterface(pid: item.pid)
            }
        case .hiddenApp:
            app.unhide()
            bringForward(app, allWindows: true)
        case .windowlessApp:
            app.unhide()
            bringForward(app, allWindows: false)
            reopen(pid: item.pid, bundleURL: item.bundleURL)
        }
    }

    private static func bringForward(_ app: NSRunningApplication, allWindows: Bool) {
        NSApp.yieldActivation(to: app)
        WindowAX.makeFrontmost(pid: app.processIdentifier)
        let options: NSApplication.ActivationOptions = allWindows ? [.activateAllWindows] : []
        if !app.activate(from: .current, options: options) {
            app.activate(options: options)
        }
    }

    /// 等价于点一次 Dock 图标：应用没有窗口时，让它打开主界面。
    private static func reopen(pid: pid_t, bundleURL: URL?) {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            _ = try event.sendEvent(options: [.noReply, .neverInteract], timeout: 1.5)
        } catch {
            openBundle(bundleURL)
        }
    }

    private static func openBundle(_ bundleURL: URL?) {
        guard let bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
    }
}

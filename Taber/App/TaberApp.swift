import AppKit
import SwiftUI

@main
enum TaberMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore.shared
    private let inventory = WindowInventory()
    private let thumbnails = ThumbnailCache()
    private var controller: SwitcherController!
    private var hotkey: HotkeyMonitor!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private let permissions = PermissionModel()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        controller = SwitcherController(inventory: inventory, thumbnails: thumbnails, settings: settings)
        hotkey = HotkeyMonitor(settings: settings, controller: controller)
        inventory.start()
        installStatusItem()
        hotkey.start()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        if !Permissions.allGranted {
            showPermissions(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.stop()
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Taber") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "Taber"
        let menu = NSMenu()
        menu.addItem(item("设置…", action: #selector(showSettings(_:)), key: ","))
        menu.addItem(item("权限…", action: #selector(showPermissions(_:)), key: ""))
        menu.addItem(.separator())
        menu.addItem(item("退出", action: #selector(quit(_:)), key: "q"))
        statusItem.menu = menu
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item("设置…", action: #selector(showSettings(_:)), key: ","))
        appMenu.addItem(item("权限…", action: #selector(showPermissions(_:)), key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出 Taber", action: #selector(quit(_:)), key: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showSettings(_ sender: Any?) {
        let window = settingsWindow ?? makeWindow(title: "设置", view: SettingsView(store: settings), size: NSSize(width: 480, height: 560))
        settingsWindow = window
        present(window)
    }

    @objc private func showPermissions(_ sender: Any?) {
        permissions.refresh()
        let window = permissionsWindow ?? makeWindow(
            title: "权限",
            view: PermissionsView(model: permissions),
            size: NSSize(width: 520, height: 420)
        )
        permissionsWindow = window
        present(window)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func refreshPermissions() {
        permissions.refresh()
        if Permissions.accessibilityGranted {
            hotkey.start()
        }
    }

    private func makeWindow<V: View>(title: String, view: V, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

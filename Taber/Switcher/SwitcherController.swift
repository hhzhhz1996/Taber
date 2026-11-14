import AppKit

final class SwitcherModel: ObservableObject {
    @Published var items: [SwitchItem] = []
    @Published var selectedIndex = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var hint = ""
    @Published private(set) var isVisible = false
    var onActivate: ((Int) -> Void)?

    func setVisible(_ visible: Bool) {
        isVisible = visible
    }

    func setThumbnail(_ windowID: CGWindowID, image: NSImage) {
        thumbnails[windowID] = image
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }
}

final class SwitcherController {
    let model = SwitcherModel()
    private let panel: SwitcherPanel
    private let inventory: WindowInventory
    private let thumbnails: ThumbnailCache
    private let settings: SettingsStore

    init(inventory: WindowInventory, thumbnails: ThumbnailCache, settings: SettingsStore) {
        self.inventory = inventory
        self.thumbnails = thumbnails
        self.settings = settings
        panel = SwitcherPanel(model: model)
        thumbnails.onUpdate = { [weak model] windowID, image in
            model?.setThumbnail(windowID, image: image)
        }
        model.onActivate = { [weak self] index in
            self?.activateFromClick(index)
        }
    }

    var isVisible: Bool { model.isVisible }

    func show(forward: Bool) {
        if model.isVisible {
            cycle(forward: forward)
            return
        }
        let items = currentItems()
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        model.thumbnails = [:]
        model.items = items
        model.selectedIndex = initialIndex(count: items.count, forward: forward)
        model.hint = "松开 \(ShortcutText.modifierSummary(settings.shortcut)) 切换 · Esc 取消"
        model.setVisible(true)
        inventory.focusUpdatesSuspended = true
        let screen = mouseScreen()
        panel.present(on: screen, size: SwitcherMetrics.size(itemCount: items.count, screen: screen))
        thumbnails.load(windowIDs: items.compactMap(\.windowID))
    }

    func cycle(forward: Bool) {
        guard model.isVisible, !model.items.isEmpty else { return }
        let count = model.items.count
        if forward {
            model.selectedIndex = (model.selectedIndex + 1) % count
        } else {
            model.selectedIndex = (model.selectedIndex - 1 + count) % count
        }
    }

    func confirm() {
        guard model.isVisible else { return }
        let item = model.items.indices.contains(model.selectedIndex) ? model.items[model.selectedIndex] : nil
        hide()
        guard let item else { return }
        if let windowID = item.windowID {
            inventory.noteFocused(windowID)
        }
        WindowActivator.activate(item)
    }

    func cancel() {
        hide()
    }

    private func activateFromClick(_ index: Int) {
        guard model.isVisible else { return }
        model.select(index)
        confirm()
    }

    private func hide() {
        guard model.isVisible else { return }
        model.setVisible(false)
        panel.orderOut(nil)
        inventory.focusUpdatesSuspended = false
        thumbnails.cancel()
    }

    private func currentItems() -> [SwitchItem] {
        var filterID: UInt32?
        if settings.currentDisplayOnly {
            filterID = mouseScreen()?.displayID
        }
        return inventory.makeItems(
            filterScreenID: filterID,
            includeMinimized: settings.includeMinimized,
            includeWindowless: settings.includeWindowless,
            includeFullscreen: settings.includeFullscreen,
            includeOtherSpaces: settings.includeOtherSpaces,
            includeDashboards: settings.includeDashboards,
            includeHidden: settings.includeHidden
        )
    }

    private func mouseScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func initialIndex(count: Int, forward: Bool) -> Int {
        guard count > 1 else { return 0 }
        return forward ? 1 : count - 1
    }
}

enum SwitcherMetrics {
    static let cellStride: CGFloat = 236
    static let height: CGFloat = 286

    static func size(itemCount: Int, screen: NSScreen?) -> NSSize {
        let available = max((screen?.visibleFrame.width ?? 1280) - 72, 320)
        let content = CGFloat(max(itemCount, 1)) * cellStride + 36
        return NSSize(width: min(available, max(320, content)), height: height)
    }
}

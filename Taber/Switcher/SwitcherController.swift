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
    var onVisibilityChange: ((Bool) -> Void)?
    private var allItems: [SwitchItem] = []
    private var query = ""

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
        inventory.warmRequest = { [weak self] in
            guard let self, !self.model.isVisible else { return }
            _ = self.currentItems()
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
            onVisibilityChange?(false)
            NSSound.beep()
            return
        }
        allItems = items
        query = ""
        model.thumbnails = [:]
        model.items = items
        model.selectedIndex = initialIndex(count: items.count, forward: forward)
        model.hint = hintText()
        onVisibilityChange?(true)
        model.setVisible(true)
        inventory.focusUpdatesSuspended = true
        let screen = mouseScreen()
        panel.present(on: screen, size: SwitcherMetrics.size(itemCount: items.count, screen: screen))
        let selected = items[model.selectedIndex].windowID
        thumbnails.load(windowIDs: items.compactMap(\.windowID), preferredID: selected)
    }

    func quickSwitch(forward: Bool) {
        let items = currentItems()
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        let index = initialIndex(count: items.count, forward: forward)
        activate(items[index])
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
        let item = selectedItem()
        hide()
        guard let item else { return }
        activate(item)
    }

    func cancel() {
        hide()
    }

    func appendQuery(_ character: Character) {
        guard model.isVisible else { return }
        query.append(character)
        applyQuery(keepSelection: false)
    }

    func deleteQueryCharacter() {
        guard model.isVisible, !query.isEmpty else { return }
        query.removeLast()
        applyQuery(keepSelection: false)
    }

    func clearQueryIfNeeded() -> Bool {
        guard model.isVisible, !query.isEmpty else { return false }
        query = ""
        applyQuery(keepSelection: false)
        return true
    }

    func closeSelected() {
        guard let item = selectedItem() else { return }
        switch item.kind {
        case .window(let windowID):
            guard WindowAX.close(pid: item.pid, windowID: windowID) else {
                NSSound.beep()
                return
            }
        case .windowlessApp, .hiddenApp:
            NSRunningApplication(processIdentifier: item.pid)?.terminate()
        }
        remove(item)
    }

    func minimizeSelected() {
        guard let item = selectedItem(), case .window(let windowID) = item.kind else {
            NSSound.beep()
            return
        }
        guard WindowAX.minimize(pid: item.pid, windowID: windowID) else {
            NSSound.beep()
            return
        }
        remove(item)
    }

    private func activateFromClick(_ index: Int) {
        guard model.isVisible else { return }
        model.select(index)
        confirm()
    }

    private func hide() {
        guard model.isVisible else { return }
        query = ""
        onVisibilityChange?(false)
        model.setVisible(false)
        panel.orderOut(nil)
        inventory.focusUpdatesSuspended = false
        thumbnails.cancel()
    }

    private func activate(_ item: SwitchItem) {
        if let windowID = item.windowID {
            inventory.noteFocused(windowID)
        }
        WindowActivator.activate(item)
    }

    private func selectedItem() -> SwitchItem? {
        guard model.items.indices.contains(model.selectedIndex) else { return nil }
        return model.items[model.selectedIndex]
    }

    private func remove(_ item: SwitchItem) {
        allItems.removeAll { $0.id == item.id }
        inventory.invalidateCache()
        applyQuery(keepSelection: true)
        if model.items.isEmpty {
            cancel()
        }
    }

    private func applyQuery(keepSelection: Bool) {
        let filtered = SwitcherQuery.filter(allItems, query: query)
        let previous = selectedItem()?.id
        model.items = filtered
        if keepSelection, let previous, let index = filtered.firstIndex(where: { $0.id == previous }) {
            model.selectedIndex = index
        } else {
            model.selectedIndex = 0
        }
        model.hint = hintText()
        let selected = filtered.indices.contains(model.selectedIndex) ? filtered[model.selectedIndex].windowID : nil
        thumbnails.load(windowIDs: filtered.compactMap(\.windowID), preferredID: selected)
        let screen = mouseScreen()
        panel.present(on: screen, size: SwitcherMetrics.size(itemCount: max(filtered.count, 1), screen: screen))
    }

    private func hintText() -> String {
        if query.isEmpty {
            let modifier = ShortcutText.modifierSummary(settings.shortcut)
            return "输入文字筛选 · ⌘W 关闭 · ⌘M 最小化 · 松开 \(modifier) 切换 · Esc 取消"
        }
        return "筛选「\(query)」 · ⌫ 删除 · Esc 清除"
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
    static let height: CGFloat = 304

    static func size(itemCount: Int, screen: NSScreen?) -> NSSize {
        let available = max((screen?.visibleFrame.width ?? 1280) - 72, 320)
        let content = CGFloat(max(itemCount, 1)) * cellStride + 36
        return NSSize(width: min(available, max(320, content)), height: height)
    }
}

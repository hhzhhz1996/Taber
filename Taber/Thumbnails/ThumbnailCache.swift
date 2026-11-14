import AppKit
import CoreGraphics
import ScreenCaptureKit

final class ThumbnailCache {
    var onUpdate: ((CGWindowID, NSImage) -> Void)?
    private var task: Task<Void, Never>?
    private var images: [CGWindowID: NSImage] = [:]
    private let lock = NSLock()

    func load(windowIDs: [CGWindowID], preferredID: CGWindowID?) {
        task?.cancel()
        var seen = Set<CGWindowID>()
        var ids = windowIDs.filter { seen.insert($0).inserted }
        if let preferredID, let index = ids.firstIndex(of: preferredID) {
            ids.remove(at: index)
            ids.insert(preferredID, at: 0)
        }
        for id in ids {
            if let image = cached(id) {
                onUpdate?(id, image)
            }
        }
        let first = Array(ids.prefix(4))
        let rest = Array(ids.dropFirst(4))
        task = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.capture(first)
            guard !Task.isCancelled, !rest.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await self?.capture(rest)
        }
    }

    private func capture(_ ids: [CGWindowID]) async {
        guard !ids.isEmpty else { return }
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        var windowsByID: [CGWindowID: SCWindow] = [:]
        for window in content?.windows ?? [] {
            windowsByID[window.windowID] = window
        }
        for id in ids {
            if Task.isCancelled { return }
            let cgImage: CGImage?
            if #available(macOS 26.0, *), let window = windowsByID[id] {
                cgImage = await captureModern(window)
            } else {
                cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])
            }
            guard let cgImage else { continue }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            store(id, image: image)
            await MainActor.run { [weak self] in
                self?.onUpdate?(id, image)
            }
        }
    }

    @available(macOS 26.0, *)
    private func captureModern(_ window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let pixels = ThumbnailSizing.pixelSize(fitting: window.frame.size)
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func cached(_ id: CGWindowID) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[id]
    }

    private func store(_ id: CGWindowID, image: NSImage) {
        lock.lock()
        images[id] = image
        if images.count > 40, let oldest = images.keys.first, oldest != id {
            images.removeValue(forKey: oldest)
        }
        lock.unlock()
    }
}

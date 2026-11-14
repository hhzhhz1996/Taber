import AppKit
import CoreGraphics
import ScreenCaptureKit

final class ThumbnailCache {
    var onUpdate: ((CGWindowID, NSImage) -> Void)?
    private var task: Task<Void, Never>?
    private var images: [CGWindowID: NSImage] = [:]
    private let lock = NSLock()

    func load(windowIDs: [CGWindowID]) {
        task?.cancel()
        var seen = Set<CGWindowID>()
        let ids = windowIDs.filter { seen.insert($0).inserted }
        for id in ids {
            if let image = cached(id) {
                onUpdate?(id, image)
            }
        }
        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
                return
            }
            var windowsByID: [CGWindowID: SCWindow] = [:]
            for window in content.windows {
                windowsByID[window.windowID] = window
            }
            for id in ids {
                if Task.isCancelled { return }
                guard let window = windowsByID[id] else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                let pixels = ThumbnailSizing.pixelSize(fitting: window.frame.size)
                configuration.width = pixels.width
                configuration.height = pixels.height
                configuration.scalesToFit = true
                configuration.preservesAspectRatio = true
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
                    continue
                }
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                let image = NSImage(cgImage: cgImage, size: size)
                self?.store(id, image: image)
                await MainActor.run { [weak self] in
                    self?.onUpdate?(id, image)
                }
            }
        }
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

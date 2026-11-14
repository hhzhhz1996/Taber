import AppKit
import CoreGraphics

struct ScreenFrame: Equatable {
    var id: UInt32
    var frame: CGRect
}

enum DisplayLayout {
    static func ordered(_ screens: [ScreenFrame]) -> [ScreenFrame] {
        screens.sorted { lhs, rhs in
            if abs(lhs.frame.minX - rhs.frame.minX) > 8 {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.maxY > rhs.frame.maxY
        }
    }

    /// Quartz 窗口坐标原点在主显示器左上角，Y 向下。Cocoa 原点在主显示器左下角，Y 向上。
    static func cocoaFrame(fromQuartz bounds: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(
            x: bounds.origin.x,
            y: primaryTop - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    static func coversScreen(size: CGSize, screens: [ScreenFrame]) -> Bool {
        screens.contains { screen in
            abs(screen.frame.width - size.width) < 80 && abs(screen.frame.height - size.height) < 80
        }
    }

    static func match(window: CGRect, screens: [ScreenFrame]) -> ScreenFrame? {
        var best: (ScreenFrame, CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(window)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.1 ?? 0) {
                best = (screen, area)
            }
        }
        return best?.0
    }

    static func screen(at point: CGPoint, screens: [ScreenFrame]) -> ScreenFrame? {
        screens.first { $0.frame.contains(point) }
    }

    static func label(displayID: UInt32?, screens: [ScreenFrame], minimized: Bool) -> String {
        let orderedScreens = ordered(screens)
        let index = displayID.flatMap { id in orderedScreens.firstIndex { $0.id == id } }
        if minimized {
            if let index {
                return "最小化 · 显示器 \(index + 1)"
            }
            return "最小化"
        }
        if let index {
            return "显示器 \(index + 1)"
        }
        return "显示器"
    }

    static func resolvedFrame(quartz: CGRect, primaryTop: CGFloat, screens: [ScreenFrame]) -> (frame: CGRect, screen: ScreenFrame?) {
        let converted = cocoaFrame(fromQuartz: quartz, primaryTop: primaryTop)
        if let screen = match(window: converted, screens: screens) {
            return (converted, screen)
        }
        if let screen = match(window: quartz, screens: screens) {
            return (quartz, screen)
        }
        return (converted, nil)
    }
}

extension NSScreen {
    var displayID: UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    var screenFrame: ScreenFrame {
        ScreenFrame(id: displayID, frame: frame)
    }

    static var primaryTop: CGFloat {
        screens.first?.frame.maxY ?? 0
    }
}

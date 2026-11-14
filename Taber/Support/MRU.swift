import CoreGraphics

enum MRUOrder {
    /// 最近使用在前。没有记录过的窗口按 Z 序（前到后）接在后面，其余窗口（例如最小化）再接在后面。
    static func orderedWindowIDs(
        zOrderFrontToBack: [CGWindowID],
        mru: [CGWindowID],
        extras: [CGWindowID]
    ) -> [CGWindowID] {
        var seen = Set<CGWindowID>()
        var result: [CGWindowID] = []

        func append(_ id: CGWindowID) {
            guard seen.insert(id).inserted else { return }
            result.append(id)
        }

        let known = Set(zOrderFrontToBack).union(extras)
        for id in mru where known.contains(id) {
            append(id)
        }
        for id in zOrderFrontToBack {
            append(id)
        }
        for id in extras {
            append(id)
        }
        return result
    }
}

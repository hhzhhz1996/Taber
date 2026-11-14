import CoreGraphics

enum WindowSpaces {
    static func assignedWindowIDs(_ windowIDs: [CGWindowID]) -> Set<CGWindowID> {
        guard !windowIDs.isEmpty else { return [] }
        let connection = CGSMainConnectionID()
        var assigned = Set<CGWindowID>()
        for windowID in windowIDs {
            let ids = [windowID] as CFArray
            guard let spaces = CGSCopySpacesForWindows(connection, 7, ids) as? [Any], !spaces.isEmpty else { continue }
            assigned.insert(windowID)
        }
        return assigned
    }

    static func orderFront(_ windowID: CGWindowID) {
        _ = CGSOrderWindow(CGSMainConnectionID(), windowID, 1, 0)
    }
}

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windowIDs: CFArray) -> CFArray?

@_silgen_name("CGSOrderWindow")
private func CGSOrderWindow(_ connection: Int32, _ windowID: CGWindowID, _ place: Int32, _ relativeTo: CGWindowID) -> Int32

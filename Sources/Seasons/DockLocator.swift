import AppKit
import SeasonsCore

/// Estimates the Dock's frame on a screen.
///
/// The Dock's thickness comes from `screen.frame` minus `screen.visibleFrame`. Its length is
/// not exposed by any public API (the Dock's own windows span the whole screen), so it is
/// estimated from the Dock preferences: number of tiles × tile size. This is a heuristic.
enum DockLocator {
    struct Preferences {
        var edge: DockEdge = .bottom
        var autohide = false
        var tileSize: CGFloat = 48
        var tileCount = 12
        var separators = 1
    }

    static func readPreferences() -> Preferences {
        var p = Preferences()
        guard let d = UserDefaults(suiteName: "com.apple.dock") else { return p }
        if let o = d.string(forKey: "orientation"), let edge = DockEdge(rawValue: o) { p.edge = edge }
        p.autohide = d.bool(forKey: "autohide")
        let size = d.double(forKey: "tilesize")
        if size > 0 { p.tileSize = CGFloat(size) }
        let apps = d.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        let others = d.array(forKey: "persistent-others")?.count ?? 0
        let showRecents = d.object(forKey: "show-recents") == nil ? true : d.bool(forKey: "show-recents")
        let recents = showRecents ? min(d.array(forKey: "recent-apps")?.count ?? 0, 3) : 0
        let pinned = Set(apps.compactMap { tile in
            ((tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String)
        })
        let runningExtra = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !pinned.contains($0.bundleIdentifier ?? "")
                && $0.bundleIdentifier != "com.apple.finder"
        }.count
        // Finder + pinned apps + running unpinned apps + recents + folders + Trash.
        p.tileCount = 2 + apps.count + runningExtra + recents + others
        p.separators = 1 + (runningExtra + recents > 0 ? 1 : 0)
        return p
    }

    /// Dock frame in screen-local coordinates, or nil if the Dock is not on this screen.
    static func dock(on screen: NSScreen, isPrimary: Bool, prefs: Preferences) -> DockFrame? {
        let f = screen.frame
        let v = screen.visibleFrame
        let bottom = v.minY - f.minY
        let left = v.minX - f.minX
        let right = f.maxX - v.maxX
        let thickness: CGFloat
        let edge: DockEdge
        if bottom > 4 { thickness = bottom; edge = .bottom }
        else if left > 4 { thickness = left; edge = .left }
        else if right > 4 { thickness = right; edge = .right }
        else if prefs.autohide && isPrimary {
            // Hidden Dock: remember where it would appear (used for the flower strip).
            thickness = prefs.tileSize + 16
            edge = prefs.edge
        } else {
            return nil
        }
        let shown = !(prefs.autohide && bottom <= 4 && left <= 4 && right <= 4)
        let pitch = prefs.tileSize + 4
        let along = edge == .bottom ? f.width : f.height
        let length = min(along - 8, CGFloat(prefs.tileCount) * pitch + CGFloat(prefs.separators) * 14 + 20)
        let rect: Rect
        switch edge {
        case .bottom:
            rect = Rect(x: Float((f.width - length) / 2), y: 0, width: Float(length), height: Float(thickness))
        case .left:
            rect = Rect(x: 0, y: Float((f.height - length) / 2), width: Float(thickness), height: Float(length))
        case .right:
            rect = Rect(x: Float(f.width - thickness), y: Float((f.height - length) / 2),
                        width: Float(thickness), height: Float(length))
        }
        return DockFrame(rect: rect, edge: edge, isShown: shown)
    }

    /// Where flowers grow: on top of a visible bottom Dock, otherwise along the screen bottom
    /// below the (hidden or side) Dock's usual center.
    static func gardenBase(for dock: DockFrame?, screenWidth: Float) -> GardenBase? {
        guard let dock else { return nil }
        if dock.edge == .bottom {
            return GardenBase(minX: dock.rect.minX + 6, maxX: dock.rect.maxX - 6, y: dock.isShown ? dock.rect.maxY : 0)
        }
        let span = min(screenWidth * 0.5, 700)
        return GardenBase(minX: (screenWidth - span) / 2, maxX: (screenWidth + span) / 2, y: 0)
    }
}

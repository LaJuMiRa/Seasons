/// A window in screen-local coordinates (origin bottom-left, y up).
public struct WindowFrame: Equatable, Sendable {
    public var id: UInt32
    public var rect: Rect

    public init(id: UInt32, rect: Rect) {
        self.id = id
        self.rect = rect
    }
}

public enum DockEdge: String, Sendable {
    case bottom, left, right
}

/// Dock geometry on one screen, in screen-local coordinates.
public struct DockFrame: Equatable, Sendable {
    public var rect: Rect
    public var edge: DockEdge
    /// False when the Dock auto-hides and is currently not taking space.
    public var isShown: Bool

    public init(rect: Rect, edge: DockEdge, isShown: Bool) {
        self.rect = rect
        self.edge = edge
        self.isShown = isShown
    }
}

/// Input for computing all ledges of one screen.
public struct ScreenGeometry: Equatable, Sendable {
    public var width: Float
    public var height: Float
    /// Height of the menu bar strip at the top (no room for piles there).
    public var topInset: Float
    public var dock: DockFrame?
    /// Front-to-back order, already filtered to normal application windows.
    public var windows: [WindowFrame]

    public init(width: Float, height: Float, topInset: Float, dock: DockFrame?, windows: [WindowFrame]) {
        self.width = width
        self.height = height
        self.topInset = topInset
        self.dock = dock
        self.windows = windows
    }
}

/// Converts screen geometry into ledges: the screen bottom, the Dock top and the visible
/// parts of window top edges. Pure function, no platform dependencies.
public enum LedgeLayout {
    public static let floorID: UInt64 = 1
    public static let dockID: UInt64 = 2
    static let windowIDBase: UInt64 = 1 << 32

    /// Minimum visible length for a window edge to become a ledge, in points.
    static let minimumSpan: Float = 24
    /// Free space needed above a window edge, in points.
    static let headroom: Float = 8

    public static func windowLedgeID(_ windowID: UInt32) -> UInt64 { windowIDBase | UInt64(windowID) }

    public static func compute(_ g: ScreenGeometry, includeWindowsAndDock: Bool) -> [LedgeSpec] {
        var specs: [LedgeSpec] = []
        let bottomDock = g.dock.flatMap { $0.edge == .bottom && $0.isShown ? $0.rect : nil }

        // Floor (screen bottom). The part under a visible bottom Dock is hidden.
        var floorSpans = [Float(0)...g.width]
        if let dock = bottomDock {
            floorSpans = subtract(dock.minX...dock.maxX, from: floorSpans)
        }
        specs.append(LedgeSpec(id: floorID, kind: .floor, minX: 0, maxX: g.width, y: 0, visibleSpans: floorSpans))

        guard includeWindowsAndDock else { return specs }

        if let dock = bottomDock, dock.width > minimumSpan {
            specs.append(LedgeSpec(id: dockID, kind: .dock, minX: dock.minX, maxX: dock.maxX, y: dock.maxY,
                                   visibleSpans: [dock.minX...dock.maxX]))
        }

        // Things that sit above all normal windows.
        var fixedOccluders: [Rect] = [Rect(x: 0, y: g.height - g.topInset, width: g.width, height: g.topInset)]
        if let dock = g.dock, dock.isShown { fixedOccluders.append(dock.rect) }

        let ceiling = g.height - g.topInset - headroom
        for (index, window) in g.windows.enumerated() {
            let top = window.rect.maxY
            guard top > 1, top < ceiling else { continue }
            let minX = max(0, window.rect.minX)
            let maxX = min(g.width, window.rect.maxX)
            guard maxX - minX >= minimumSpan else { continue }

            var spans = [minX...maxX]
            let occluders = fixedOccluders + g.windows[..<index].map(\.rect)
            for o in occluders where o.minY <= top + 3 && o.maxY >= top - 1 {
                spans = subtract(o.minX...o.maxX, from: spans)
                if spans.isEmpty { break }
            }
            spans = spans.filter { $0.upperBound - $0.lowerBound >= minimumSpan }
            guard !spans.isEmpty else { continue }
            specs.append(LedgeSpec(id: windowLedgeID(window.id), kind: .window, minX: minX, maxX: maxX,
                                   y: top, visibleSpans: spans))
        }
        return specs
    }

    /// Removes `cut` from every range in `spans`.
    static func subtract(_ cut: ClosedRange<Float>, from spans: [ClosedRange<Float>]) -> [ClosedRange<Float>] {
        var out: [ClosedRange<Float>] = []
        for s in spans {
            if cut.upperBound <= s.lowerBound || cut.lowerBound >= s.upperBound {
                out.append(s)
                continue
            }
            if cut.lowerBound > s.lowerBound { out.append(s.lowerBound...cut.lowerBound) }
            if cut.upperBound < s.upperBound { out.append(cut.upperBound...s.upperBound) }
        }
        return out
    }
}

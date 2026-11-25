import Foundation

/// A window in front that hangs into the space above a ledge: the pile is hidden behind it from
/// `height` points above the edge, within `span`.
public struct Ceiling: Equatable, Sendable {
    public var span: ClosedRange<Float>
    public var height: Float

    public init(span: ClosedRange<Float>, height: Float) {
        self.span = span
        self.height = height
    }
}

/// Description of a horizontal surface that can carry a pile, produced by `LedgeLayout`.
public struct LedgeSpec: Equatable, Sendable {
    public var id: UInt64
    public var kind: LedgeKind
    public var minX: Float
    public var maxX: Float
    /// Height of the surface in screen-local points (y up).
    public var y: Float
    /// Absolute x ranges where the surface is visible (not covered by a window in front).
    public var visibleSpans: [ClosedRange<Float>]
    /// Radius of the rounded top corners at the left and right end (0 = square end).
    public var leftRadius: Float
    public var rightRadius: Float
    /// Windows in front that cover the upper part of a pile (see `Ceiling`).
    public var ceilings: [Ceiling]

    public init(id: UInt64, kind: LedgeKind, minX: Float, maxX: Float, y: Float,
                visibleSpans: [ClosedRange<Float>], leftRadius: Float = 0, rightRadius: Float = 0,
                ceilings: [Ceiling] = []) {
        self.id = id
        self.kind = kind
        self.minX = minX
        self.maxX = maxX
        self.y = y
        self.visibleSpans = visibleSpans
        self.leftRadius = leftRadius
        self.rightRadius = rightRadius
        self.ceilings = ceilings
    }
}

/// Mass that left a ledge and should become falling particles.
public struct Spill: Sendable {
    public var x: Float
    public var y: Float
    /// Area in square points.
    public var mass: Float
}

/// A 1D height field along a horizontal edge (window top, Dock top, screen bottom).
///
/// Heights are in points above `y`. Mass is measured as area (height * cell width).
/// The struct is mutated in place by the simulation for performance; it never shares storage.
public struct Ledge: Sendable {
    public let id: UInt64
    public let kind: LedgeKind
    public let cellWidth: Float
    public private(set) var minX: Float
    public private(set) var y: Float
    public private(set) var heights: [Float]
    public private(set) var visible: [Bool]
    /// How far the real edge lies below `y` in each cell. Zero on a straight edge; towards a rounded
    /// corner it follows the arc, so piles rest on the curve instead of hanging in the air.
    public private(set) var drop: [Float]
    public private(set) var leftRadius: Float
    public private(set) var rightRadius: Float
    /// Highest drawn height of the pile per cell (`.infinity` when nothing hangs over it).
    public private(set) var ceiling: [Float]
    /// Mass waiting at the left/right end until it is enough to drop a particle.
    var pendingSpillLeft: Float = 0
    var pendingSpillRight: Float = 0

    public init(spec: LedgeSpec, cellWidth: Float = EffectCatalog.cellWidth) {
        id = spec.id
        kind = spec.kind
        self.cellWidth = cellWidth
        minX = spec.minX
        y = spec.y
        let count = max(1, Int(((spec.maxX - spec.minX) / cellWidth).rounded()))
        heights = Array(repeating: 0, count: count)
        visible = Array(repeating: true, count: count)
        leftRadius = spec.leftRadius
        rightRadius = spec.rightRadius
        drop = Self.cornerDrops(count: count, cellWidth: cellWidth, left: spec.leftRadius, right: spec.rightRadius)
        ceiling = Array(repeating: .infinity, count: count)
        applyVisibility(spec.visibleSpans)
        applyCeilings(spec.ceilings)
    }

    public var count: Int { heights.count }
    public var maxX: Float { minX + Float(heights.count) * cellWidth }
    public var width: Float { maxX - minX }
    public var totalMass: Float { heights.reduce(0, +) * cellWidth }

    @inline(__always)
    public func cellIndex(forX x: Float) -> Int? {
        let i = Int((x - minX) / cellWidth)
        return (x >= minX && i < heights.count) ? i : nil
    }

    @inline(__always)
    public func cellCenterX(_ i: Int) -> Float { minX + (Float(i) + 0.5) * cellWidth }

    /// Height of the edge a pile rests on in cell `i` (lower than `y` on a rounded corner).
    @inline(__always)
    public func restY(_ i: Int) -> Float { y - drop[i] }

    @inline(__always)
    public func surfaceY(_ i: Int) -> Float { y - drop[i] + heights[i] }

    /// Deepest point of the corners; the pile can reach this far below `y`.
    public var maxDrop: Float { max(drop.first ?? 0, drop.last ?? 0) }

    /// Arc profile of the two corners for `count` cells of width `cellWidth`.
    static func cornerDrops(count: Int, cellWidth: Float, left: Float, right: Float) -> [Float] {
        guard left > 0 || right > 0 else { return Array(repeating: 0, count: count) }
        let width = Float(count) * cellWidth
        func arc(_ distance: Float, _ radius: Float) -> Float {
            guard radius > 0, distance < radius else { return 0 }
            let r = min(radius, width / 2)
            let d = min(distance, r)
            return r - max(0, r * r - (r - d) * (r - d)).squareRoot()
        }
        return (0..<count).map { i in
            let x = (Float(i) + 0.5) * cellWidth
            return max(arc(x, left), arc(width - x, right))
        }
    }

    /// Updates the corner radii (a window can slide partly off the screen).
    mutating func setCorners(left: Float, right: Float) {
        guard left != leftRadius || right != rightRadius else { return }
        leftRadius = left
        rightRadius = right
        drop = Self.cornerDrops(count: heights.count, cellWidth: cellWidth, left: left, right: right)
    }

    // MARK: - Geometry updates

    mutating func applyVisibility(_ spans: [ClosedRange<Float>]) {
        for i in visible.indices {
            let cx = cellCenterX(i)
            visible[i] = spans.contains { $0.contains(cx) }
        }
    }

    mutating func applyCeilings(_ ceilings: [Ceiling]) {
        for i in ceiling.indices {
            let cx = cellCenterX(i)
            ceiling[i] = ceilings.reduce(Float.infinity) { $1.span.contains(cx) ? min($0, $1.height) : $0 }
        }
    }

    /// Moves the ledge. Returns nothing; pile mass moves with the surface.
    mutating func move(toMinX newMinX: Float, y newY: Float) {
        minX = newMinX
        y = newY
    }

    /// Changes the width, keeping the pile anchored at the left edge.
    /// Mass beyond the new right end is returned as spill.
    mutating func resize(toWidth newWidth: Float) -> [Spill] {
        let newCount = max(1, Int((newWidth / cellWidth).rounded()))
        guard newCount != heights.count else { return [] }
        var spills: [Spill] = []
        if newCount < heights.count {
            for i in newCount..<heights.count where heights[i] > 0 {
                spills.append(Spill(x: cellCenterX(i), y: surfaceY(i), mass: heights[i] * cellWidth))
            }
            heights.removeLast(heights.count - newCount)
            visible.removeLast(visible.count - newCount)
            ceiling.removeLast(ceiling.count - newCount)
        } else {
            heights.append(contentsOf: repeatElement(0, count: newCount - heights.count))
            visible.append(contentsOf: repeatElement(true, count: newCount - visible.count))
            ceiling.append(contentsOf: repeatElement(.infinity, count: newCount - ceiling.count))
        }
        drop = Self.cornerDrops(count: newCount, cellWidth: cellWidth, left: leftRadius, right: rightRadius)
        return spills
    }

    /// Shifts the pile relative to the surface by `cells` (fractional allowed), as inertia
    /// does when the surface moves sideways. Mass pushed past either end is returned.
    mutating func shift(byCells cells: Float) -> [Spill] {
        guard abs(cells) > 0.01 else { return [] }
        let n = heights.count
        var shifted = Array(repeating: Float(0), count: n)
        var spills: [Spill] = []
        let whole = Int(cells.rounded(.down))
        let frac = cells - Float(whole)
        for i in 0..<n where heights[i] > 0 {
            let mass = heights[i]
            for (target, part) in [(i + whole, mass * (1 - frac)), (i + whole + 1, mass * frac)] where part > 0 {
                if target >= 0 && target < n {
                    shifted[target] += part
                } else {
                    let x = minX + (Float(target) + 0.5) * cellWidth
                    spills.append(Spill(x: x, y: restY(clamp(i, 0, n - 1)) + mass, mass: part * cellWidth))
                }
            }
        }
        heights = shifted
        return spills
    }

    // MARK: - Mass

    /// Per-cell fraction of the maximum height (0.78...1). A smooth, stable wave so a full
    /// pile has a natural, uneven top instead of a flat slab.
    @inline(__always)
    func capFactor(_ i: Int) -> Float {
        let phase = Float(id % 997)
        let x = Float(i)
        return 0.89 + 0.07 * sin(x * 0.19 + phase) + 0.04 * sin(x * 0.053 + phase * 1.7)
    }

    /// Adds `area` square points centered at `x`, spread with a triangular kernel of
    /// half-width `radius` over visible cells. Height is capped at `maxHeight` (shaped by `capFactor`).
    @discardableResult
    mutating func deposit(atX x: Float, area: Float, radius: Float, maxHeight: Float) -> Bool {
        let r = max(radius, cellWidth)
        let lo = max(0, Int((x - r - minX) / cellWidth))
        let hi = min(heights.count - 1, Int((x + r - minX) / cellWidth))
        guard lo <= hi else { return false }
        var weightSum: Float = 0
        for i in lo...hi where visible[i] {
            weightSum += max(0, 1 - abs(cellCenterX(i) - x) / r)
        }
        guard weightSum > 0 else { return false }
        let scale = area / (weightSum * cellWidth)
        for i in lo...hi where visible[i] {
            let w = max(0, 1 - abs(cellCenterX(i) - x) / r)
            heights[i] = min(maxHeight * capFactor(i), heights[i] + w * scale)
        }
        return true
    }

    /// Angle-of-repose relaxation: neighbors differing by more than `slope * cellWidth`
    /// exchange mass. The open ends of the ledge shed mass that accumulates as pending spill.
    mutating func relax(slope: Float, iterations: Int, rate: Float = 0.45) {
        let maxDiff = slope * cellWidth
        let n = heights.count
        guard n > 0 else { return }
        for _ in 0..<iterations {
            for i in 0..<(n - 1) where visible[i] && visible[i + 1] {
                // Slope of the real surface: on a rounded corner the edge itself falls away.
                let d = heights[i] - heights[i + 1] + drop[i + 1] - drop[i]
                let excess = abs(d) - maxDiff
                if excess > 0 {
                    let t = excess * 0.5 * rate
                    if d > 0 {
                        let moved = min(t, heights[i])
                        heights[i] -= moved
                        heights[i + 1] += moved
                    } else {
                        let moved = min(t, heights[i + 1])
                        heights[i] += moved
                        heights[i + 1] -= moved
                    }
                }
            }
            // Open ends: the neighbor outside the ledge has height 0 and swallows the excess.
            if visible[0], heights[0] > maxDiff {
                let t = (heights[0] - maxDiff) * 0.5 * rate
                heights[0] -= t
                pendingSpillLeft += t * cellWidth
            }
            if visible[n - 1], heights[n - 1] > maxDiff {
                let t = (heights[n - 1] - maxDiff) * 0.5 * rate
                heights[n - 1] -= t
                pendingSpillRight += t * cellWidth
            }
        }
    }

    /// Diffusion pass that rounds off small bumps (snow settles, water spreads).
    /// Flux form between neighbors: conserves mass and never produces negative heights.
    mutating func smooth(_ k: Float) {
        guard k > 0, heights.count > 1 else { return }
        let rate = min(k, 1) * 0.25
        for i in 0..<(heights.count - 1) where visible[i] && visible[i + 1] {
            let flow = (heights[i] - heights[i + 1]) * rate
            heights[i] -= flow
            heights[i + 1] += flow
        }
    }

    /// Returns pending end spills once they exceed `threshold` mass.
    mutating func takeEndSpills(threshold: Float) -> [Spill] {
        var out: [Spill] = []
        if pendingSpillLeft >= threshold {
            out.append(Spill(x: minX - 1, y: surfaceY(0), mass: pendingSpillLeft))
            pendingSpillLeft = 0
        }
        if pendingSpillRight >= threshold {
            out.append(Spill(x: maxX + 1, y: surfaceY(heights.count - 1), mass: pendingSpillRight))
            pendingSpillRight = 0
        }
        return out
    }

    /// Cells over which pushed-aside snow is spread next to the carved span.
    static let bermCells = 8

    /// Carves the pile with a circle (the cursor). Mass above the circle's lower boundary is
    /// removed. A fraction `sideFraction` is pushed aside and spread as a wedge over the cells
    /// next to the circle (steepest at the circle, fading outwards, never above `maxHeight`);
    /// the rest, and whatever does not fit on the wedge, is returned as spill to be ejected as
    /// particles.
    mutating func erode(center: Vec2, radius: Float, sideFraction: Float,
                        maxHeight: Float = .greatestFiniteMagnitude) -> [Spill] {
        let lo = max(0, Int((center.x - radius - minX) / cellWidth))
        let hi = min(heights.count - 1, Int((center.x + radius - minX) / cellWidth))
        guard lo <= hi, center.y - radius < y + (heights.max() ?? 0), center.y + radius > y - maxDrop else { return [] }
        var spills: [Spill] = []
        var pushedLeft: Float = 0
        var pushedRight: Float = 0
        for i in lo...hi where visible[i] && heights[i] > 0 {
            let dx = cellCenterX(i) - center.x
            let r2 = radius * radius - dx * dx
            guard r2 > 0 else { continue }
            let half = r2.squareRoot()
            let bottom = center.y - half
            let top = center.y + half
            let rest = restY(i)
            let surface = rest + heights[i]
            guard bottom < surface, top > rest else { continue }
            let newHeight = max(0, bottom - rest)
            let removed = heights[i] - newHeight
            guard removed > 0.01 else { continue }
            heights[i] = newHeight
            let aside = removed * sideFraction
            if dx < 0 { pushedLeft += aside } else { pushedRight += aside }
            spills.append(Spill(x: cellCenterX(i), y: surface, mass: (removed - aside) * cellWidth))
        }
        spills += spreadBerm(pushedLeft, from: lo - 1, step: -1, maxHeight: maxHeight)
        spills += spreadBerm(pushedRight, from: hi + 1, step: 1, maxHeight: maxHeight)
        return spills
    }

    /// Adds `amount` (in height units, summed over cells) as a wedge starting at cell `start` and
    /// running away in direction `step`. Returns what did not fit as spill.
    private mutating func spreadBerm(_ amount: Float, from start: Int, step: Int, maxHeight: Float) -> [Spill] {
        guard amount > 0 else { return [] }
        let cells = Self.bermCells
        let weightSum = Float(cells * (cells + 1) / 2)
        var leftover: Float = 0
        for j in 0..<cells {
            let share = amount * Float(cells - j) / weightSum
            let index = start + step * j
            guard index >= 0, index < heights.count, visible[index] else {
                leftover += share
                continue
            }
            let room = max(0, maxHeight * capFactor(index) - heights[index])
            let added = min(share, room)
            heights[index] += added
            leftover += share - added
        }
        guard leftover > 0 else { return [] }
        let edge = clamp(start, 0, heights.count - 1)
        return [Spill(x: cellCenterX(edge), y: surfaceY(edge) + 2, mass: leftover * cellWidth)]
    }

    /// Hard limit: cuts every cell down to `maxHeight` (excess is compacted away).
    /// Needed because pushing material sideways or shifting it can stack above the cap.
    mutating func enforceCap(_ maxHeight: Float) {
        for i in heights.indices where heights[i] > maxHeight {
            heights[i] = maxHeight
        }
    }

    mutating func decay(by amount: Float) {
        guard amount > 0 else { return }
        for i in heights.indices where heights[i] > 0 {
            heights[i] = max(0, heights[i] - amount)
        }
    }

    /// Removes up to `fraction` of every cell and returns it as spill (used when a window moves).
    mutating func shed(fraction: Float) -> [Spill] {
        guard fraction > 0 else { return [] }
        var spills: [Spill] = []
        for i in heights.indices where heights[i] > 0.05 && visible[i] {
            let part = heights[i] * min(fraction, 1)
            heights[i] -= part
            spills.append(Spill(x: cellCenterX(i), y: surfaceY(i) + part * 0.5, mass: part * cellWidth))
        }
        return spills
    }

    /// Removes everything and returns it as spill (window closed or minimized).
    mutating func takeAll() -> [Spill] {
        let spills = shed(fraction: 1)
        for i in heights.indices { heights[i] = 0 }
        return spills
    }

    mutating func clear() {
        for i in heights.indices { heights[i] = 0 }
        pendingSpillLeft = 0
        pendingSpillRight = 0
    }
}

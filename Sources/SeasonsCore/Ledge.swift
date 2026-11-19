import Foundation

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

    public init(id: UInt64, kind: LedgeKind, minX: Float, maxX: Float, y: Float,
                visibleSpans: [ClosedRange<Float>]) {
        self.id = id
        self.kind = kind
        self.minX = minX
        self.maxX = maxX
        self.y = y
        self.visibleSpans = visibleSpans
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
        applyVisibility(spec.visibleSpans)
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

    @inline(__always)
    public func surfaceY(_ i: Int) -> Float { y + heights[i] }

    // MARK: - Geometry updates

    mutating func applyVisibility(_ spans: [ClosedRange<Float>]) {
        for i in visible.indices {
            let cx = cellCenterX(i)
            visible[i] = spans.contains { $0.contains(cx) }
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
                spills.append(Spill(x: cellCenterX(i), y: y + heights[i], mass: heights[i] * cellWidth))
            }
            heights.removeLast(heights.count - newCount)
            visible.removeLast(visible.count - newCount)
        } else {
            heights.append(contentsOf: repeatElement(0, count: newCount - heights.count))
            visible.append(contentsOf: repeatElement(true, count: newCount - visible.count))
        }
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
                    spills.append(Spill(x: x, y: y + mass, mass: part * cellWidth))
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
                let d = heights[i] - heights[i + 1]
                let excess = abs(d) - maxDiff
                if excess > 0 {
                    let t = excess * 0.5 * rate
                    if d > 0 {
                        heights[i] -= t
                        heights[i + 1] += t
                    } else {
                        heights[i] += t
                        heights[i + 1] -= t
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
            out.append(Spill(x: minX - 1, y: y + heights[0], mass: pendingSpillLeft))
            pendingSpillLeft = 0
        }
        if pendingSpillRight >= threshold {
            out.append(Spill(x: maxX + 1, y: y + heights[heights.count - 1], mass: pendingSpillRight))
            pendingSpillRight = 0
        }
        return out
    }

    /// Carves the pile with a circle (the cursor). Mass above the circle's lower boundary
    /// is removed. A fraction `sideFraction` is pushed to the first cell outside the circle on
    /// the same side, the rest is returned as spill to be ejected as particles.
    mutating func erode(center: Vec2, radius: Float, sideFraction: Float) -> [Spill] {
        let lo = max(0, Int((center.x - radius - minX) / cellWidth))
        let hi = min(heights.count - 1, Int((center.x + radius - minX) / cellWidth))
        guard lo <= hi, center.y - radius < y + (heights.max() ?? 0), center.y + radius > y else { return [] }
        var spills: [Spill] = []
        let leftTarget = lo - 1
        let rightTarget = hi + 1
        for i in lo...hi where visible[i] && heights[i] > 0 {
            let dx = cellCenterX(i) - center.x
            let r2 = radius * radius - dx * dx
            guard r2 > 0 else { continue }
            let half = r2.squareRoot()
            let bottom = center.y - half
            let top = center.y + half
            let surface = y + heights[i]
            guard bottom < surface, top > y else { continue }
            let newHeight = max(0, bottom - y)
            let removed = heights[i] - newHeight
            guard removed > 0.01 else { continue }
            heights[i] = newHeight
            let target = dx < 0 ? leftTarget : rightTarget
            var ejected = removed
            if target >= 0, target < heights.count, visible[target] {
                heights[target] += removed * sideFraction
                ejected = removed * (1 - sideFraction)
            }
            spills.append(Spill(x: cellCenterX(i), y: surface, mass: ejected * cellWidth))
        }
        return spills
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
            spills.append(Spill(x: cellCenterX(i), y: y + heights[i] + part * 0.5, mass: part * cellWidth))
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

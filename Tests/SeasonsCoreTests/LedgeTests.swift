import Testing
@testable import SeasonsCore

private func makeLedge(width: Float = 300, y: Float = 100) -> Ledge {
    Ledge(spec: LedgeSpec(id: 7, kind: .window, minX: 0, maxX: width, y: y, visibleSpans: [0...width]))
}

@Suite("Height field")
struct LedgeTests {
    @Test("Deposit spreads over several cells and conserves area")
    func depositSpreads() {
        var l = makeLedge()
        l.deposit(atX: 150, area: 60, radius: 9, maxHeight: 100)
        let touched = l.heights.filter { $0 > 0 }.count
        #expect(touched >= 5)
        #expect(abs(l.totalMass - 60) < 0.01)
    }

    @Test("Height is capped at the maximum")
    func depositCaps() {
        var l = makeLedge()
        for _ in 0..<500 { l.deposit(atX: 150, area: 100, radius: 6, maxHeight: 20) }
        #expect((l.heights.max() ?? 0) <= 20)
    }

    @Test("Hidden cells receive nothing")
    func depositRespectsVisibility() {
        var l = Ledge(spec: LedgeSpec(id: 1, kind: .window, minX: 0, maxX: 300, y: 0, visibleSpans: [0...100]))
        l.deposit(atX: 200, area: 50, radius: 6, maxHeight: 50)
        #expect(l.totalMass == 0)
    }

    @Test("Relaxation flattens a spike to the angle of repose without losing mass in the middle")
    func relaxSpreads() {
        var l = makeLedge(width: 600)
        l.deposit(atX: 300, area: 900, radius: 3, maxHeight: 1000)
        let before = l.totalMass
        for _ in 0..<2000 { l.relax(slope: 0.5, iterations: 1) }
        let maxDiff = zip(l.heights, l.heights.dropFirst()).map { abs($0 - $1) }.max() ?? 0
        #expect(maxDiff <= 0.5 * l.cellWidth + 0.05)
        #expect(abs(l.totalMass - before) < 0.5) // far away from the open ends
        #expect(l.heights.filter { $0 > 0.1 }.count > 20) // no single stack
    }

    @Test("Open ends shed mass that becomes pending spill")
    func relaxSpillsAtEnds() {
        var l = makeLedge(width: 30)
        l.deposit(atX: 2, area: 200, radius: 3, maxHeight: 1000)
        for _ in 0..<200 { l.relax(slope: 0.5, iterations: 1) }
        let spills = l.takeEndSpills(threshold: 1)
        #expect(!spills.isEmpty)
        #expect(spills.allSatisfy { $0.mass >= 1 })
    }

    @Test("The cursor carves the pile, pushes part sideways and ejects the rest")
    func erodeCarves() {
        var l = makeLedge(width: 300, y: 0)
        for x in stride(from: Float(1), to: 300, by: 3) { l.deposit(atX: x, area: 60, radius: 3, maxHeight: 30) }
        let before = l.totalMass
        let center = Vec2(150, 5)
        let spills = l.erode(center: center, radius: 20, sideFraction: 0.4)
        let ejected = spills.reduce(0) { $0 + $1.mass }
        #expect(!spills.isEmpty)
        #expect(l.heights[l.cellIndex(forX: 150)!] < 0.01)
        // Mass is conserved: what is not ejected stays on the ledge.
        #expect(abs(l.totalMass + ejected - before) < 0.5)
    }

    @Test("Pushed-aside snow forms a smooth wedge on each side, not one tall column")
    func bermIsSpread() {
        var l = makeLedge(width: 300, y: 0)
        for x in stride(from: Float(1), to: 300, by: 3) { l.deposit(atX: x, area: 36, radius: 3, maxHeight: 30) }
        let original = l.heights[l.cellIndex(forX: 250)!]
        _ = l.erode(center: Vec2(150, 4), radius: 20, sideFraction: 0.4, maxHeight: 30)
        for side: Float in [-1, 1] {
            let first = l.cellIndex(forX: 150 + side * 24)!
            let berm = (0..<10).map { l.heights[first + Int(side) * $0] }
            #expect(berm.filter { $0 > original + 0.5 }.count >= 5) // spread over several cells
            #expect((berm.max() ?? 0) <= original + 10) // no spike
            #expect((berm.max() ?? 0) <= 30) // never above the cap
            #expect(zip(berm, berm.dropFirst()).allSatisfy { abs($0 - $1) <= 4 }) // gentle slope
        }
    }

    @Test("Material that does not fit on the berm is thrown up instead of being cut off")
    func bermOverflowSpills() {
        var l = makeLedge(width: 300, y: 0)
        for x in stride(from: Float(1), to: 300, by: 3) { l.deposit(atX: x, area: 90, radius: 3, maxHeight: 30) }
        let before = l.totalMass
        let spills = l.erode(center: Vec2(150, 4), radius: 20, sideFraction: 0.9, maxHeight: 30)
        let ejected = spills.reduce(0) { $0 + $1.mass }
        #expect((l.heights.max() ?? 0) <= 30)
        #expect(abs(l.totalMass + ejected - before) < 0.5) // nothing silently lost
    }

    @Test("Shifting moves mass and spills past the end")
    func shiftSpills() {
        var l = makeLedge(width: 30)
        l.deposit(atX: 28, area: 30, radius: 3, maxHeight: 100)
        let spills = l.shift(byCells: 5)
        #expect(!spills.isEmpty)
    }

    // MARK: - Rounded corners

    private func roundedLedge(left: Float, right: Float, width: Float = 300) -> Ledge {
        Ledge(spec: LedgeSpec(id: 3, kind: .window, minX: 0, maxX: width, y: 100, visibleSpans: [0...width],
                              leftRadius: left, rightRadius: right))
    }

    @Test("A rounded corner lowers the resting surface towards the end and is flat beyond the radius")
    func cornerProfile() {
        let l = roundedLedge(left: 12, right: 0)
        #expect(l.restY(0) < 100 - 5)
        #expect(l.restY(l.count - 1) == 100) // square right end
        #expect(l.restY(6) == 100) // cell centre 19.5 pt > radius
        for i in 0..<5 { #expect(l.restY(i) <= l.restY(i + 1)) }
        // An arc, not a bevel: halfway into the radius the edge has dropped only a little.
        let u = l.cellCenterX(3) - l.minX
        let expected = 100 - (12 - (144 - (12 - u) * (12 - u)).squareRoot())
        #expect(abs(l.restY(3) - expected) < 0.01)
    }

    @Test("Snow cannot stay on the steep part of a rounded corner and slides off the end")
    func cornerShedsSnow() {
        var l = roundedLedge(left: 14, right: 14)
        let maxDiff: Float = 0.55 * l.cellWidth
        for x in stride(from: Float(1), to: 300, by: 3) { l.deposit(atX: x, area: 30, radius: 3, maxHeight: 20) }
        for _ in 0..<600 { l.relax(slope: 0.55, iterations: 2) }
        #expect(l.heights[0] <= maxDiff + 0.01)
        #expect(l.heights[l.count - 1] <= maxDiff + 0.01)
        // Where snow lies on two neighbours the surface is never steeper than the angle of repose.
        for i in 0..<(l.count - 1) where l.heights[i] > 0.01 && l.heights[i + 1] > 0.01 {
            #expect(abs(l.surfaceY(i) - l.surfaceY(i + 1)) <= maxDiff + 0.05)
        }
        #expect(!l.takeEndSpills(threshold: 0.5).isEmpty)
    }

    @Test("A flat ledge relaxes exactly as before (no corner, no change)")
    func flatLedgeUnchanged() {
        var l = makeLedge(width: 600)
        l.deposit(atX: 300, area: 900, radius: 3, maxHeight: 1000)
        for _ in 0..<2000 { l.relax(slope: 0.5, iterations: 1) }
        #expect((0..<l.count).allSatisfy { l.restY($0) == 100 })
        #expect(abs(l.totalMass - 900) < 0.5)
    }

    @Test("The drawn pile is clipped where a window in front hangs into it")
    func pileMeshIsClipped() {
        var l = Ledge(spec: LedgeSpec(id: 5, kind: .window, minX: 0, maxX: 300, y: 100, visibleSpans: [0...300],
                                      ceilings: [Ceiling(span: 100...200, height: 6)]))
        for x in stride(from: Float(1), to: 300, by: 3) { l.deposit(atX: x, area: 54, radius: 3, maxHeight: 30) }
        #expect((l.heights.max() ?? 0) > 15) // the mass itself is untouched
        var batch = RenderBatch()
        PileMesh.append(ledges: [l], params: EffectCatalog.snow, into: &batch)
        let under = batch.pileVertices.filter { $0.x > 106 && $0.x < 194 }
        let outside = batch.pileVertices.filter { $0.x < 90 || $0.x > 210 }
        #expect(!under.isEmpty)
        #expect(under.allSatisfy { $0.y <= 106.001 })
        #expect((outside.map(\.y).max() ?? 0) > 112)
    }

    @Test("Shrinking a ledge spills the cut-off part")
    func resizeSpills() {
        var l = makeLedge(width: 300)
        l.deposit(atX: 280, area: 50, radius: 3, maxHeight: 100)
        let spills = l.resize(toWidth: 150)
        #expect(spills.reduce(0) { $0 + $1.mass } > 49)
        #expect(l.totalMass < 0.01)
    }
}

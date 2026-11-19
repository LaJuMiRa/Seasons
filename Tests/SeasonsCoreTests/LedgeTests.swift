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

    @Test("Shifting moves mass and spills past the end")
    func shiftSpills() {
        var l = makeLedge(width: 30)
        l.deposit(atX: 28, area: 30, radius: 3, maxHeight: 100)
        let spills = l.shift(byCells: 5)
        #expect(!spills.isEmpty)
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

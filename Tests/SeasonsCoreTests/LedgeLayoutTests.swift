import Testing
@testable import SeasonsCore

@Suite("Ledge layout (collision surfaces)")
struct LedgeLayoutTests {
    private func geometry(windows: [WindowFrame], dock: DockFrame? = nil) -> ScreenGeometry {
        ScreenGeometry(width: 1000, height: 800, topInset: 30, dock: dock, windows: windows)
    }

    @Test("Without windows only the floor exists")
    func floorOnly() {
        let specs = LedgeLayout.compute(geometry(windows: []))
        #expect(specs.count == 1)
        #expect(specs[0].kind == .floor)
        #expect(specs[0].visibleSpans == [0...1000])
    }

    @Test("A window in front hides part of the edge behind it")
    func occlusion() {
        let front = WindowFrame(id: 1, rect: Rect(x: 100, y: 200, width: 200, height: 400)) // top 600
        let back = WindowFrame(id: 2, rect: Rect(x: 0, y: 300, width: 600, height: 200)) // top 500
        let specs = LedgeLayout.compute(geometry(windows: [front, back]))
        let backSpec = specs.first { $0.id == LedgeLayout.windowLedgeID(2) }
        #expect(backSpec != nil)
        #expect(backSpec?.visibleSpans == [0...100, 300...600])
        let frontSpec = specs.first { $0.id == LedgeLayout.windowLedgeID(1) }
        #expect(frontSpec?.visibleSpans == [100...300])
    }

    @Test("Windows reaching the menu bar get no ledge (no room above)")
    func noRoomBelowMenuBar() {
        let full = WindowFrame(id: 3, rect: Rect(x: 0, y: 0, width: 1000, height: 770))
        let specs = LedgeLayout.compute(geometry(windows: [full]))
        #expect(specs.allSatisfy { $0.kind != .window })
    }

    @Test("A bottom Dock creates a ledge and hides the floor beneath it")
    func dockLedge() {
        let dock = DockFrame(rect: Rect(x: 300, y: 0, width: 400, height: 70), edge: .bottom, isShown: true)
        let specs = LedgeLayout.compute(geometry(windows: [], dock: dock))
        let dockSpec = specs.first { $0.kind == .dock }
        #expect(dockSpec?.y == 70)
        #expect(dockSpec?.minX == 300)
        let floor = specs.first { $0.kind == .floor }
        #expect(floor?.visibleSpans == [0...300, 700...1000])
    }

    @Test("Window edges behind the Dock are hidden")
    func dockOccludesWindows() {
        let dock = DockFrame(rect: Rect(x: 0, y: 0, width: 1000, height: 70), edge: .bottom, isShown: true)
        let low = WindowFrame(id: 4, rect: Rect(x: 100, y: -300, width: 300, height: 340)) // top 40
        let specs = LedgeLayout.compute(geometry(windows: [low], dock: dock))
        #expect(specs.filter { $0.kind == .window }.allSatisfy { $0.visibleSpans.isEmpty })
    }

    @Test("A window that is completely covered keeps its ledge, hidden, so its pile can come back")
    func coveredWindowKeepsHiddenLedge() {
        let covered = WindowFrame(id: 2, rect: Rect(x: 200, y: 300, width: 300, height: 200)) // top 500
        let cover = WindowFrame(id: 1, rect: Rect(x: 100, y: 250, width: 600, height: 400)) // in front
        let specs = LedgeLayout.compute(geometry(windows: [cover, covered]))
        let hidden = specs.first { $0.id == LedgeLayout.windowLedgeID(2) }
        #expect(hidden != nil)
        #expect(hidden?.visibleSpans.isEmpty == true)
        #expect(specs.first { $0.id == LedgeLayout.windowLedgeID(1) }?.visibleSpans.isEmpty == false)
    }

    @Test("A window hanging into the pile height clips the pile where it overlaps")
    func overhangingWindowClipsPile() {
        let below = WindowFrame(id: 2, rect: Rect(x: 0, y: 100, width: 600, height: 200)) // top 300
        let above = WindowFrame(id: 1, rect: Rect(x: 200, y: 312, width: 200, height: 200)) // bottom 312
        let specs = LedgeLayout.compute(geometry(windows: [above, below]))
        let spec = specs.first { $0.id == LedgeLayout.windowLedgeID(2) }
        #expect(spec?.visibleSpans == [0...600]) // the edge itself is still free
        #expect(spec?.ceilings == [Ceiling(span: 200...400, height: 12)])
    }

    @Test("Windows far above the edge do not clip anything")
    func farWindowDoesNotClip() {
        let below = WindowFrame(id: 2, rect: Rect(x: 0, y: 100, width: 600, height: 200)) // top 300
        let above = WindowFrame(id: 1, rect: Rect(x: 200, y: 500, width: 200, height: 100))
        let spec = LedgeLayout.compute(geometry(windows: [above, below]))
            .first { $0.id == LedgeLayout.windowLedgeID(2) }
        #expect(spec?.ceilings.isEmpty == true)
    }

    @Test("Turning accumulation off keeps only the floor")
    func accumulationOff() {
        let w = WindowFrame(id: 5, rect: Rect(x: 100, y: 100, width: 300, height: 300))
        let dock = DockFrame(rect: Rect(x: 300, y: 0, width: 400, height: 70), edge: .bottom, isShown: true)
        let specs = LedgeLayout.compute(geometry(windows: [w], dock: dock), includeWindows: false, includeDock: false)
        #expect(specs.map(\.kind) == [.floor])
    }

    @Test("Window ledges carry the rounded corners of the window")
    func windowCorners() {
        let w = WindowFrame(id: 1, rect: Rect(x: 100, y: 200, width: 300, height: 200))
        let spec = LedgeLayout.compute(geometry(windows: [w]))
            .first { $0.kind == .window }
        #expect(spec?.leftRadius == LedgeLayout.windowCornerRadius)
        #expect(spec?.rightRadius == LedgeLayout.windowCornerRadius)
    }

    @Test("A window that continues beyond the screen edge has no corner on that side")
    func clippedCorners() {
        let w = WindowFrame(id: 1, rect: Rect(x: -80, y: 200, width: 300, height: 200))
        let spec = LedgeLayout.compute(geometry(windows: [w]))
            .first { $0.kind == .window }
        #expect(spec?.leftRadius == 0)
        #expect(spec?.rightRadius == LedgeLayout.windowCornerRadius)
        let right = WindowFrame(id: 2, rect: Rect(x: 800, y: 200, width: 300, height: 200))
        let rightSpec = LedgeLayout.compute(geometry(windows: [right]))
            .first { $0.kind == .window }
        #expect(rightSpec?.leftRadius == LedgeLayout.windowCornerRadius)
        #expect(rightSpec?.rightRadius == 0)
    }

    @Test("The Dock is rounder than a window and its radius follows its height")
    func dockCorners() {
        let dock = DockFrame(rect: Rect(x: 300, y: 0, width: 400, height: 70), edge: .bottom, isShown: true)
        let spec = LedgeLayout.compute(geometry(windows: [], dock: dock))
            .first { $0.kind == .dock }
        #expect(spec?.leftRadius == spec?.rightRadius)
        #expect((spec?.leftRadius ?? 0) > LedgeLayout.windowCornerRadius)
        #expect((spec?.leftRadius ?? 0) <= 70 / 2)
    }

    @Test("The floor has square ends")
    func floorHasNoCorners() {
        let spec = LedgeLayout.compute(geometry(windows: []))[0]
        #expect(spec.leftRadius == 0 && spec.rightRadius == 0)
    }

    @Test("Range subtraction")
    func subtract() {
        #expect(LedgeLayout.subtract(2...4, from: [0...10]) == [0...2, 4...10])
        #expect(LedgeLayout.subtract(0...10, from: [2...4]) == [])
        #expect(LedgeLayout.subtract(20...30, from: [0...10]) == [0...10])
    }
}

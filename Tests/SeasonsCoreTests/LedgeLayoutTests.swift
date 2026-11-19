import Testing
@testable import SeasonsCore

@Suite("Ledge layout (collision surfaces)")
struct LedgeLayoutTests {
    private func geometry(windows: [WindowFrame], dock: DockFrame? = nil) -> ScreenGeometry {
        ScreenGeometry(width: 1000, height: 800, topInset: 30, dock: dock, windows: windows)
    }

    @Test("Without windows only the floor exists")
    func floorOnly() {
        let specs = LedgeLayout.compute(geometry(windows: []), includeWindowsAndDock: true)
        #expect(specs.count == 1)
        #expect(specs[0].kind == .floor)
        #expect(specs[0].visibleSpans == [0...1000])
    }

    @Test("A window in front hides part of the edge behind it")
    func occlusion() {
        let front = WindowFrame(id: 1, rect: Rect(x: 100, y: 200, width: 200, height: 400)) // top 600
        let back = WindowFrame(id: 2, rect: Rect(x: 0, y: 300, width: 600, height: 200)) // top 500
        let specs = LedgeLayout.compute(geometry(windows: [front, back]), includeWindowsAndDock: true)
        let backSpec = specs.first { $0.id == LedgeLayout.windowLedgeID(2) }
        #expect(backSpec != nil)
        #expect(backSpec?.visibleSpans == [0...100, 300...600])
        let frontSpec = specs.first { $0.id == LedgeLayout.windowLedgeID(1) }
        #expect(frontSpec?.visibleSpans == [100...300])
    }

    @Test("Windows reaching the menu bar get no ledge (no room above)")
    func noRoomBelowMenuBar() {
        let full = WindowFrame(id: 3, rect: Rect(x: 0, y: 0, width: 1000, height: 770))
        let specs = LedgeLayout.compute(geometry(windows: [full]), includeWindowsAndDock: true)
        #expect(specs.allSatisfy { $0.kind != .window })
    }

    @Test("A bottom Dock creates a ledge and hides the floor beneath it")
    func dockLedge() {
        let dock = DockFrame(rect: Rect(x: 300, y: 0, width: 400, height: 70), edge: .bottom, isShown: true)
        let specs = LedgeLayout.compute(geometry(windows: [], dock: dock), includeWindowsAndDock: true)
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
        let specs = LedgeLayout.compute(geometry(windows: [low], dock: dock), includeWindowsAndDock: true)
        #expect(specs.allSatisfy { $0.kind != .window })
    }

    @Test("Turning accumulation off keeps only the floor")
    func accumulationOff() {
        let w = WindowFrame(id: 5, rect: Rect(x: 100, y: 100, width: 300, height: 300))
        let dock = DockFrame(rect: Rect(x: 300, y: 0, width: 400, height: 70), edge: .bottom, isShown: true)
        let specs = LedgeLayout.compute(geometry(windows: [w], dock: dock), includeWindowsAndDock: false)
        #expect(specs.map(\.kind) == [.floor])
    }

    @Test("Range subtraction")
    func subtract() {
        #expect(LedgeLayout.subtract(2...4, from: [0...10]) == [0...2, 4...10])
        #expect(LedgeLayout.subtract(0...10, from: [2...4]) == [])
        #expect(LedgeLayout.subtract(20...30, from: [0...10]) == [0...10])
    }
}

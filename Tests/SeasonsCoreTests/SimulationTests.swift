import Testing
@testable import SeasonsCore

private let frame: Float = 1.0 / 60

private func run(_ world: SimulationWorld, seconds: Float, mouse: Vec2? = nil, intensity: Float = 1,
                 start: Double = 0) {
    let steps = Int(seconds / frame)
    for i in 0..<steps {
        world.step(dt: frame, time: start + Double(Float(i) * frame), input: StepInput(mouse: mouse, intensity: intensity))
    }
}

private func windowSpec(id: UInt32, x: Float, y: Float, width: Float = 400) -> LedgeSpec {
    LedgeSpec(id: LedgeLayout.windowLedgeID(id), kind: .window, minX: x, maxX: x + width, y: y,
              visibleSpans: [x...(x + width)])
}

private let floorSpec = LedgeSpec(id: LedgeLayout.floorID, kind: .floor, minX: 0, maxX: 800, y: 0,
                                  visibleSpans: [0...800])

@Suite("Simulation")
struct SimulationTests {
    @Test("Same seed and inputs give identical results")
    func determinism() {
        let a = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 42)
        let b = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 42)
        for w in [a, b] {
            w.updateLedges([floorSpec, windowSpec(id: 1, x: 100, y: 300)], time: 0, removal: .spill)
            run(w, seconds: 20, mouse: Vec2(400, 200))
        }
        #expect(a.particles.count == b.particles.count)
        #expect(zip(a.particles, b.particles).allSatisfy { $0.position == $1.position })
        #expect(a.ledges.map(\.heights) == b.ledges.map(\.heights))
    }

    @Test("Different seeds diverge")
    func seedsDiffer() {
        let a = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 1)
        let b = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 2)
        run(a, seconds: 3)
        run(b, seconds: 3)
        #expect(a.particles.map(\.position) != b.particles.map(\.position))
    }

    @Test("Snow lands on the floor and on window tops", arguments: EffectKind.allCases)
    func accumulates(effect: EffectKind) {
        let w = SimulationWorld(width: 800, height: 600, effect: effect, seed: 7)
        w.updateLedges([floorSpec, windowSpec(id: 1, x: 200, y: 300)], time: 0, removal: .spill)
        run(w, seconds: 40, intensity: 2)
        let floor = w.ledges.first { $0.kind == .floor }!
        let window = w.ledges.first { $0.kind == .window }!
        #expect(floor.totalMass > 0)
        #expect(window.totalMass > 0)
        // Never more than the configured maximum.
        let p = EffectCatalog.parameters(for: effect).pile
        #expect((window.heights.max() ?? 0) <= p.maxHeightWindow + 0.001)
    }

    @Test("With accumulation off, nothing stays on windows")
    func accumulationOff() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 7)
        w.accumulateOnWindowsAndDock = false
        w.updateLedges([floorSpec, windowSpec(id: 1, x: 200, y: 300)], time: 0, removal: .spill)
        run(w, seconds: 20, intensity: 2)
        #expect(w.ledges.first { $0.kind == .window }!.totalMass == 0)
    }

    @Test("The cursor pushes airborne particles away")
    func mousePushesParticles() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 3)
        run(w, seconds: 12, intensity: 3)
        let m = Vec2(400, 300)
        let r = EffectCatalog.mouseRadius
        let near = { w.particles.filter { ($0.position - m).length < r * 0.5 }.count }
        // Hold the cursor still for a while: the area around it must clear out.
        run(w, seconds: 1.5, mouse: m, intensity: 3, start: 12)
        #expect(near() <= 2)
    }

    @Test("Wiping through a pile removes mass and throws particles up")
    func wipePile() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 5)
        w.updateLedges([floorSpec, windowSpec(id: 1, x: 200, y: 300)], time: 0, removal: .spill)
        run(w, seconds: 60, intensity: 3)
        run(w, seconds: 4, intensity: 0, start: 60) // let the air clear
        let before = w.ledges.first { $0.kind == .window }!.totalMass
        #expect(before > 100)
        let airborneBefore = w.particles.count
        // Sweep the cursor along the window top.
        for i in 0..<40 {
            let x = 200 + Float(i) * 10
            w.step(dt: frame, time: 70 + Double(i) * Double(frame), input: StepInput(mouse: Vec2(x, 305), intensity: 0))
        }
        let after = w.ledges.first { $0.kind == .window }!.totalMass
        #expect(after < before * 0.8)
        #expect(w.particles.count > airborneBefore)
        #expect(w.particles.contains { $0.velocity.y > 0 }) // thrown upwards
    }

    @Test("Moving a window fast makes the pile slide and fall off")
    func windowMoveSheds() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 9)
        w.updateLedges([floorSpec, windowSpec(id: 1, x: 100, y: 300)], time: 0, removal: .spill)
        run(w, seconds: 40, intensity: 3)
        run(w, seconds: 4, intensity: 0, start: 40)
        let before = w.ledges.first { $0.kind == .window }!.totalMass
        let airborne = w.particles.count
        for i in 1...6 {
            w.updateLedges([floorSpec, windowSpec(id: 1, x: 100 + Float(i) * 40, y: 300)],
                           time: 44 + Double(i) / 30, removal: .spill)
        }
        let after = w.ledges.first { $0.kind == .window }!.totalMass
        #expect(after < before * 0.9)
        #expect(w.particles.count > airborne)
    }

    @Test("Closing a window drops its pile; Space switches keep it")
    func removalModes() {
        for mode in [LedgeRemoval.spill, .stash] {
            let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 11)
            w.updateLedges([floorSpec, windowSpec(id: 1, x: 100, y: 300)], time: 0, removal: .spill)
            run(w, seconds: 30, intensity: 3)
            run(w, seconds: 4, intensity: 0, start: 30)
            let mass = w.ledges.first { $0.kind == .window }!.totalMass
            let airborne = w.particles.count
            w.updateLedges([floorSpec], time: 35, removal: mode)
            if mode == .spill {
                #expect(w.particles.count > airborne)
            } else {
                #expect(w.particles.count == airborne)
                w.updateLedges([floorSpec, windowSpec(id: 1, x: 100, y: 300)], time: 36, removal: .spill)
                let restored = w.ledges.first { $0.kind == .window }!.totalMass
                #expect(abs(restored - mass) < mass * 0.05)
            }
        }
    }

    @Test("Clear removes everything, melt removes piles gradually")
    func clearAndMelt() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 13)
        w.updateLedges([floorSpec], time: 0, removal: .spill)
        run(w, seconds: 30, intensity: 3)
        w.startMelting()
        let before = w.ledges[0].totalMass
        run(w, seconds: 1, intensity: 0, start: 30)
        #expect(w.ledges[0].totalMass < before)
        #expect(w.ledges[0].totalMass > 0)
        run(w, seconds: 60, intensity: 0, start: 31)
        #expect(w.ledges[0].totalMass == 0)
        #expect(!w.isMelting)
        run(w, seconds: 5, intensity: 3, start: 100)
        w.clearAll()
        #expect(w.particles.isEmpty)
        #expect(w.ledges.allSatisfy { $0.totalMass == 0 })
    }

    @Test("Rain produces splash droplets on impact")
    func rainSplashes() {
        let w = SimulationWorld(width: 800, height: 600, effect: .rain, seed: 17)
        w.updateLedges([floorSpec], time: 0, removal: .spill)
        run(w, seconds: 3)
        #expect(w.particles.contains { $0.isSplash })
    }

    @Test("Splash droplets expire instead of floating forever")
    func splashesExpire() {
        let w = SimulationWorld(width: 800, height: 600, effect: .rain, seed: 29)
        w.updateLedges([floorSpec, windowSpec(id: 1, x: 100, y: 300)], time: 0, removal: .spill)
        run(w, seconds: 10)
        run(w, seconds: 3, intensity: 0, start: 10)
        // Without new rain only short-lived drips from the water films remain; nothing hovers.
        #expect(w.particles.allSatisfy { $0.isSplash ? $0.life <= 0.9 : $0.velocity.y < -50 })
        #expect(w.particles.filter { !$0.isSplash }.isEmpty)
    }

    @Test("A quiet world is quiescent; falling particles are not")
    func quiescence() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 19)
        run(w, seconds: 0.5, intensity: 0)
        #expect(w.isQuiescent)
        run(w, seconds: 0.5, intensity: 1, start: 1)
        #expect(!w.isQuiescent)
    }

    @Test("Render batch contains pile geometry and sprites")
    func renderBatch() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 23)
        w.updateLedges([floorSpec], time: 0, removal: .spill)
        run(w, seconds: 20, intensity: 2)
        var batch = RenderBatch()
        w.buildRenderBatch(&batch)
        #expect(!batch.pileVertices.isEmpty)
        #expect(batch.pileVertices.count % 3 == 0)
        #expect(batch.sprites.count >= w.particles.count)
        #expect(MemoryLayout<SpriteInstance>.stride == 48)
        #expect(MemoryLayout<PileVertex>.stride == 24)
    }
}

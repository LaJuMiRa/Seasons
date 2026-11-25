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
        w.accumulateOnWindows = false
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

    @Test("A very fast wipe clears the whole path and leaves no cliff behind", arguments: [30, 60])
    func fastWipeLeavesNoBar(fps: Int) {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 5)
        w.updateLedges([floorSpec], time: 0, removal: .spill)
        run(w, seconds: 60, intensity: 3)
        run(w, seconds: 4, intensity: 0, start: 60)
        let floor = { w.ledges[0] }
        let before = floor().heights
        // 2400 pt/s along the floor: 80 pt per frame at 30 fps, 40 pt at 60 fps.
        let dt = 1 / Float(fps)
        var t = 64.0
        var x: Float = 100
        while x < 700 {
            w.step(dt: dt, time: t, input: StepInput(mouse: Vec2(x, 6), intensity: 0))
            x += 2400 * dt
            t += Double(dt)
        }
        for _ in 0..<(fps / 2) { // half a second without the cursor
            w.step(dt: dt, time: t, input: StepInput(mouse: nil, intensity: 0))
            t += Double(dt)
        }
        let after = floor().heights
        let lo = floor().cellIndex(forX: 160)!, hi = floor().cellIndex(forX: 640)!
        let beforeMean = before[lo...hi].reduce(0, +) / Float(hi - lo + 1)
        let afterMean = after[lo...hi].reduce(0, +) / Float(hi - lo + 1)
        #expect(beforeMean > 15)
        #expect(afterMean < beforeMean * 0.25) // no uncleared strips between the cursor positions
        let steepest = zip(after, after.dropFirst()).map { abs($0 - $1) }.max() ?? 0
        #expect(steepest < 6) // no cliff or single-column bar
        #expect((after.max() ?? 0) <= EffectCatalog.snow.pile.maxHeightFloor)
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

    @Test("A window that gets covered keeps its pile hidden and spills nothing; it returns when uncovered")
    func coveredWindowKeepsPile() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 41)
        let visible = windowSpec(id: 1, x: 100, y: 300)
        w.updateLedges([floorSpec, visible], time: 0, removal: .spill)
        run(w, seconds: 40, intensity: 3)
        run(w, seconds: 5, intensity: 0, start: 40)
        let mass = w.ledges.first { $0.kind == .window }!.totalMass
        #expect(mass > 100)
        let airborne = w.particles.count

        var hidden = visible
        hidden.visibleSpans = []
        w.updateLedges([floorSpec, hidden], time: 45, removal: .spill)
        #expect(w.particles.count == airborne) // no flakes fly out over the window that covers it
        #expect(w.ledges.first { $0.kind == .window }!.totalMass == mass)

        run(w, seconds: 10, intensity: 3, start: 45) // new snow does not land on a covered edge
        #expect(w.ledges.first { $0.kind == .window }!.totalMass == mass)
        var batch = RenderBatch()
        w.buildRenderBatch(&batch)
        #expect(batch.pileVertices.allSatisfy { v in !(v.x > 110 && v.x < 490 && v.y > 300.5) })

        w.updateLedges([floorSpec, visible], time: 60, removal: .spill)
        #expect(w.ledges.first { $0.kind == .window }!.totalMass == mass) // pile is back
    }

    @Test("Closing a window that was covered does not throw snow out over the windows in front")
    func closingCoveredWindowSpillsNothing() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 43)
        let visible = windowSpec(id: 1, x: 100, y: 300)
        w.updateLedges([floorSpec, visible], time: 0, removal: .spill)
        run(w, seconds: 40, intensity: 3)
        run(w, seconds: 5, intensity: 0, start: 40)
        var hidden = visible
        hidden.visibleSpans = []
        w.updateLedges([floorSpec, hidden], time: 45, removal: .spill)
        let airborne = w.particles.count
        w.updateLedges([floorSpec], time: 46, removal: .spill)
        #expect(w.particles.count == airborne)
    }

    @Test("The floor never exceeds its maximum, even after sweeping back and forth", arguments: EffectKind.allCases)
    func floorCapHolds(effect: EffectKind) {
        let w = SimulationWorld(width: 800, height: 600, effect: effect, seed: 31)
        w.updateLedges([floorSpec], time: 0, removal: .spill)
        let cap = EffectCatalog.parameters(for: effect).pile.maxHeightFloor
        var t = 0.0
        // Ten minutes of heavy fall while the cursor keeps sweeping along the floor,
        // pushing material sideways into walls.
        for i in 0..<(600 * 30) {
            let phase = Float(i % 240) / 240
            let x = 40 + 720 * (phase < 0.5 ? phase * 2 : 2 - phase * 2)
            w.step(dt: 1.0 / 30, time: t, input: StepInput(mouse: Vec2(x, 6), intensity: 2.2))
            t += 1.0 / 30
        }
        #expect((w.ledges[0].heights.max() ?? 0) <= cap + 0.001)
    }

    @Test("Clear removes everything immediately")
    func clear() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 13)
        w.updateLedges([floorSpec], time: 0, removal: .spill)
        run(w, seconds: 10, intensity: 3)
        w.clearAll()
        #expect(w.particles.isEmpty)
        #expect(w.ledges.allSatisfy { $0.totalMass == 0 })
    }

    @Test("Melting is a switch: piles vanish while on and build up again when off")
    func meltSwitch() {
        let w = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 13)
        w.updateLedges([floorSpec], time: 0, removal: .spill)
        run(w, seconds: 30, intensity: 3)
        #expect(w.ledges[0].totalMass > 0)

        // Switched on while it keeps snowing: the pile melts away within seconds and stays
        // gone; single flakes still touch down and melt right after.
        let before = w.ledges[0].totalMass
        w.isMelting = true
        run(w, seconds: 15, intensity: 1, start: 30)
        #expect(w.isMelting) // never switches itself off
        #expect(w.ledges[0].totalMass < before * 0.03)
        #expect((w.ledges[0].heights.max() ?? 0) < 6)
        run(w, seconds: 25, intensity: 1, start: 45)
        #expect(w.ledges[0].totalMass < before * 0.03)

        // Nothing falls and nothing lies around: the world may idle even with melting on.
        run(w, seconds: 20, intensity: 0, start: 70)
        #expect(w.isQuiescent)

        // Switched off: snow stays again.
        w.isMelting = false
        run(w, seconds: 20, intensity: 3, start: 90)
        #expect(w.ledges[0].totalMass > 100)
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

@Suite("Multiple screens")
struct MultiScreenTests {
    @Test("Worlds with the same wind seed see the same wind")
    func sharedWind() {
        let a = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 1, windSeed: 7)
        let b = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 2, windSeed: 7)
        #expect(a.windSpeed(at: 123.4) == b.windSpeed(at: 123.4))
    }

    @Test("A particle that leaves towards a neighbour is handed over, not deleted")
    func handOff() {
        let world = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 3)
        world.hasNeighborRight = true
        world.adopt(Particle.testFlake(at: Vec2(795, 300), velocity: Vec2(200, -10)))
        run(world, seconds: 0.2, intensity: 0)
        let out = world.takeExited()
        #expect(out.count == 1)
        #expect((out.first?.position.x ?? 0) > 800)
        #expect(world.particles.isEmpty)
        #expect(world.takeExited().isEmpty)
    }

    @Test("Without a neighbour a particle stays on its screen")
    func noNeighbour() {
        let world = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 3)
        world.adopt(Particle.testFlake(at: Vec2(795, 300), velocity: Vec2(200, -10)))
        run(world, seconds: 0.2, intensity: 0)
        #expect(world.takeExited().isEmpty)
        #expect(world.particles.count == 1)
    }

    @Test("Spawning does not fill the strip next to a neighbour")
    func noSpawnBeyondConnectedEdge() {
        let world = SimulationWorld(width: 800, height: 600, effect: .snow, seed: 5)
        world.hasNeighborLeft = true
        world.hasNeighborRight = true
        run(world, seconds: 5, intensity: 2)
        #expect(world.particles.allSatisfy { $0.position.x >= -25 && $0.position.x <= 825 })
    }
}

extension Particle {
    static func testFlake(at position: Vec2, velocity: Vec2) -> Particle {
        Particle(position: position, velocity: velocity, size: 4, rotation: 0, spin: 0, fallSpeed: 40,
                 swayPhase: 0, swayFrequency: 0.5, shape: .flake, color: RGBA(1, 1, 1, 1), life: .infinity,
                 ignoreLedge: 0, ignoreTimer: 0, variant: 0)
    }
}

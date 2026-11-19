import Foundation

/// Per-frame input from the platform layer.
public struct StepInput: Sendable {
    /// Cursor position in screen-local points, nil when the cursor is on another screen.
    public var mouse: Vec2?
    /// Spawn-rate multiplier (0 = nothing new falls).
    public var intensity: Float

    public init(mouse: Vec2?, intensity: Float) {
        self.mouse = mouse
        self.intensity = intensity
    }
}

/// What happens to the pile on ledges that disappear.
public enum LedgeRemoval: Sendable {
    /// Window closed or minimized: the pile falls down.
    case spill
    /// Window left with a Space switch: keep the pile and restore it when the window returns.
    case stash
}

/// The simulation of one screen. Deterministic for a fixed seed and fixed inputs.
///
/// Mutable by design: particles and height fields are updated in place every frame because
/// copying thousands of particles 60 times per second would dominate the CPU budget.
public final class SimulationWorld {
    public private(set) var width: Float
    public private(set) var height: Float
    public private(set) var particles: [Particle] = []
    public private(set) var ledges: [Ledge] = []
    public private(set) var garden: FlowerGarden
    public private(set) var effect: EffectKind
    public private(set) var params: EffectParameters
    public var accumulateOnWindowsAndDock = true
    public var flowersEnabled = false {
        didSet { if !flowersEnabled { garden.setBase(nil) } }
    }
    /// True while "Melt" runs; switches itself off when all piles are gone.
    public private(set) var isMelting = false

    private var rng: SeededRandom
    private let wind: Wind
    private var spawnAccumulator: Float = 0
    private var lastMouse: Vec2?
    public private(set) var mouseVelocity: Vec2 = .zero
    private var stash: [UInt64: (width: Float, heights: [Float])] = [:]
    private var stashOrder: [UInt64] = []
    private var lastSpecTime: Double?
    private var lastSpawnIntensity: Float = 0
    private static let stashLimit = 64

    public init(width: Float, height: Float, effect: EffectKind, seed: UInt64) {
        self.width = width
        self.height = height
        self.effect = effect
        params = EffectCatalog.parameters(for: effect)
        rng = SeededRandom(seed: seed)
        wind = Wind(seed: seed)
        garden = FlowerGarden(seed: seed)
        ledges = [Ledge(spec: LedgeSpec(id: LedgeLayout.floorID, kind: .floor, minX: 0, maxX: width, y: 0,
                                        visibleSpans: [0...width]))]
    }

    // MARK: - Configuration

    public func setEffect(_ newEffect: EffectKind) {
        guard newEffect != effect else { return }
        effect = newEffect
        params = EffectCatalog.parameters(for: newEffect)
        // A pile of snow cannot turn into leaves: start fresh with the new material.
        particles.removeAll(keepingCapacity: true)
        for i in ledges.indices { ledges[i].clear() }
        stash.removeAll()
        stashOrder.removeAll()
    }

    public func resize(width newWidth: Float, height newHeight: Float) {
        guard newWidth != width || newHeight != height else { return }
        width = newWidth
        height = newHeight
        particles.removeAll { $0.position.x < -200 || $0.position.x > newWidth + 200 || $0.position.y > newHeight + 200 }
    }

    /// Removes every particle and pile immediately.
    public func clearAll() {
        particles.removeAll(keepingCapacity: true)
        for i in ledges.indices { ledges[i].clear() }
        stash.removeAll()
        stashOrder.removeAll()
        garden.resetGrowth()
        isMelting = false
    }

    /// Lets piles shrink slowly until they are gone.
    public func startMelting() { isMelting = true }

    public func setGardenBase(_ base: GardenBase?) {
        garden.setBase(flowersEnabled ? base : nil)
    }

    /// Replaces the set of ledges. Ledges are matched by id so piles survive small moves.
    /// `time` is used to estimate window speed for the slide-off behaviour.
    public func updateLedges(_ specs: [LedgeSpec], time: Double, removal: LedgeRemoval) {
        let dt = Float(max(1.0 / 120, min(0.5, time - (lastSpecTime ?? time - 1.0 / 30))))
        lastSpecTime = time
        var old: [UInt64: Ledge] = [:]
        for l in ledges { old[l.id] = l }
        var next: [Ledge] = []
        next.reserveCapacity(specs.count)
        var spills: [(Spill, Vec2, UInt64)] = []

        for spec in specs {
            guard var ledge = old.removeValue(forKey: spec.id) else {
                var fresh = Ledge(spec: spec)
                restoreFromStash(&fresh, width: spec.maxX - spec.minX)
                next.append(fresh)
                continue
            }
            let dx = spec.minX - ledge.minX
            let dy = spec.y - ledge.y
            if abs(dx) > 0.25 || abs(dy) > 0.25 {
                let v = Vec2(dx / dt, dy / dt)
                ledge.move(toMinX: spec.minX, y: spec.y)
                // Inertia: the pile lags behind horizontal motion and slides off the trailing end.
                let slide = ledge.shift(byCells: -dx * 0.35 / ledge.cellWidth)
                // Fast motion (or yanking the window down) throws snow off.
                let shedFraction = clamp(abs(v.x) * 0.00022 + max(0, -v.y) * 0.0009 + max(0, v.y) * 0.00008, 0, 0.6)
                let shed = ledge.shed(fraction: shedFraction)
                let fallVelocity = Vec2(v.x * 0.12, min(0, v.y) * 0.25)
                for s in slide + shed { spills.append((s, fallVelocity, ledge.id)) }
            }
            for s in ledge.resize(toWidth: spec.maxX - spec.minX) { spills.append((s, .zero, ledge.id)) }
            ledge.applyVisibility(spec.visibleSpans)
            next.append(ledge)
        }

        for (_, var gone) in old {
            switch removal {
            case .stash where gone.kind == .window && gone.totalMass > 1:
                remember(gone)
            default:
                for s in gone.takeAll() { spills.append((s, .zero, gone.id)) }
            }
        }
        ledges = next
        var budget = EffectCatalog.maxEjectPerFrame * 3
        for (s, v, id) in spills {
            emit(s, baseVelocity: v, scatter: 25, ignoreLedge: id, budget: &budget)
        }
    }

    private func remember(_ ledge: Ledge) {
        if stash[ledge.id] == nil { stashOrder.append(ledge.id) }
        stash[ledge.id] = (ledge.width, ledge.heights)
        while stashOrder.count > Self.stashLimit {
            stash.removeValue(forKey: stashOrder.removeFirst())
        }
    }

    private func restoreFromStash(_ ledge: inout Ledge, width: Float) {
        guard let saved = stash.removeValue(forKey: ledge.id) else { return }
        stashOrder.removeAll { $0 == ledge.id }
        guard abs(saved.width - width) < 2 else { return }
        let maxH = params.pile.maxHeight(for: ledge.kind)
        for (i, h) in saved.heights.enumerated() where i < ledge.count && h > 0 {
            ledge.deposit(atX: ledge.cellCenterX(i), area: h * ledge.cellWidth, radius: 0, maxHeight: maxH)
        }
    }

    // MARK: - Step

    /// True when nothing moves and nothing will move without new input.
    public var isQuiescent: Bool {
        particles.isEmpty && lastSpawnIntensity == 0 && !isMelting && !garden.isAnimating
            && (params.pile.decayPerSecond == 0 || ledges.allSatisfy { $0.totalMass == 0 })
    }

    /// True if the cursor is close to something it could interact with.
    public func isNearInteractive(_ p: Vec2) -> Bool {
        let r = EffectCatalog.mouseRadius
        if let b = garden.base, flowersEnabled, p.x > b.minX - r, p.x < b.maxX + r, p.y < b.y + 90 { return true }
        for l in ledges where p.x > l.minX - r && p.x < l.maxX + r {
            if p.y > l.y - r && p.y < l.y + params.pile.maxHeight(for: l.kind) + r && l.totalMass > 0 { return true }
        }
        return false
    }

    public func step(dt rawDt: Float, time: Double, input: StepInput) {
        let dt = clamp(rawDt, 0, 1.0 / 20)
        guard dt > 0 else { return }
        updateMouse(input.mouse, dt: dt)
        let windSpeed = wind.speed(at: time, strength: params.windStrength, gustiness: params.gustiness)
        lastSpawnIntensity = input.intensity
        spawn(dt: dt, intensity: input.intensity, windSpeed: windSpeed)
        advanceParticles(dt: dt, time: time, windSpeed: windSpeed, mouse: input.mouse)
        updatePiles(dt: dt, mouse: input.mouse)
        if flowersEnabled {
            var petals: [(Vec2, Vec2, RGBA)] = []
            garden.step(dt: dt, time: time, windSpeed: windSpeed, mouse: input.mouse,
                        mouseVelocity: mouseVelocity) { petals.append(($0, $1, $2)) }
            for (p, v, c) in petals { addPetal(at: p, velocity: v, color: c) }
        }
    }

    private func updateMouse(_ mouse: Vec2?, dt: Float) {
        if let m = mouse, let last = lastMouse {
            let instant = (m - last) * (1 / dt)
            mouseVelocity = mouseVelocity * 0.5 + instant * 0.5
        } else {
            mouseVelocity = .zero
        }
        lastMouse = mouse
    }

    private func spawn(dt: Float, intensity: Float, windSpeed: Float) {
        guard intensity > 0 else { return }
        spawnAccumulator += params.density * intensity * (width / 1000) * dt
        let room = params.maxParticles - particles.count
        var n = Int(spawnAccumulator)
        spawnAccumulator -= Float(n)
        n = min(n, max(0, room))
        guard n > 0 else { return }
        // Spawn upwind so the screen fills evenly even with strong wind.
        let travelTime = height / max(params.fallSpeed.lowerBound, 1)
        let drift = clamp(windSpeed * travelTime * 0.5, -width, width)
        let lo = min(0, -drift) - 20
        let hi = max(width, width - drift) + 20
        for _ in 0..<n {
            let size = rng.float(in: params.size)
            let fall = rng.float(in: params.fallSpeed)
            let x = rng.float(in: lo...hi)
            let y = height + size * params.aspect + rng.float(in: 0...(params.aspect > 4 ? 120 : 20))
            particles.append(Particle(
                position: Vec2(x, y),
                velocity: Vec2(windSpeed, -fall),
                size: size,
                rotation: rng.float(in: 0...6.28),
                spin: rng.float(in: params.spin) * rng.sign(),
                fallSpeed: fall,
                swayPhase: rng.float(in: 0...6.28),
                swayFrequency: rng.float(in: params.swayFrequency),
                shape: params.shape,
                color: params.colors[rng.int(below: params.colors.count)],
                life: -1,
                ignoreLedge: 0,
                ignoreTimer: 0,
                variant: Float(rng.int(below: 2))
            ))
        }
    }

    private func advanceParticles(dt: Float, time: Double, windSpeed: Float, mouse: Vec2?) {
        let relax = min(1, params.drag * dt)
        let r = EffectCatalog.mouseRadius
        let push = min(1, dt * 14)
        let t = Float(time.truncatingRemainder(dividingBy: 10_000))
        var splashes: [(Vec2, Vec2)] = []
        var i = 0
        while i < particles.count {
            var p = particles[i]
            let previous = p.position
            if p.isSplash {
                p.velocity.y -= 900 * dt
                p.life -= dt
            } else {
                let sway = params.swayAmplitude * sin(t * p.swayFrequency * 6.283 + p.swayPhase)
                let targetX = windSpeed + sway
                p.velocity.x += (targetX - p.velocity.x) * relax
                p.velocity.y += (-p.fallSpeed - p.velocity.y) * relax
                // Leaves and petals flutter: spin speeds up with sideways motion.
                p.rotation += (p.spin + sway * 0.01) * dt
                if p.ignoreTimer > 0 { p.ignoreTimer -= dt }
            }
            if let m = mouse {
                let d = p.position - m
                let dist = d.length
                if dist < r, dist > 0.01 {
                    let falloff = 1 - dist / r
                    let n = d * (1 / dist)
                    let kick = n * (EffectCatalog.mouseRepulsion * 2.2) + mouseVelocity * EffectCatalog.mouseCoupling
                    p.velocity += (kick - p.velocity * 0.2) * (falloff * push)
                    p.spin += (mouseVelocity.x * 0.004 * falloff)
                }
            }
            p.position += p.velocity * dt

            var dead = p.isSplash && p.life <= 0
            if !dead, !p.isSplash, p.velocity.y < 0, let hit = landingLedge(from: previous, to: p.position, particle: p) {
                let ledge = ledges[hit]
                let maxH = params.pile.maxHeight(for: ledge.kind)
                let area = p.area * params.pile.depositFactor
                ledges[hit].deposit(atX: p.position.x, area: area, radius: p.size * 0.9, maxHeight: maxH)
                if params.splashCount > 0, let c = ledge.cellIndex(forX: p.position.x) {
                    splashes.append((Vec2(p.position.x, ledge.surfaceY(c)), p.velocity))
                }
                dead = true
            }
            if p.position.y < -60 || p.position.x < -260 || p.position.x > width + 260 { dead = true }

            if dead {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
            } else {
                particles[i] = p
                i += 1
            }
        }
        for (pos, v) in splashes { addSplash(at: pos, impact: v) }
    }

    /// Finds the highest visible ledge surface crossed between two positions.
    private func landingLedge(from a: Vec2, to b: Vec2, particle p: Particle) -> Int? {
        var best: Int?
        var bestY = -Float.greatestFiniteMagnitude
        for li in ledges.indices {
            let l = ledges[li]
            if !accumulateOnWindowsAndDock && l.kind != .floor { continue }
            if p.ignoreTimer > 0 && l.id == p.ignoreLedge { continue }
            guard b.x >= l.minX, b.x < l.maxX, let c = l.cellIndex(forX: b.x), l.visible[c] else { continue }
            let surface = l.surfaceY(c)
            // Allow a little tolerance so fast rain does not tunnel through thin films.
            if a.y >= surface - 0.5 && b.y < surface && surface > bestY {
                bestY = surface
                best = li
            }
        }
        return best
    }

    private func updatePiles(dt: Float, mouse: Vec2?) {
        let pile = params.pile
        let decay = pile.decayPerSecond * dt + (isMelting ? pile.meltPerSecond * dt : 0)
        let particleMass = averageParticleArea * pile.depositFactor
        var budget = EffectCatalog.maxEjectPerFrame
        var anyMass = false
        for li in ledges.indices {
            if ledges[li].totalMass == 0 && ledges[li].pendingSpillLeft == 0 && ledges[li].pendingSpillRight == 0 {
                continue
            }
            ledges[li].relax(slope: pile.reposeSlope, iterations: 2)
            if decay > 0 { ledges[li].decay(by: decay) }
            let id = ledges[li].id
            if ledges[li].kind != .floor {
                for s in ledges[li].takeEndSpills(threshold: particleMass) {
                    emit(s, baseVelocity: Vec2(0, -20), scatter: 8, ignoreLedge: id, budget: &budget)
                }
            } else {
                _ = ledges[li].takeEndSpills(threshold: 0) // Mass leaving the screen is gone.
            }
            if let m = mouse {
                let spills = ledges[li].erode(center: m, radius: EffectCatalog.mouseRadius * 0.6, sideFraction: 0.4)
                for s in spills {
                    let outward = Vec2(s.x - m.x, 0)
                    let dir: Float = outward.x >= 0 ? 1 : -1
                    let v = mouseVelocity * 0.6 + Vec2(dir * rng.float(in: 40...160), rng.float(in: 80...220))
                    emit(s, baseVelocity: v, scatter: 50, ignoreLedge: id, budget: &budget)
                }
            }
            if ledges[li].totalMass > 0 { anyMass = true }
        }
        if isMelting && !anyMass { isMelting = false }
    }

    private var averageParticleArea: Float {
        let s = (params.size.lowerBound + params.size.upperBound) * 0.5
        return s * s * 0.8
    }

    /// Converts spilled mass into airborne particles of the current effect.
    private func emit(_ s: Spill, baseVelocity: Vec2, scatter: Float, ignoreLedge: UInt64, budget: inout Int) {
        let particleMass = averageParticleArea * params.pile.depositFactor
        guard particleMass > 0, budget > 0 else { return }
        var count = s.mass / particleMass
        // Probabilistic rounding keeps mass roughly conserved without fractional particles.
        let whole = Int(count)
        count -= Float(whole)
        let n = min(whole + (rng.unit() < count ? 1 : 0), budget)
        guard n > 0 else { return }
        budget -= n
        let isRain = params.shape == .streak
        for _ in 0..<n {
            let size = rng.float(in: params.size)
            let v = baseVelocity + Vec2(rng.float(in: -scatter...scatter), rng.float(in: -scatter * 0.5...scatter * 0.5))
            if isRain {
                particles.append(makeDroplet(at: Vec2(s.x, s.y), velocity: v, life: rng.float(in: 0.5...0.9)))
            } else {
                particles.append(Particle(
                    position: Vec2(s.x + rng.float(in: -2...2), s.y + rng.float(in: 0...3)),
                    velocity: v,
                    size: size,
                    rotation: rng.float(in: 0...6.28),
                    spin: rng.float(in: params.spin) * rng.sign(),
                    fallSpeed: rng.float(in: params.fallSpeed),
                    swayPhase: rng.float(in: 0...6.28),
                    swayFrequency: rng.float(in: params.swayFrequency),
                    shape: params.shape,
                    color: params.colors[rng.int(below: params.colors.count)],
                    life: -1,
                    ignoreLedge: ignoreLedge,
                    ignoreTimer: 0.25,
                    variant: Float(rng.int(below: 2))
                ))
            }
        }
    }

    private func makeDroplet(at p: Vec2, velocity: Vec2, life: Float) -> Particle {
        Particle(position: p, velocity: velocity, size: rng.float(in: 1.6...3.2), rotation: 0, spin: 0,
                 fallSpeed: 0, swayPhase: 0, swayFrequency: 0, shape: .splash,
                 color: RGBA(0.82, 0.9, 1, 0.75), life: life, ignoreLedge: 0, ignoreTimer: 0, variant: 0)
    }

    private func addSplash(at p: Vec2, impact: Vec2) {
        guard particles.count < params.maxParticles + 400 else { return }
        for _ in 0..<params.splashCount where rng.unit() < 0.7 {
            let v = Vec2(impact.x * 0.1 + rng.float(in: -110...110), rng.float(in: 70...200))
            particles.append(makeDroplet(at: p + Vec2(0, 1), velocity: v, life: rng.float(in: 0.18...0.38)))
        }
    }

    private func addPetal(at p: Vec2, velocity: Vec2, color: RGBA) {
        let b = EffectCatalog.blossoms
        particles.append(Particle(
            position: p, velocity: velocity, size: rng.float(in: 6...9), rotation: rng.float(in: 0...6.28),
            spin: rng.float(in: b.spin) * rng.sign(), fallSpeed: rng.float(in: b.fallSpeed),
            swayPhase: rng.float(in: 0...6.28), swayFrequency: rng.float(in: b.swayFrequency),
            shape: .petal, color: color, life: -1, ignoreLedge: 0, ignoreTimer: 0, variant: 0))
    }

    // MARK: - Rendering

    /// Fills `batch` with the pile mesh, pile decoration, flowers and airborne particles.
    public func buildRenderBatch(_ batch: inout RenderBatch) {
        batch.reset()
        PileMesh.append(ledges: ledges, params: params, into: &batch)
        if flowersEnabled { garden.appendSprites(into: &batch) }
        for p in particles {
            let w: Float
            let h: Float
            var rotation = p.rotation
            switch p.shape {
            case .streak:
                w = p.size
                h = p.size * params.aspect
                // Local +y (the fading tail) points against the direction of travel.
                rotation = atan2(p.velocity.x, -p.velocity.y)
            case .splash, .bead:
                w = p.size
                h = p.size
            default:
                w = p.size
                h = p.size * (p.shape == .flake ? 1 : params.aspect)
            }
            var color = p.color
            if p.isSplash { color.a *= min(1, p.life * 4) }
            batch.sprites.append(SpriteInstance(x: p.position.x, y: p.position.y, width: w, height: h,
                                                rotation: rotation, shape: p.shape, param: p.variant, color: color))
        }
    }
}

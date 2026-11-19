import Foundation

/// A single flower growing out of the Dock's top edge.
public struct Flower: Sendable {
    public var x: Float
    public var species: Int
    public var color: RGBA
    public var stemHeight: Float
    public var headSize: Float
    /// 0 = seed, 1 = fully grown.
    public var growth: Float
    public var growDuration: Float
    /// Bend angle in radians (positive = to the right) and its angular velocity.
    public var bend: Float
    public var bendVelocity: Float
    public var swayPhase: Float
    /// Seconds to wait before (re)growing.
    public var waitTimer: Float
}

/// Horizontal strip where flowers grow (normally the top edge of a bottom Dock).
public struct GardenBase: Equatable, Sendable {
    public var minX: Float
    public var maxX: Float
    public var y: Float

    public init(minX: Float, maxX: Float, y: Float) {
        self.minX = minX
        self.maxX = maxX
        self.y = y
    }
}

/// Flowers along the Dock: growth, wind sway, spring physics against the cursor, wiping and regrowth.
public struct FlowerGarden: Sendable {
    public private(set) var flowers: [Flower] = []
    public private(set) var base: GardenBase?
    private var rng: SeededRandom
    private let params = EffectCatalog.flowers
    private static let stemSegments = 5

    public init(seed: UInt64) {
        rng = SeededRandom(seed: seed ^ 0xF10E5)
    }

    /// True while something moves (growing, swaying back, waiting to regrow).
    public var isAnimating: Bool {
        flowers.contains { $0.growth < 1 || abs($0.bend) > 0.002 || abs($0.bendVelocity) > 0.002 }
    }

    public mutating func setBase(_ newBase: GardenBase?) {
        guard newBase != base else { return }
        defer { base = newBase }
        guard let newBase else {
            flowers.removeAll()
            return
        }
        if let old = base, abs(old.minX - newBase.minX) < 2, abs(old.maxX - newBase.maxX) < 2 {
            return // Only the height changed; flowers follow `base.y` when drawn.
        }
        layout(newBase)
    }

    private mutating func layout(_ b: GardenBase) {
        var kept = flowers.filter { $0.x > b.minX + 6 && $0.x < b.maxX - 6 }.sorted { $0.x < $1.x }
        var x = b.minX + rng.float(in: 6...14)
        var result: [Flower] = []
        while x < b.maxX - 6 {
            if let idx = kept.firstIndex(where: { abs($0.x - x) < params.spacing.lowerBound * 0.6 }) {
                result.append(kept.remove(at: idx))
            } else {
                result.append(makeFlower(at: x, initialWait: rng.float(in: 0...25)))
            }
            x += rng.float(in: params.spacing)
        }
        flowers = result
    }

    private mutating func makeFlower(at x: Float, initialWait: Float) -> Flower {
        let speciesIndex = rng.int(below: params.species.count)
        let species = params.species[speciesIndex]
        return Flower(
            x: x,
            species: speciesIndex,
            color: species.colors[rng.int(below: species.colors.count)],
            stemHeight: rng.float(in: species.stemHeight),
            headSize: rng.float(in: species.headSize),
            growth: 0,
            growDuration: rng.float(in: params.growDuration),
            bend: 0,
            bendVelocity: 0,
            swayPhase: rng.float(in: 0...6.28),
            waitTimer: initialWait
        )
    }

    /// Instantly regrows nothing: used by "Clear" so the Dock is empty and flowers start again.
    public mutating func resetGrowth() {
        for i in flowers.indices {
            flowers[i].growth = 0
            flowers[i].waitTimer = rng.float(in: 1...12)
        }
    }

    /// Advances the garden. `emit` receives petals of wiped flowers (position, velocity, color).
    public mutating func step(dt: Float, time: Double, windSpeed: Float, mouse: Vec2?, mouseVelocity: Vec2,
                              emit: (Vec2, Vec2, RGBA) -> Void) {
        guard let base else { return }
        let mouseSpeed = mouseVelocity.length
        let t = Float(time.truncatingRemainder(dividingBy: 10_000))
        for i in flowers.indices {
            var f = flowers[i]
            if f.waitTimer > 0 {
                f.waitTimer -= dt
            } else if f.growth < 1 {
                f.growth = min(1, f.growth + dt / f.growDuration)
            }

            let grown = smoothGrowth(f.growth)
            var torque = (windSpeed * params.windResponse) * (0.7 + 0.3 * sin(t * 1.7 + f.swayPhase)) * grown
            if let m = mouse, grown > 0.05 {
                let head = tip(of: f, baseY: base.y)
                let mid = Vec2((f.x + head.x) * 0.5, (base.y + head.y) * 0.5)
                let d = min((m - head).length, (m - mid).length)
                if d < params.mouseRadius {
                    let push = 1 - d / params.mouseRadius
                    let away: Float = head.x >= m.x ? 1 : -1
                    torque += away * push * 2.2 + mouseVelocity.x * 0.0016 * push
                    if mouseSpeed > params.wipeSpeed, (m - head).length < f.headSize + 12, f.growth > 0.35 {
                        wipe(&f, head: head, mouseVelocity: mouseVelocity, emit: emit)
                    }
                }
            }
            // Damped torsion spring toward the torque-defined rest angle.
            let accel = (torque - f.bend) * params.stiffness - f.bendVelocity * params.damping
            f.bendVelocity += accel * dt
            f.bend = clamp(f.bend + f.bendVelocity * dt, -1.35, 1.35)
            flowers[i] = f
        }
    }

    private mutating func wipe(_ f: inout Flower, head: Vec2, mouseVelocity: Vec2, emit: (Vec2, Vec2, RGBA) -> Void) {
        let petals = 4 + rng.int(below: 4)
        for _ in 0..<petals {
            let v = Vec2(mouseVelocity.x * rng.float(in: 0.15...0.45) + rng.float(in: -60...60),
                         abs(mouseVelocity.y) * 0.2 + rng.float(in: 60...220))
            emit(head + Vec2(rng.float(in: -4...4), rng.float(in: -4...4)), v, f.color)
        }
        f.growth = 0
        f.bend = 0
        f.bendVelocity = 0
        f.waitTimer = rng.float(in: params.regrowDelay)
        f.growDuration = rng.float(in: params.growDuration)
    }

    private func smoothGrowth(_ g: Float) -> Float { g * g * (3 - 2 * g) }

    /// Position of the stem tip.
    func tip(of f: Flower, baseY: Float) -> Vec2 {
        var p = Vec2(f.x, baseY)
        let len = f.stemHeight * smoothGrowth(f.growth) / Float(Self.stemSegments)
        for s in 1...Self.stemSegments {
            let a = f.bend * pow(Float(s) / Float(Self.stemSegments), 1.4)
            p += Vec2(sin(a) * len, cos(a) * len)
        }
        return p
    }

    public func appendSprites(into batch: inout RenderBatch) {
        guard let base else { return }
        for f in flowers where f.growth > 0.01 {
            let g = smoothGrowth(f.growth)
            let segLen = f.stemHeight * g / Float(Self.stemSegments)
            var p = Vec2(f.x, base.y - 1)
            for s in 1...Self.stemSegments {
                let a = f.bend * pow(Float(s) / Float(Self.stemSegments), 1.4)
                let next = p + Vec2(sin(a) * segLen, cos(a) * segLen)
                let mid = Vec2((p.x + next.x) * 0.5, (p.y + next.y) * 0.5)
                batch.sprites.append(SpriteInstance(
                    x: mid.x, y: mid.y, width: 2.4, height: segLen + 1.4, rotation: -a,
                    shape: .stem, color: params.stemColor))
                if s == 2, g > 0.3 {
                    let leafSize = 9 * min(1, (g - 0.3) * 2)
                    for side: Float in [-1, 1] {
                        let la = -a + side * 0.9
                        batch.sprites.append(SpriteInstance(
                            x: mid.x + side * leafSize * 0.35, y: mid.y, width: leafSize * 0.55, height: leafSize,
                            rotation: la, shape: .leaf, param: 2, color: params.leafColor))
                    }
                }
                p = next
            }
            let bloom = clamp((f.growth - 0.55) / 0.45, 0, 1)
            if bloom > 0 {
                let style = params.species[f.species].headStyle
                let size = f.headSize * (0.35 + 0.65 * bloom)
                batch.sprites.append(SpriteInstance(
                    x: p.x, y: p.y + size * 0.25, width: size, height: size, rotation: -f.bend,
                    shape: .flowerHead, param: style, param2: bloom, color: f.color))
            }
        }
    }
}

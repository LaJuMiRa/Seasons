import Foundation

/// Smooth, deterministic wind made of slow sine waves plus occasional gusts.
public struct Wind: Sendable {
    private let phases: (Float, Float, Float, Float)

    public init(seed: UInt64) {
        var rng = SeededRandom(seed: seed ^ 0xA11CE)
        phases = (rng.float(in: 0...6.28), rng.float(in: 0...6.28), rng.float(in: 0...6.28), rng.float(in: 0...6.28))
    }

    /// Returns (base, gust): base is roughly -1...1, gust is 0...1.
    public func sample(at time: Double) -> (base: Float, gust: Float) {
        let t = Float(time.truncatingRemainder(dividingBy: 100_000))
        let base = 0.55 * sin(t * 0.045 + phases.0) + 0.3 * sin(t * 0.11 + phases.1) + 0.15 * sin(t * 0.27 + phases.2)
        let g = max(0, sin(t * 0.19 + phases.3))
        return (base, g * g * g)
    }

    /// Horizontal wind speed in points per second for the given effect parameters.
    public func speed(at time: Double, strength: Float, gustiness: Float) -> Float {
        let s = sample(at: time)
        return s.base * strength + s.gust * gustiness * (s.base >= 0 ? 1 : -1)
    }
}

/// Amount of falling particles.
public enum Intensity: String, CaseIterable, Codable, Sendable {
    case off, light, medium, heavy, variable

    /// Spawn-rate multiplier. `variable` drifts between light and heavy over minutes.
    public func multiplier(at time: Double) -> Float {
        switch self {
        case .off: return 0
        case .light: return 0.4
        case .medium: return 1
        case .heavy: return 2.2
        case .variable:
            let t = time.truncatingRemainder(dividingBy: 1_000_000)
            let wave = 0.95 + 0.75 * sin(t * 2 * .pi / 290) + 0.35 * sin(t * 2 * .pi / 83 + 1.3)
            return Float(min(max(wave, 0.12), 2.1))
        }
    }
}

public enum Season: String, Sendable, CaseIterable {
    case winter, spring, summer, autumn

    /// Meteorological seasons by month (1...12).
    public static func of(month: Int, southernHemisphere: Bool = false) -> Season {
        let northern: Season
        switch month {
        case 12, 1, 2: northern = .winter
        case 3, 4, 5: northern = .spring
        case 6, 7, 8: northern = .summer
        default: northern = .autumn
        }
        guard southernHemisphere else { return northern }
        switch northern {
        case .winter: return .summer
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        }
    }
}

/// What is shown: an optional falling effect plus the optional flower layer.
public struct SceneSelection: Equatable, Sendable {
    public var effect: EffectKind?
    public var flowers: Bool

    public init(effect: EffectKind?, flowers: Bool) {
        self.effect = effect
        self.flowers = flowers
    }

    public static func automatic(for season: Season, rainInSummer: Bool) -> SceneSelection {
        switch season {
        case .winter: return SceneSelection(effect: .snow, flowers: false)
        case .spring: return SceneSelection(effect: .blossoms, flowers: true)
        case .summer: return SceneSelection(effect: rainInSummer ? .rain : nil, flowers: false)
        case .autumn: return SceneSelection(effect: .leaves, flowers: false)
        }
    }
}

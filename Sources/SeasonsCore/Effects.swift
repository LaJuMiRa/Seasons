/// The falling effects. Flowers are a separate, combinable layer (see `FlowerGarden`).
public enum EffectKind: String, CaseIterable, Codable, Sendable {
    case snow
    case leaves
    case rain
    case blossoms
}

/// Shape ids understood by the renderer's fragment shader.
public enum SpriteShape: UInt32, Sendable {
    case flake = 0
    case leaf = 1
    case streak = 2
    case petal = 3
    case bead = 4
    case splash = 5
    case stem = 6
    case flowerHead = 7
}

/// How accumulated mass on a ledge is drawn.
public enum PileStyle: Sendable {
    /// Continuous blanket (snow).
    case blanket
    /// Individual sprites stacked on a soft base (leaves, petals).
    case scatter
    /// Thin translucent film with beads; puddles on the floor (rain).
    case water
}

public enum LedgeKind: Sendable, Equatable {
    case floor
    case dock
    case window
}

public struct PileParameters: Sendable {
    /// Maximum pile height in points per ledge kind; extra mass is compacted away.
    public var maxHeightFloor: Float
    public var maxHeightDock: Float
    public var maxHeightWindow: Float
    /// Angle of repose as max height difference per point of horizontal distance.
    public var reposeSlope: Float
    /// Fraction of a landing sprite's area that becomes pile area.
    public var depositFactor: Float
    /// Natural decay in points per second (evaporation for rain, 0 otherwise).
    public var decayPerSecond: Float
    /// Decay in points per second while "Melt" is active.
    public var meltPerSecond: Float
    public var style: PileStyle
    /// Blanket/base color at the top and bottom of the pile.
    public var colorTop: RGBA
    public var colorBottom: RGBA
    /// Vertical spacing between stacked sprites for `.scatter`, in points.
    public var scatterSpacing: Float

    public func maxHeight(for kind: LedgeKind) -> Float {
        switch kind {
        case .floor: return maxHeightFloor
        case .dock: return maxHeightDock
        case .window: return maxHeightWindow
        }
    }
}

/// One row of the effect parameter table. All tunable numbers for an effect live here.
public struct EffectParameters: Sendable {
    public var shape: SpriteShape
    /// Sprite width in points.
    public var size: ClosedRange<Float>
    /// Sprite height / width (streaks are long and thin).
    public var aspect: Float
    /// Terminal fall speed in points per second.
    public var fallSpeed: ClosedRange<Float>
    /// Lateral sway velocity amplitude in points per second.
    public var swayAmplitude: Float
    /// Sway frequency in Hz.
    public var swayFrequency: ClosedRange<Float>
    /// Spin in radians per second (sign chosen randomly).
    public var spin: ClosedRange<Float>
    /// Wind speed scale in points per second.
    public var windStrength: Float
    /// Extra gust strength in points per second.
    public var gustiness: Float
    /// How fast velocity relaxes back to terminal velocity (1/s). Higher = heavier feel.
    public var drag: Float
    /// Spawned particles per second per 1000 points of screen width at intensity 1.
    public var density: Float
    /// Hard cap of airborne particles per screen.
    public var maxParticles: Int
    /// Number of splash droplets on impact (rain), 0 for none.
    public var splashCount: Int
    public var colors: [RGBA]
    public var pile: PileParameters
}

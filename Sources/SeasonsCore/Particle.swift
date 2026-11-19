/// An airborne particle (flake, leaf, drop, petal or splash droplet).
public struct Particle: Sendable {
    public var position: Vec2
    public var velocity: Vec2
    public var size: Float
    public var rotation: Float
    public var spin: Float
    /// Terminal fall speed in points per second.
    public var fallSpeed: Float
    public var swayPhase: Float
    public var swayFrequency: Float
    public var shape: SpriteShape
    public var color: RGBA
    /// Seconds left for transient splash droplets; negative means unlimited.
    public var life: Float
    /// Ledge this particle must not land on for `ignoreTimer` seconds (just left it).
    public var ignoreLedge: UInt64
    public var ignoreTimer: Float
    /// Sprite variant (e.g. leaf type), stable for the particle's lifetime.
    public var variant: Float

    public var isSplash: Bool { life >= 0 }

    /// Area used when the particle lands (square points).
    public var area: Float { size * size * 0.8 }
}

// Configuration file: the per-effect parameter tables.
// Every tunable number for the look and feel of an effect lives here and nowhere else.

public enum EffectCatalog {
    public static func parameters(for kind: EffectKind) -> EffectParameters {
        switch kind {
        case .snow: return snow
        case .leaves: return leaves
        case .rain: return rain
        case .blossoms: return blossoms
        }
    }

    public static let snow = EffectParameters(
        shape: .flake,
        size: 2.5...8,
        aspect: 1,
        fallSpeed: 30...85,
        swayAmplitude: 14,
        swayFrequency: 0.15...0.6,
        spin: 0...0.6,
        windStrength: 18,
        gustiness: 30,
        drag: 1.6,
        density: 34,
        maxParticles: 2200,
        splashCount: 0,
        colors: [RGBA(1, 1, 1, 0.95), RGBA(0.93, 0.96, 1, 0.9), RGBA(0.88, 0.93, 1, 0.85)],
        pile: PileParameters(
            maxHeightFloor: 64,
            maxHeightDock: 34,
            maxHeightWindow: 26,
            reposeSlope: 0.55,
            smoothing: 0.10,
            depositFactor: 0.55,
            decayPerSecond: 0,
            meltPerSecond: 2.2,
            style: .blanket,
            colorTop: RGBA(0.99, 0.995, 1, 0.98),
            colorBottom: RGBA(0.84, 0.90, 0.98, 0.96),
            scatterSpacing: 0
        )
    )

    public static let leaves = EffectParameters(
        shape: .leaf,
        size: 11...19,
        aspect: 1.25,
        fallSpeed: 45...85,
        swayAmplitude: 46,
        swayFrequency: 0.25...0.7,
        spin: 0.8...3.2,
        windStrength: 32,
        gustiness: 55,
        drag: 1.4,
        density: 3.2,
        maxParticles: 260,
        splashCount: 0,
        colors: [
            RGBA(hex: 0xD9480F), RGBA(hex: 0xE8590C), RGBA(hex: 0xF08C00),
            RGBA(hex: 0xFAB005), RGBA(hex: 0xC92A2A), RGBA(hex: 0x8B4513),
            RGBA(hex: 0xA0522D),
        ],
        pile: PileParameters(
            maxHeightFloor: 36,
            maxHeightDock: 22,
            maxHeightWindow: 18,
            reposeSlope: 0.9,
            smoothing: 0.0,
            depositFactor: 0.22,
            decayPerSecond: 0,
            meltPerSecond: 1.6,
            style: .scatter,
            colorTop: RGBA(hex: 0x9C4A1A, alpha: 0.0),
            colorBottom: RGBA(hex: 0x6B3410, alpha: 0.75),
            scatterSpacing: 4.5
        )
    )

    public static let rain = EffectParameters(
        shape: .streak,
        size: 1.1...1.8,
        aspect: 14,
        fallSpeed: 620...900,
        swayAmplitude: 0,
        swayFrequency: 0...0,
        spin: 0...0,
        windStrength: 70,
        gustiness: 90,
        drag: 5,
        density: 150,
        maxParticles: 2600,
        splashCount: 3,
        colors: [RGBA(0.72, 0.82, 0.95, 0.55), RGBA(0.80, 0.88, 1, 0.45)],
        pile: PileParameters(
            maxHeightFloor: 7,
            maxHeightDock: 3,
            maxHeightWindow: 2.4,
            reposeSlope: 0.04,
            smoothing: 0.3,
            depositFactor: 0.35,
            decayPerSecond: 0.012,
            meltPerSecond: 0.6,
            style: .water,
            colorTop: RGBA(0.86, 0.93, 1, 0.55),
            colorBottom: RGBA(0.55, 0.70, 0.92, 0.30),
            scatterSpacing: 0
        )
    )

    public static let blossoms = EffectParameters(
        shape: .petal,
        size: 7...12,
        aspect: 1.1,
        fallSpeed: 22...48,
        swayAmplitude: 34,
        swayFrequency: 0.2...0.55,
        spin: 0.5...2.2,
        windStrength: 26,
        gustiness: 40,
        drag: 1.2,
        density: 6,
        maxParticles: 420,
        splashCount: 0,
        colors: [
            RGBA(hex: 0xFFC9DE), RGBA(hex: 0xFFB3CF), RGBA(hex: 0xFADDE8),
            RGBA(hex: 0xF7A1C4), RGBA(hex: 0xFFF0F5),
        ],
        pile: PileParameters(
            maxHeightFloor: 26,
            maxHeightDock: 16,
            maxHeightWindow: 13,
            reposeSlope: 0.7,
            smoothing: 0.03,
            depositFactor: 0.25,
            decayPerSecond: 0,
            meltPerSecond: 1.2,
            style: .scatter,
            colorTop: RGBA(hex: 0xFFD6E5, alpha: 0.0),
            colorBottom: RGBA(hex: 0xF5B8CF, alpha: 0.7),
            scatterSpacing: 3.2
        )
    )

    // MARK: - Flowers along the Dock

    public struct FlowerSpecies: Sendable {
        /// Head style id understood by the shader (0 daisy, 1 tulip, 2 poppy, 3 star, 4 bell).
        public var headStyle: Float
        public var headSize: ClosedRange<Float>
        public var stemHeight: ClosedRange<Float>
        public var colors: [RGBA]
    }

    public struct FlowerParameters: Sendable {
        public var spacing: ClosedRange<Float>
        /// Seconds until fully grown.
        public var growDuration: ClosedRange<Float>
        /// Seconds before a wiped flower starts to regrow.
        public var regrowDelay: ClosedRange<Float>
        public var stemColor: RGBA
        public var leafColor: RGBA
        /// Cursor influence radius in points.
        public var mouseRadius: Float
        /// Cursor speed (points per second) needed to wipe a flower away.
        public var wipeSpeed: Float
        public var stiffness: Float
        public var damping: Float
        public var windResponse: Float
        public var species: [FlowerSpecies]
    }

    public static let flowers = FlowerParameters(
        spacing: 16...30,
        growDuration: 18...55,
        regrowDelay: 5...14,
        stemColor: RGBA(hex: 0x4C8C2B),
        leafColor: RGBA(hex: 0x5FA83A),
        mouseRadius: 46,
        wipeSpeed: 900,
        stiffness: 28,
        damping: 4.5,
        windResponse: 0.006,
        species: [
            FlowerSpecies(headStyle: 0, headSize: 16...22, stemHeight: 30...52,
                          colors: [RGBA(1, 1, 1), RGBA(hex: 0xFFF3BF)]),
            FlowerSpecies(headStyle: 1, headSize: 14...19, stemHeight: 34...58,
                          colors: [RGBA(hex: 0xE03131), RGBA(hex: 0xF783AC), RGBA(hex: 0xFCC419), RGBA(hex: 0x9C36B5)]),
            FlowerSpecies(headStyle: 2, headSize: 17...23, stemHeight: 32...56,
                          colors: [RGBA(hex: 0xF03E3E), RGBA(hex: 0xFF922B)]),
            FlowerSpecies(headStyle: 3, headSize: 11...14, stemHeight: 18...34,
                          colors: [RGBA(hex: 0x74C0FC), RGBA(hex: 0x4DABF7), RGBA(hex: 0xB197FC)]),
            FlowerSpecies(headStyle: 4, headSize: 13...17, stemHeight: 28...46,
                          colors: [RGBA(hex: 0x9775FA), RGBA(hex: 0x748FFC)]),
        ]
    )

    // MARK: - Interaction

    /// Cursor influence radius on airborne particles and piles, in points.
    public static let mouseRadius: Float = 52
    /// Constant repulsion (points per second) near the cursor even when it is still.
    public static let mouseRepulsion: Float = 160
    /// Fraction of the cursor velocity transferred to particles it touches.
    public static let mouseCoupling: Float = 0.55
    /// Ledge resolution in points per height-field cell.
    public static let cellWidth: Float = 3
    /// Maximum particles spawned per frame from wiped or spilled piles.
    public static let maxEjectPerFrame = 120
}

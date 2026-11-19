/// Deterministic SplitMix64 generator. The simulation only uses this generator,
/// so a fixed seed and fixed inputs always produce the same result.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform Float in 0..<1.
    public mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    public mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    /// Uniform Int in 0..<upperBound (upperBound > 0).
    public mutating func int(below upperBound: Int) -> Int {
        Int(next() % UInt64(max(upperBound, 1)))
    }

    /// Returns -1 or +1.
    public mutating func sign() -> Float {
        next() & 1 == 0 ? -1 : 1
    }
}

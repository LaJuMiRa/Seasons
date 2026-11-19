import Foundation

/// 2D vector in points. Coordinates are screen-local with the origin at the
/// bottom-left corner and y pointing up.
public struct Vec2: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Float) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }

    public var length: Float { (x * x + y * y).squareRoot() }
}

/// Axis-aligned rectangle in screen-local points (origin bottom-left, y up).
public struct Rect: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Float { x }
    public var maxX: Float { x + width }
    public var minY: Float { y }
    public var maxY: Float { y + height }
}

/// Linear RGBA color, components 0...1, not premultiplied.
public struct RGBA: Equatable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Hex helper for readable configuration tables, e.g. `RGBA(hex: 0xE8743B)`.
    public init(hex: UInt32, alpha: Float = 1) {
        self.init(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255,
            alpha
        )
    }

    public func withAlpha(_ alpha: Float) -> RGBA { RGBA(r, g, b, alpha) }
}

@inline(__always)
func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

@inline(__always)
func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// Stateless integer hash used for stable, flicker-free decoration of piles.
@inline(__always)
func hash32(_ a: UInt32, _ b: UInt32) -> UInt32 {
    var h = a &* 0x9E37_79B1 ^ (b &+ 0x7F4A_7C15) &* 0x85EB_CA6B
    h ^= h >> 15
    h = h &* 0xC2B2_AE35
    h ^= h >> 13
    return h
}

/// Maps a hash to 0..<1.
@inline(__always)
func unitHash(_ a: UInt32, _ b: UInt32) -> Float {
    Float(hash32(a, b) >> 8) / Float(1 << 24)
}

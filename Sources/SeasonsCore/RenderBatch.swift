/// One instanced quad for the GPU. Layout must match `SpriteInstance` in the Metal shader
/// (12 floats, 48 bytes).
public struct SpriteInstance: Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    /// Counter-clockwise rotation in radians.
    public var rotation: Float
    public var shape: Float
    /// Shape-specific parameter (leaf variant, flower head style, bloom amount ...).
    public var param: Float
    public var param2: Float
    public var color: RGBA

    public init(x: Float, y: Float, width: Float, height: Float, rotation: Float,
                shape: SpriteShape, param: Float = 0, param2: Float = 0, color: RGBA) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.shape = Float(shape.rawValue)
        self.param = param
        self.param2 = param2
        self.color = color
    }
}

/// Vertex of the pile mesh (triangles). Layout must match `PileVertex` in the shader.
public struct PileVertex: Sendable {
    public var x: Float
    public var y: Float
    public var color: RGBA
}

/// Everything the renderer needs for one frame, in draw order:
/// pile mesh first, then sprites (pile decoration, flowers, airborne particles).
public struct RenderBatch: Sendable {
    public var pileVertices: [PileVertex] = []
    public var sprites: [SpriteInstance] = []

    public init() {}

    public mutating func reset() {
        pileVertices.removeAll(keepingCapacity: true)
        sprites.removeAll(keepingCapacity: true)
    }

    mutating func appendQuad(x0: Float, x1: Float, bottom0: Float, top0: Float, bottom1: Float, top1: Float,
                             colorBottom: RGBA, colorTop: RGBA) {
        let a = PileVertex(x: x0, y: bottom0, color: colorBottom)
        let b = PileVertex(x: x1, y: bottom1, color: colorBottom)
        let c = PileVertex(x: x0, y: top0, color: colorTop)
        let d = PileVertex(x: x1, y: top1, color: colorTop)
        pileVertices.append(contentsOf: [a, b, c, c, b, d])
    }
}

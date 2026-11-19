import Metal
import MetalKit
import SeasonsCore

/// Device, queue and pipelines shared by all overlay views.
final class MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let spritePipeline: MTLRenderPipelineState
    let pilePipeline: MTLRenderPipelineState
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    private init(device: MTLDevice, queue: MTLCommandQueue, sprite: MTLRenderPipelineState, pile: MTLRenderPipelineState) {
        self.device = device
        self.queue = queue
        spritePipeline = sprite
        pilePipeline = pile
    }

    static func make() -> MetalContext? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let sprite = try pipeline(device, library, vertex: "sprite_vertex", fragment: "sprite_fragment")
            let pile = try pipeline(device, library, vertex: "pile_vertex", fragment: "pile_fragment")
            return MetalContext(device: device, queue: queue, sprite: sprite, pile: pile)
        } catch {
            log.error("Metal setup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func pipeline(_ device: MTLDevice, _ library: MTLLibrary, vertex: String,
                                 fragment: String) throws -> MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: vertex)
        d.fragmentFunction = library.makeFunction(name: fragment)
        let c = d.colorAttachments[0]!
        c.pixelFormat = pixelFormat
        // Premultiplied alpha over a transparent window.
        c.isBlendingEnabled = true
        c.rgbBlendOperation = .add
        c.alphaBlendOperation = .add
        c.sourceRGBBlendFactor = .one
        c.sourceAlphaBlendFactor = .one
        c.destinationRGBBlendFactor = .oneMinusSourceAlpha
        c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: d)
    }
}

/// Per-view renderer with triple-buffered vertex/instance buffers.
final class MetalRenderer {
    private let context: MetalContext
    private static let inFlight = 3
    private let semaphore = DispatchSemaphore(value: MetalRenderer.inFlight)
    private var spriteBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.inFlight)
    private var pileBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.inFlight)
    private var frameIndex = 0

    private struct Uniforms {
        var viewSize: SIMD2<Float>
        var pad: SIMD2<Float> = .zero
    }

    init(context: MetalContext) {
        self.context = context
    }

    func draw(_ batch: RenderBatch, in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        let size = SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        guard let commands = encode(batch, pass: pass, viewSize: size) else { return }
        commands.present(drawable)
        commands.commit()
    }

    /// Encodes one frame into `pass`. The caller commits the returned command buffer.
    func encode(_ batch: RenderBatch, pass: MTLRenderPassDescriptor, viewSize: SIMD2<Float>) -> MTLCommandBuffer? {
        semaphore.wait()
        frameIndex = (frameIndex + 1) % Self.inFlight
        let spriteBuffer = upload(batch.sprites, into: &spriteBuffers[frameIndex])
        let pileBuffer = upload(batch.pileVertices, into: &pileBuffers[frameIndex])

        guard let commands = context.queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            semaphore.signal()
            return nil
        }
        var uniforms = Uniforms(viewSize: viewSize)
        if let pileBuffer, !batch.pileVertices.isEmpty {
            encoder.setRenderPipelineState(context.pilePipeline)
            encoder.setVertexBuffer(pileBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: batch.pileVertices.count)
        }
        if let spriteBuffer, !batch.sprites.isEmpty {
            encoder.setRenderPipelineState(context.spritePipeline)
            encoder.setVertexBuffer(spriteBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: batch.sprites.count)
        }
        encoder.endEncoding()
        let sem = semaphore
        commands.addCompletedHandler { _ in sem.signal() }
        return commands
    }

    /// Copies `items` into a reusable buffer that grows in powers of two.
    private func upload<T>(_ items: [T], into slot: inout MTLBuffer?) -> MTLBuffer? {
        guard !items.isEmpty else { return slot }
        let bytes = items.count * MemoryLayout<T>.stride
        if slot == nil || slot!.length < bytes {
            var capacity = 64 * 1024
            while capacity < bytes { capacity *= 2 }
            slot = context.device.makeBuffer(length: capacity, options: .storageModeShared)
        }
        guard let buffer = slot else { return nil }
        items.withUnsafeBytes { raw in
            buffer.contents().copyMemory(from: raw.baseAddress!, byteCount: bytes)
        }
        return buffer
    }

    /// Releases GPU buffers (screen removed).
    func releaseBuffers() {
        spriteBuffers = Array(repeating: nil, count: Self.inFlight)
        pileBuffers = Array(repeating: nil, count: Self.inFlight)
    }
}

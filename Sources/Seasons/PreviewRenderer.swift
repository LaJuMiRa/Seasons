import AppKit
import ImageIO
import Metal
import SeasonsCore
import UniformTypeIdentifiers

/// Developer aid: `Seasons --render-preview <folder>` simulates every effect on a synthetic
/// desktop (Dock plus two windows) and writes PNGs rendered by the real Metal pipeline.
/// Used to check the look without needing Screen Recording permission for screenshots.
enum PreviewRenderer {
    private static let width: Float = 1440
    private static let height: Float = 900
    private static let scale = 2

    private struct Scenario {
        let name: String
        let effect: EffectKind
        let flowers: Bool
        let wipe: Bool
    }

    static func run(outputFolder: String, context: MetalContext) -> Int32 {
        let scenarios = [
            Scenario(name: "snow", effect: .snow, flowers: false, wipe: false),
            Scenario(name: "snow-wiped", effect: .snow, flowers: false, wipe: true),
            Scenario(name: "leaves", effect: .leaves, flowers: false, wipe: false),
            Scenario(name: "rain", effect: .rain, flowers: false, wipe: false),
            Scenario(name: "blossoms-flowers", effect: .blossoms, flowers: true, wipe: false),
        ]
        let renderer = MetalRenderer(context: context)
        for s in scenarios {
            let batch = simulate(s)
            guard let image = render(batch, renderer: renderer, context: context) else { return 1 }
            let url = URL(fileURLWithPath: outputFolder).appendingPathComponent("\(s.name).png")
            guard write(image, to: url) else { return 1 }
            print("wrote \(url.path) (\(batch.sprites.count) sprites, \(batch.pileVertices.count / 3) triangles)")
        }
        return 0
    }

    private static let dock = Rect(x: 420, y: 0, width: 600, height: 72)
    private static let windows = [
        WindowFrame(id: 1, rect: Rect(x: 160, y: 260, width: 560, height: 420)),
        WindowFrame(id: 2, rect: Rect(x: 600, y: 160, width: 640, height: 380)),
    ]

    private static func simulate(_ s: Scenario) -> RenderBatch {
        let world = SimulationWorld(width: width, height: height, effect: s.effect, seed: 2026)
        world.flowersEnabled = s.flowers
        let geometry = ScreenGeometry(width: width, height: height, topInset: 30,
                                      dock: DockFrame(rect: dock, edge: .bottom, isShown: true), windows: windows)
        world.updateLedges(LedgeLayout.compute(geometry, includeWindowsAndDock: true), time: 0, removal: .spill)
        world.setGardenBase(GardenBase(minX: dock.minX + 6, maxX: dock.maxX - 6, y: dock.maxY))
        let dt: Float = 1.0 / 30
        let seconds: Float = s.effect == .rain ? 25 : 120
        var t = 0.0
        for _ in 0..<Int(seconds / dt) {
            world.step(dt: dt, time: t, input: StepInput(mouse: nil, intensity: 2.2))
            t += Double(dt)
        }
        if s.wipe {
            // Sweep the cursor along the top of the front window, then let a moment pass.
            for i in 0..<45 {
                let mouse = Vec2(620 + Float(i) * 9, 545)
                world.step(dt: 1.0 / 60, time: t, input: StepInput(mouse: mouse, intensity: 2.2))
                t += 1.0 / 60
            }
            for _ in 0..<8 {
                world.step(dt: 1.0 / 60, time: t, input: StepInput(mouse: nil, intensity: 2.2))
                t += 1.0 / 60
            }
        }
        var batch = RenderBatch()
        world.buildRenderBatch(&batch)
        batch.pileVertices = background() + batch.pileVertices
        return batch
    }

    /// Synthetic desktop: gradient wallpaper, two windows with title bars and a Dock.
    private static func background() -> [PileVertex] {
        var b = RenderBatch()
        b.appendQuad(x0: 0, x1: width, bottom0: 0, top0: height, bottom1: 0, top1: height,
                     colorBottom: RGBA(hex: 0x1D2B44), colorTop: RGBA(hex: 0x4B6386))
        for w in windows.reversed() {
            let r = w.rect
            b.appendQuad(x0: r.minX, x1: r.maxX, bottom0: r.minY, top0: r.maxY - 28, bottom1: r.minY, top1: r.maxY - 28,
                         colorBottom: RGBA(hex: 0xF4F5F7), colorTop: RGBA(hex: 0xFAFAFB))
            b.appendQuad(x0: r.minX, x1: r.maxX, bottom0: r.maxY - 28, top0: r.maxY, bottom1: r.maxY - 28, top1: r.maxY,
                         colorBottom: RGBA(hex: 0xDCDEE3), colorTop: RGBA(hex: 0xE6E8EC))
        }
        b.appendQuad(x0: dock.minX, x1: dock.maxX, bottom0: 4, top0: dock.maxY, bottom1: 4, top1: dock.maxY,
                     colorBottom: RGBA(1, 1, 1, 0.22), colorTop: RGBA(1, 1, 1, 0.32))
        b.appendQuad(x0: 0, x1: width, bottom0: height - 30, top0: height, bottom1: height - 30, top1: height,
                     colorBottom: RGBA(0, 0, 0, 0.25), colorTop: RGBA(0, 0, 0, 0.25))
        return b.pileVertices
    }

    private static func render(_ batch: RenderBatch, renderer: MetalRenderer, context: MetalContext) -> CGImage? {
        let pw = Int(width) * scale
        let ph = Int(height) * scale
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MetalContext.pixelFormat, width: pw,
                                                            height: ph, mipmapped: false)
        desc.usage = [.renderTarget]
        desc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: desc) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let commands = renderer.encode(batch, pass: pass, viewSize: SIMD2(width, height)) else { return nil }
        commands.commit()
        commands.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: pw * ph * 4)
        texture.getBytes(&pixels, bytesPerRow: pw * 4, from: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: pw, height: ph, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pw * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}

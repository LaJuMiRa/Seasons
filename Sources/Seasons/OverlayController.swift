import AppKit
import MetalKit
import SeasonsCore

/// One screen: overlay window, Metal view and the simulation for that screen.
@MainActor
final class OverlayController: NSObject, MTKViewDelegate {
    let displayID: CGDirectDisplayID
    private(set) var screen: NSScreen
    let world: SimulationWorld
    private var window: OverlayWindow
    private let view: MTKView
    private let renderer: MetalRenderer
    private var batch = RenderBatch()
    private var lastFrame: CFTimeInterval?
    /// All screens share this wind, so the effect falls the same way everywhere.
    private static let sharedWindSeed: UInt64 = 0x5EA5_0001
    /// Called with particles that left this screen towards a neighbour (positions in local points).
    var onParticlesExit: (([Particle]) -> Void)?
    private var quietFrames = 0
    private var lastSpecs: [LedgeSpec] = []
    private var occlusionToken: NSObjectProtocol?
    /// Drives frames. CADisplayLink (macOS 14) lets the system schedule exactly the
    /// requested rate; MTKView's own loop is turned off.
    private var displayLink: CADisplayLink?
    private var framesPerSecond = SystemMonitor.fpsOnAC

    // Run state. Rendering happens only when all of these allow it.
    private var userPaused = false
    private var suspended = false
    private var occluded = false
    /// An app from "Hide Effects in Apps" is in front: the overlay is out of the way.
    private var hiddenByApp = false
    private(set) var isIdle = false
    private var intensity: Intensity = .medium
    private var hasEffect = true
    private var pointerInteraction = true

    /// Frames of "nothing happens" before the view stops rendering.
    private static let framesBeforeIdle = 45

    init(screen: NSScreen, displayID: CGDirectDisplayID, context: MetalContext, desktopOnly: Bool) {
        self.displayID = displayID
        self.screen = screen
        window = OverlayWindow(frame: screen.frame, desktopOnly: desktopOnly)
        view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: context.device)
        renderer = MetalRenderer(context: context)
        let seed = UInt64(displayID) &* 0x9E37_79B9 ^ UInt64(Date().timeIntervalSince1970)
        world = SimulationWorld(width: Float(screen.frame.width), height: Float(screen.frame.height),
                                effect: .snow, seed: seed, windSeed: Self.sharedWindSeed)
        super.init()

        view.colorPixelFormat = MetalContext.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        view.delegate = self
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        observeOcclusion()

        let link = view.displayLink(target: self, selector: #selector(displayTick(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
        applyFrameRate()
    }

    private func observeOcclusion() {
        if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
        occlusionToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }

    /// Moves the Metal view into a new window with the other full-screen behavior. The
    /// simulation, display link and renderer stay as they are.
    private func replaceWindow(desktopOnly: Bool) {
        let old = window
        window = OverlayWindow(frame: screen.frame, desktopOnly: desktopOnly)
        window.sharingType = old.sharingType
        old.orderOut(nil)
        old.contentView = nil
        window.contentView = view
        if hiddenByApp { window.orderOut(nil) } else { window.orderFrontRegardless() }
        observeOcclusion()
        occlusionChanged()
    }

    func tearDown() {
        if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
        displayLink?.invalidate()
        displayLink = nil
        view.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        renderer.releaseBuffers()
    }

    // MARK: - Configuration

    func setScreen(_ newScreen: NSScreen) {
        screen = newScreen
        window.setFrame(newScreen.frame, display: false)
        world.resize(width: Float(newScreen.frame.width), height: Float(newScreen.frame.height))
        lastSpecs = []
        wake()
    }

    func configure(scene: SceneSelection, settings: Settings) {
        if let effect = scene.effect { world.setEffect(effect) }
        hasEffect = scene.effect != nil
        world.flowersEnabled = scene.flowers
        world.accumulateOnWindows = settings.pileOnWindows
        world.accumulateOnDock = settings.pileOnDock
        pointerInteraction = settings.pointerInteraction
        world.isMelting = settings.melting
        intensity = settings.intensity
        userPaused = settings.paused
        if settings.desktopOnly != window.desktopOnly { replaceWindow(desktopOnly: settings.desktopOnly) }
        window.sharingType = settings.hideInScreenshots ? .none : .readOnly
        lastSpecs = []
        wake()
        if userPaused { view.draw() } // show the frozen frame with current settings
    }

    func setSuspended(_ value: Bool, framesPerSecond: Int) {
        if framesPerSecond != self.framesPerSecond {
            self.framesPerSecond = framesPerSecond
            applyFrameRate()
        }
        guard value != suspended else { return }
        suspended = value
        updateRunning()
    }

    func setNeighbors(left: Bool, right: Bool) {
        world.hasNeighborLeft = left
        world.hasNeighborRight = right
    }

    /// Takes over particles that flew in from a neighbouring screen.
    func adopt(_ incoming: [Particle]) {
        incoming.forEach(world.adopt)
        wake()
    }

    func setHiddenByApp(_ value: Bool) {
        guard value != hiddenByApp else { return }
        hiddenByApp = value
        if value {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
            lastFrame = nil
        }
        updateRunning()
    }

    func perform(_ command: OverlayCommand) {
        switch command {
        case .clear: world.clearAll()
        }
        wake()
        if userPaused { view.draw() }
    }

    /// Converts global window geometry into ledges for this screen.
    func updateGeometry(windows: [TrackedWindow], primaryHeight: CGFloat, dockPrefs: DockLocator.Preferences,
                        isPrimary: Bool, removal: LedgeRemoval) {
        let f = screen.frame
        let local = windows.compactMap { w -> WindowFrame? in
            let nsRect = CGRect(x: w.bounds.minX, y: primaryHeight - w.bounds.maxY,
                                width: w.bounds.width, height: w.bounds.height)
            guard nsRect.intersects(f) else { return nil }
            return WindowFrame(id: w.id, rect: Rect(x: Float(nsRect.minX - f.minX), y: Float(nsRect.minY - f.minY),
                                                    width: Float(nsRect.width), height: Float(nsRect.height)))
        }
        let dock = DockLocator.dock(on: screen, isPrimary: isPrimary, prefs: dockPrefs)
        let geometry = ScreenGeometry(width: Float(f.width), height: Float(f.height),
                                      topInset: Float(f.maxY - screen.visibleFrame.maxY), dock: dock, windows: local)
        let specs = LedgeLayout.compute(geometry, includeWindows: world.accumulateOnWindows,
                                        includeDock: world.accumulateOnDock)
        world.setGardenBase(DockLocator.gardenBase(for: dock, screenWidth: Float(f.width)))
        guard specs != lastSpecs else { return }
        lastSpecs = specs
        world.updateLedges(specs, time: CACurrentMediaTime(), removal: removal)
        wake()
    }

    // MARK: - Run state

    private var shouldRender: Bool { !suspended && !occluded && !userPaused && !isIdle && !hiddenByApp }

    private func updateRunning() {
        guard let link = displayLink else { return }
        let run = shouldRender
        if run && link.isPaused { lastFrame = nil }
        link.isPaused = !run
    }

    private func applyFrameRate() {
        let fps = Float(min(framesPerSecond, screen.maximumFramesPerSecond))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: fps * 0.5, maximum: fps, preferred: fps)
        applyResolution()
    }

    /// On battery and in Low Power Mode the view renders at 1x instead of the Retina resolution:
    /// a quarter of the pixels to shade and composite. Soft particles hardly show the difference.
    private func applyResolution() {
        let reduced = framesPerSecond < SystemMonitor.fpsOnAC
        view.autoResizeDrawable = !reduced
        let scale = reduced ? 1 : (window.screen?.backingScaleFactor ?? screen.backingScaleFactor)
        let size = view.bounds.size
        view.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
    }

    @objc private func displayTick(_ link: CADisplayLink) {
        view.draw()
    }

    func wake() {
        quietFrames = 0
        guard isIdle else { updateRunning(); return }
        isIdle = false
        updateRunning()
    }

    /// Called by the manager while idle: wake up when the cursor comes close to a pile.
    func checkWake(mouse: NSPoint) {
        guard isIdle, pointerInteraction, let local = localMouse(mouse) else { return }
        if world.isNearInteractive(local) { wake() }
    }

    private func occlusionChanged() {
        occluded = !window.occlusionState.contains(.visible)
        updateRunning()
    }

    private func localMouse(_ p: NSPoint) -> Vec2? {
        let f = screen.frame
        guard f.contains(p) else { return nil }
        return Vec2(Float(p.x - f.minX), Float(p.y - f.minY))
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { renderFrame() }
    }

    private func renderFrame() {
        let now = CACurrentMediaTime()
        let dt = lastFrame.map { Float(now - $0) } ?? 1 / 60
        lastFrame = now
        if !userPaused && !suspended {
            let mouse = pointerInteraction ? localMouse(NSEvent.mouseLocation) : nil
            let amount = hasEffect ? intensity.multiplier(at: Date().timeIntervalSinceReferenceDate) : 0
            world.step(dt: dt, time: now, input: StepInput(mouse: mouse, intensity: amount))
            let near = mouse.map { world.isNearInteractive($0) } ?? false
            quietFrames = (world.isQuiescent && !near) ? quietFrames + 1 : 0
        }
        let exited = world.takeExited()
        if !exited.isEmpty { onParticlesExit?(exited) }
        world.buildRenderBatch(&batch)
        renderer.draw(batch, in: view)
        if quietFrames > Self.framesBeforeIdle && !isIdle {
            isIdle = true
            updateRunning()
        }
    }
}

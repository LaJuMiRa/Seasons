import AppKit
import MetalKit
import SeasonsCore

/// One screen: overlay window, Metal view and the simulation for that screen.
@MainActor
final class OverlayController: NSObject, MTKViewDelegate {
    let displayID: CGDirectDisplayID
    private(set) var screen: NSScreen
    let world: SimulationWorld
    private let window: OverlayWindow
    private let view: MTKView
    private let renderer: MetalRenderer
    private var batch = RenderBatch()
    private var lastFrame: CFTimeInterval?
    private var simulationTime: Double = 0
    private var quietFrames = 0
    private var lastSpecs: [LedgeSpec] = []
    private var occlusionToken: NSObjectProtocol?

    // Run state. Rendering happens only when all of these allow it.
    private var userPaused = false
    private var suspended = false
    private var occluded = false
    private(set) var isIdle = false
    private var intensity: Intensity = .medium
    private var hasEffect = true

    /// Frames of "nothing happens" before the view stops rendering.
    private static let framesBeforeIdle = 45

    init(screen: NSScreen, displayID: CGDirectDisplayID, context: MetalContext) {
        self.displayID = displayID
        self.screen = screen
        window = OverlayWindow(frame: screen.frame)
        view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: context.device)
        renderer = MetalRenderer(context: context)
        let seed = UInt64(displayID) &* 0x9E37_79B9 ^ UInt64(Date().timeIntervalSince1970)
        world = SimulationWorld(width: Float(screen.frame.width), height: Float(screen.frame.height),
                                effect: .snow, seed: seed)
        super.init()

        view.colorPixelFormat = MetalContext.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        view.delegate = self
        view.preferredFramesPerSecond = SystemMonitor.fpsOnAC
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()

        occlusionToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }

    func tearDown() {
        if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
        view.isPaused = true
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
        world.accumulateOnWindowsAndDock = settings.accumulate
        intensity = settings.intensity
        userPaused = settings.paused
        window.sharingType = settings.hideInScreenshots ? .none : .readOnly
        lastSpecs = []
        wake()
        if userPaused { view.draw() } // show the frozen frame with current settings
    }

    func setSuspended(_ value: Bool, framesPerSecond: Int) {
        view.preferredFramesPerSecond = min(framesPerSecond, screen.maximumFramesPerSecond)
        guard value != suspended else { return }
        suspended = value
        updateRunning()
    }

    func perform(_ command: OverlayCommand) {
        switch command {
        case .clear: world.clearAll()
        case .melt: world.startMelting()
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
        let specs = LedgeLayout.compute(geometry, includeWindowsAndDock: world.accumulateOnWindowsAndDock)
        world.setGardenBase(DockLocator.gardenBase(for: dock, screenWidth: Float(f.width)))
        guard specs != lastSpecs else { return }
        lastSpecs = specs
        world.updateLedges(specs, time: CACurrentMediaTime(), removal: removal)
        wake()
    }

    // MARK: - Run state

    private var shouldRender: Bool { !suspended && !occluded && !userPaused && !isIdle }

    private func updateRunning() {
        let run = shouldRender
        if run && view.isPaused { lastFrame = nil }
        view.isPaused = !run
    }

    func wake() {
        quietFrames = 0
        guard isIdle else { updateRunning(); return }
        isIdle = false
        updateRunning()
    }

    /// Called by the manager while idle: wake up when the cursor comes close to a pile.
    func checkWake(mouse: NSPoint) {
        guard isIdle, let local = localMouse(mouse) else { return }
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
            simulationTime += Double(dt)
            let mouse = localMouse(NSEvent.mouseLocation)
            let amount = hasEffect ? intensity.multiplier(at: Date().timeIntervalSinceReferenceDate) : 0
            world.step(dt: dt, time: simulationTime, input: StepInput(mouse: mouse, intensity: amount))
            let near = mouse.map { world.isNearInteractive($0) } ?? false
            quietFrames = (world.isQuiescent && !near) ? quietFrames + 1 : 0
        }
        world.buildRenderBatch(&batch)
        renderer.draw(batch, in: view)
        if quietFrames > Self.framesBeforeIdle && !isIdle {
            isIdle = true
            updateRunning()
        }
    }
}

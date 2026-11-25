import AppKit
import SeasonsCore

/// Keeps one `OverlayController` per screen and feeds them settings, system state and geometry.
@MainActor
final class OverlayManager {
    private let context: MetalContext
    private let model: AppModel
    private let system: SystemMonitor
    private let windows: WindowTracker
    private var controllers: [CGDirectDisplayID: OverlayController] = [:]
    private var dockPrefs = DockLocator.readPreferences()
    private var stashUntil = Date.distantPast
    private var idleTimer: Timer?
    private var dockTimer: Timer?
    private var lastIdleMouse = NSPoint.zero
    private var tokens: [NSObjectProtocol] = []

    /// After a Space switch, windows that disappear keep their pile for this long.
    private static let spaceSwitchGrace: TimeInterval = 1.5

    init(context: MetalContext, model: AppModel, system: SystemMonitor, windows: WindowTracker) {
        self.context = context
        self.model = model
        self.system = system
        self.windows = windows
    }

    func start() {
        rebuildScreens()
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dockPrefs = DockLocator.readPreferences()
                self?.rebuildScreens()
            }
        })
        let ws = NSWorkspace.shared.notificationCenter
        tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stashUntil = Date().addingTimeInterval(Self.spaceSwitchGrace)
                self.windows.pollNow()
            }
        })
        tokens.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAppVisibility() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDock() }
            })
        }
        // The Dock can change size without notifications (resizing, adding items).
        dockTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDock() }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.idleTick() }
        }
        idleTimer?.tolerance = 0.05

        model.observe { [weak self] _ in self?.applySettings() }
        model.onCommand { [weak self] command in
            self?.controllers.values.forEach { $0.perform(command) }
        }
        system.onChange = { [weak self] in self?.applySystemState() }
        windows.onChange = { [weak self] in self?.pushGeometry() }
        applySystemState()
    }

    var screenCount: Int { controllers.count }

    // MARK: - Screens

    private func rebuildScreens() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            if let existing = controllers[id] {
                if existing.screen.frame != screen.frame || existing.screen.visibleFrame != screen.visibleFrame {
                    existing.setScreen(screen)
                }
            } else {
                let controller = OverlayController(screen: screen, displayID: id, context: context,
                                                  desktopOnly: model.settings.desktopOnly)
                controllers[id] = controller
                controller.onParticlesExit = { [weak self, weak controller] particles in
                    guard let controller else { return }
                    self?.route(particles, from: controller)
                }
                controller.configure(scene: model.scene, settings: model.settings)
                controller.setSuspended(system.isSuspended, framesPerSecond: system.framesPerSecond)
                controller.setHiddenByApp(isHiddenByFrontApp)
            }
        }
        for (id, controller) in controllers where !seen.contains(id) {
            controller.tearDown()
            controllers.removeValue(forKey: id)
        }
        updateNeighbors()
        log.info("screens: \(self.controllers.count)")
        pushGeometry()
    }

    /// Screens that touch another screen's left or right edge (with overlapping height).
    private func updateNeighbors() {
        for c in controllers.values {
            let f = c.screen.frame
            let others = controllers.values.filter { $0 !== c }.map(\.screen.frame)
            let left = others.contains { $0.maxX == f.minX && $0.maxY > f.minY && $0.minY < f.maxY }
            let right = others.contains { $0.minX == f.maxX && $0.maxY > f.minY && $0.minY < f.maxY }
            c.setNeighbors(left: left, right: right)
        }
    }

    /// Hands particles that left `source` sideways to the screen they flew onto.
    private func route(_ particles: [Particle], from source: OverlayController) {
        let origin = source.screen.frame.origin
        var batches: [ObjectIdentifier: (OverlayController, [Particle])] = [:]
        for var p in particles {
            let global = CGPoint(x: origin.x + CGFloat(p.position.x), y: origin.y + CGFloat(p.position.y))
            guard let target = controllers.values.first(where: { $0 !== source && $0.screen.frame.contains(global) })
            else { continue }
            p.position = Vec2(Float(global.x - target.screen.frame.minX), Float(global.y - target.screen.frame.minY))
            batches[ObjectIdentifier(target), default: (target, [])].1.append(p)
        }
        for (target, list) in batches.values { target.adopt(list) }
    }

    private func refreshDock() {
        let prefs = DockLocator.readPreferences()
        guard prefs.tileCount != dockPrefs.tileCount || prefs.tileSize != dockPrefs.tileSize
                || prefs.edge != dockPrefs.edge || prefs.autohide != dockPrefs.autohide else { return }
        dockPrefs = prefs
        pushGeometry()
    }

    // MARK: - State propagation

    private func applySettings() {
        let scene = model.scene
        let settings = model.settings
        controllers.values.forEach { $0.configure(scene: scene, settings: settings) }
        updateAppVisibility()
        updateTrackerActivity()
        pushGeometry()
    }

    private func applySystemState() {
        controllers.values.forEach {
            $0.setSuspended(system.isSuspended, framesPerSecond: system.framesPerSecond)
        }
        updateTrackerActivity()
    }

    /// Hides the overlays while an app from the "Hide Effects in Apps" list is in front.
    private var isHiddenByFrontApp: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map { model.settings.hiddenInApps.contains($0) } ?? false
    }

    private func updateAppVisibility() {
        let hide = isHiddenByFrontApp
        controllers.values.forEach { $0.setHiddenByApp(hide) }
    }

    /// Window polling only runs when piles on windows can matter.
    private func updateTrackerActivity() {
        let needed = !system.isSuspended && !model.settings.paused && model.settings.pileOnWindows
        if needed { windows.start() } else { windows.stop() }
        if needed { windows.pollNow() }
    }

    private func pushGeometry() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let primaryID = NSScreen.screens.first?.displayID
        let removal: LedgeRemoval = Date() < stashUntil ? .stash : .spill
        let list = model.settings.pileOnWindows ? windows.windows : []
        for controller in controllers.values {
            controller.updateGeometry(windows: list, primaryHeight: primaryHeight, dockPrefs: dockPrefs,
                                      isPrimary: controller.displayID == primaryID, removal: removal)
        }
    }

    private func idleTick() {
        let mouse = NSEvent.mouseLocation
        guard mouse != lastIdleMouse else { return }
        lastIdleMouse = mouse
        for c in controllers.values where c.isIdle { c.checkWake(mouse: mouse) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

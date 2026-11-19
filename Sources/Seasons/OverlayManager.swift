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
                let controller = OverlayController(screen: screen, displayID: id, context: context)
                controllers[id] = controller
                controller.configure(scene: model.scene, settings: model.settings)
                controller.setSuspended(system.isSuspended, framesPerSecond: system.framesPerSecond)
            }
        }
        for (id, controller) in controllers where !seen.contains(id) {
            controller.tearDown()
            controllers.removeValue(forKey: id)
        }
        log.info("screens: \(self.controllers.count)")
        pushGeometry()
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
        updateTrackerActivity()
        pushGeometry()
    }

    private func applySystemState() {
        controllers.values.forEach {
            $0.setSuspended(system.isSuspended, framesPerSecond: system.framesPerSecond)
        }
        updateTrackerActivity()
    }

    /// Window polling only runs when piles on windows can matter.
    private func updateTrackerActivity() {
        let needed = !system.isSuspended && !model.settings.paused && model.settings.accumulate
        if needed { windows.start() } else { windows.stop() }
        if needed { windows.pollNow() }
    }

    private func pushGeometry() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let primaryID = NSScreen.screens.first?.displayID
        let removal: LedgeRemoval = Date() < stashUntil ? .stash : .spill
        let list = model.settings.accumulate ? windows.windows : []
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

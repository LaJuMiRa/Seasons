import AppKit
import os

let log = Logger(subsystem: "com.laurenzrauscher.Seasons", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var overlays: OverlayManager?
    private var menu: StatusMenuController?
    private var system: SystemMonitor?
    private var windows: WindowTracker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let context = MetalContext.make() else {
            showFatal(L("Metal is not available on this Mac. Seasons cannot draw its effects."))
            return
        }
        let model = AppModel(store: SettingsStore())
        let system = SystemMonitor()
        let windows = WindowTracker()
        let overlays = OverlayManager(context: context, model: model, system: system, windows: windows)
        let menu = StatusMenuController(model: model, windows: windows)

        self.model = model
        self.system = system
        self.windows = windows
        self.overlays = overlays
        self.menu = menu

        system.start()
        windows.start()
        overlays.start()
        model.startSeasonClock()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windows?.stop()
    }

    private func showFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Seasons"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}

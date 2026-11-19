import AppKit
import IOKit.ps

/// Watches lock screen, sleep, screen saver, fast user switching and power source.
/// Reports whether rendering should be suspended and which frame rate to use.
@MainActor
final class SystemMonitor {
    private(set) var isSuspended = false
    private(set) var framesPerSecond = 60
    var onChange: (() -> Void)?

    private var locked = false
    private var asleep = false
    private var screensAsleep = false
    private var screenSaver = false
    private var sessionInactive = false
    private var powerSource: CFRunLoopSource?
    private var tokens: [NSObjectProtocol] = []

    static let fpsOnAC = 60
    static let fpsOnBattery = 30
    static let fpsLowPower = 20

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, "com.apple.screenIsLocked") { $0.locked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.locked = false }
        observe(distributed, "com.apple.screensaver.didstart") { $0.screenSaver = true }
        observe(distributed, "com.apple.screensaver.didstop") { $0.screenSaver = false }

        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.willSleepNotification.rawValue) { $0.asleep = true }
        observe(ws, NSWorkspace.didWakeNotification.rawValue) { $0.asleep = false }
        observe(ws, NSWorkspace.screensDidSleepNotification.rawValue) { $0.screensAsleep = true }
        observe(ws, NSWorkspace.screensDidWakeNotification.rawValue) { $0.screensAsleep = false }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification.rawValue) { $0.sessionInactive = true }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification.rawValue) { $0.sessionInactive = false }
        observe(NotificationCenter.default, Notification.Name.NSProcessInfoPowerStateDidChange.rawValue) { _ in }

        startPowerSourceNotifications()
        recompute()
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ apply: @escaping (SystemMonitor) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                apply(self)
                self.recompute()
            }
        }
        tokens.append(token)
    }

    private func startPowerSourceNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.recompute() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    private var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    private func recompute() {
        let suspended = locked || asleep || screensAsleep || screenSaver || sessionInactive
        let fps: Int
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            fps = Self.fpsLowPower
        } else if isOnBattery {
            fps = Self.fpsOnBattery
        } else {
            fps = Self.fpsOnAC
        }
        guard suspended != isSuspended || fps != framesPerSecond else { return }
        isSuspended = suspended
        framesPerSecond = fps
        log.info("system state: suspended=\(suspended) fps=\(fps)")
        onChange?()
    }
}

import AppKit
import CoreGraphics

/// A normal application window in global Quartz coordinates (origin top-left of the
/// primary display, y down). Only geometry is kept: no titles, no content.
struct TrackedWindow: Equatable, Sendable {
    let id: UInt32
    let bounds: CGRect
}

/// Polls `CGWindowListCopyWindowInfo` on a background queue.
///
/// Permission finding (tested on macOS 27.0.1, see docs/ARCHITECTURE.md): window bounds, layer
/// and owner are returned without the Screen Recording permission; only window titles are
/// withheld, and Seasons never reads them. If the list ever comes back without any foreign
/// windows, `isDetectionAvailable` turns false and the menu offers the privacy settings.
@MainActor
final class WindowTracker {
    private(set) var windows: [TrackedWindow] = []
    private(set) var isDetectionAvailable = true
    /// Called on the main thread when the window list changed.
    var onChange: (() -> Void)?
    var onAvailabilityChange: (() -> Void)?

    private let queue = DispatchQueue(label: "Seasons.WindowTracker", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastMovement = Date.distantPast
    private var emptyPolls = 0
    private var currentInterval: Double = 0
    private nonisolated let ownPID = getpid()

    /// Poll fast while windows move so piles follow them closely, slow otherwise.
    static let fastInterval = 1.0 / 30
    static let slowInterval = 1.0 / 8

    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        schedule(interval: Self.slowInterval)
        pollNow()
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        currentInterval = 0
    }

    func pollNow() {
        let pid = ownPID
        queue.async { [weak self] in
            let result = Self.readWindows(excluding: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(result) }
            }
        }
    }

    private func schedule(interval: Double) {
        guard interval != currentInterval else { return }
        currentInterval = interval
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 250)))
        let pid = ownPID
        t.setEventHandler { [weak self] in
            let result = Self.readWindows(excluding: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(result) }
            }
        }
        t.resume()
        timer = t
    }

    private func apply(_ result: (windows: [TrackedWindow], foreignEntries: Int)?) {
        let available: Bool
        if let result {
            emptyPolls = result.foreignEntries == 0 ? emptyPolls + 1 : 0
            available = emptyPolls < 16
            if result.windows != windows {
                let moved = Set(result.windows.map(\.id)) == Set(windows.map(\.id))
                if moved { lastMovement = Date() }
                windows = result.windows
                onChange?()
            }
        } else {
            emptyPolls += 1
            available = emptyPolls < 16
        }
        if available != isDetectionAvailable {
            isDetectionAvailable = available
            onAvailabilityChange?()
        }
        guard isRunning else { return }
        let recent = Date().timeIntervalSince(lastMovement) < 0.6
        schedule(interval: recent ? Self.fastInterval : Self.slowInterval)
    }

    /// Reads on-screen windows front to back. Returns nil if the API fails.
    private nonisolated static func readWindows(excluding pid: pid_t) -> (windows: [TrackedWindow], foreignEntries: Int)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else { return nil }
        var out: [TrackedWindow] = []
        var foreign = 0
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? Int32, owner != pid else { continue }
            foreign += 1
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 60, bounds.height >= 40 else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            out.append(TrackedWindow(id: number, bounds: bounds))
        }
        return (out, foreign)
    }
}

import AppKit

/// Transparent, borderless, click-through window covering one screen, above normal windows
/// and the Dock, on all Spaces and – unless `desktopOnly` – next to full-screen apps.
final class OverlayWindow: NSWindow {
    let desktopOnly: Bool

    /// With `desktopOnly`, `.fullScreenNone` replaces `.fullScreenAuxiliary`: macOS then keeps the
    /// window out of full-screen Spaces, also during the Space transition, so nothing flickers.
    /// Found by testing on macOS 27.0.1; leaving out `.fullScreenAuxiliary` alone is not enough.
    /// The behavior only takes effect for a newly created window, so toggling the setting
    /// creates a new window (see `OverlayController.configure`).
    init(frame: NSRect, desktopOnly: Bool) {
        self.desktopOnly = desktopOnly
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Above the Dock (level 20) and floating panels, below the screen saver.
        level = .statusBar
        collectionBehavior = desktopOnly
            ? [.canJoinAllSpaces, .fullScreenNone, .stationary, .ignoresCycle]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

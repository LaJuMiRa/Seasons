import AppKit
import Testing
@testable import Seasons

/// "Only on Desktop" relies on `.fullScreenNone` keeping the overlay out of full-screen Spaces.
@MainActor
@Suite("Overlay window")
struct OverlayWindowTests {
    @Test("Default: joins full-screen Spaces next to the app")
    func showsOverFullScreen() {
        let w = OverlayWindow(frame: NSRect(x: 0, y: 0, width: 100, height: 100), desktopOnly: false)
        #expect(w.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!w.collectionBehavior.contains(.fullScreenNone))
        #expect(w.collectionBehavior.contains(.canJoinAllSpaces))
    }

    @Test("Only on Desktop: stays out of full-screen Spaces, still on every desktop Space")
    func desktopOnly() {
        let w = OverlayWindow(frame: NSRect(x: 0, y: 0, width: 100, height: 100), desktopOnly: true)
        #expect(w.collectionBehavior.contains(.fullScreenNone))
        #expect(!w.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(w.collectionBehavior.contains(.canJoinAllSpaces))
    }
}

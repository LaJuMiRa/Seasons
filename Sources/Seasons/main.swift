import AppKit

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--render-preview"), flag + 1 < arguments.count {
    // Developer aid, see PreviewRenderer.swift.
    guard let context = MetalContext.make() else { exit(1) }
    exit(PreviewRenderer.run(outputFolder: arguments[flag + 1], context: context))
}

// Menu bar only: no Dock icon even when started via `swift run` (the bundle sets LSUIElement too).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

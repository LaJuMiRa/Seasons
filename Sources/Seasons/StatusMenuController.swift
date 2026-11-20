import AppKit
import CoreGraphics
import SeasonsCore

/// The menu bar icon and its menu. The menu is rebuilt each time it opens so it always
/// reflects the current state.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let windows: WindowTracker
    private let item: NSStatusItem
    let menu = NSMenu()

    init(model: AppModel, windows: WindowTracker) {
        self.model = model
        self.windows = windows
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.toolTip = "Seasons"
        model.observe { [weak self] _ in self?.updateIcon() }
    }

    // MARK: - Icon

    private func updateIcon() {
        let symbol: String
        switch model.scene.effect {
        case .snow: symbol = "snowflake"
        case .leaves: symbol = "leaf.fill"
        case .rain: symbol = "cloud.rain.fill"
        case .blossoms: symbol = "camera.macro"
        case nil: symbol = model.scene.flowers ? "camera.macro" : "sun.max"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Seasons")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.appearsDisabled = model.settings.paused
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = model.settings
        let scene = model.scene

        menu.addItem(NSMenuItem.sectionHeader(title: L("Effect")))
        for (effect, title) in [(EffectKind.snow, "Snow"), (.leaves, "Autumn Leaves"), (.rain, "Rain"),
                                (.blossoms, "Cherry Blossoms")] {
            let mi = action(L(title), #selector(selectEffect(_:)), checked: scene.effect == effect)
            mi.representedObject = effect.rawValue
            menu.addItem(mi)
        }
        menu.addItem(action(L("Flowers on the Dock"), #selector(toggleFlowers), checked: scene.flowers))

        menu.addItem(.separator())
        let auto = action(L("Choose Automatically by Season"), #selector(toggleAutomatic), checked: s.automatic)
        menu.addItem(auto)
        if s.automatic {
            let info = NSMenuItem(title: String(format: L("Current season: %@"), L(seasonName(model.season))),
                                  action: nil, keyEquivalent: "")
            info.isEnabled = false
            info.indentationLevel = 1
            menu.addItem(info)
            let rain = action(L("Rain in Summer"), #selector(toggleSummerRain), checked: s.rainInSummer)
            rain.indentationLevel = 1
            menu.addItem(rain)
        }

        menu.addItem(.separator())
        menu.addItem(action(s.paused ? L("Resume") : L("Pause"), #selector(togglePause), key: "p"))
        menu.addItem(amountMenu(current: s.intensity))
        menu.addItem(action(L("Clear Now"), #selector(clearNow), key: "k"))
        menu.addItem(action(L("Melt Away"), #selector(toggleMelt), checked: s.melting))

        menu.addItem(.separator())
        menu.addItem(action(L("Pile Up on Windows and Dock"), #selector(toggleAccumulate), checked: s.accumulate))
        menu.addItem(action(L("Hide in Screenshots and Screen Sharing"), #selector(toggleHide),
                            checked: s.hideInScreenshots))
        menu.addItem(action(L("Only on Desktop, Not Over Full-Screen Apps"), #selector(toggleDesktopOnly),
                            checked: s.desktopOnly))
        menu.addItem(action(L("Launch at Login"), #selector(toggleLogin), checked: LoginItem.isEnabled))
        if LoginItem.needsApproval {
            menu.addItem(action(L("Approve in Login Items Settings…"), #selector(openLoginSettings)))
        }

        menu.addItem(.separator())
        if windows.isDetectionAvailable {
            let status = NSMenuItem(title: L("Window detection: active"), action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else {
            let status = NSMenuItem(title: L("Window detection unavailable – only Dock and screen edge"),
                                    action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(action(L("Open Privacy Settings…"), #selector(openPrivacySettings)))
        }

        menu.addItem(.separator())
        menu.addItem(action(L("About Seasons"), #selector(showAbout)))
        menu.addItem(action(L("Quit Seasons"), #selector(quit), key: "q"))
    }

    private func amountMenu(current: Intensity) -> NSMenuItem {
        let parent = NSMenuItem(title: L("Amount"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (value, title) in [(Intensity.off, "Off"), (.light, "Light"), (.medium, "Medium"), (.heavy, "Heavy"),
                               (.variable, "Variable")] {
            let mi = action(L(title), #selector(selectAmount(_:)), checked: current == value)
            mi.representedObject = value.rawValue
            sub.addItem(mi)
        }
        parent.submenu = sub
        return parent
    }

    private func action(_ title: String, _ selector: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        mi.target = self
        mi.state = checked ? .on : .off
        return mi
    }

    private func seasonName(_ season: Season) -> String {
        switch season {
        case .winter: return "Winter"
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        }
    }

    // MARK: - Actions

    @objc private func selectEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let effect = EffectKind(rawValue: raw) else { return }
        // A manual choice switches the automatic mode off.
        let flowers = model.scene.flowers
        model.update {
            $0.effect = effect
            $0.flowers = flowers
            $0.automatic = false
            if $0.intensity == .off { $0.intensity = .medium }
        }
    }

    @objc private func toggleFlowers() {
        let scene = model.scene
        model.update {
            $0.effect = scene.effect ?? $0.effect
            $0.flowers = !scene.flowers
            $0.automatic = false
        }
    }

    @objc private func toggleAutomatic() { model.update { $0.automatic.toggle() } }
    @objc private func toggleSummerRain() { model.update { $0.rainInSummer.toggle() } }
    @objc private func togglePause() { model.update { $0.paused.toggle() } }
    @objc private func toggleAccumulate() { model.update { $0.accumulate.toggle() } }
    @objc private func toggleHide() { model.update { $0.hideInScreenshots.toggle() } }
    @objc private func toggleDesktopOnly() { model.update { $0.desktopOnly.toggle() } }
    @objc private func clearNow() { model.send(.clear) }
    @objc private func toggleMelt() { model.update { $0.melting.toggle() } }

    @objc private func selectAmount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Intensity(rawValue: raw) else { return }
        model.update { $0.intensity = value }
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
            if LoginItem.needsApproval { LoginItem.openSystemSettings() }
        } catch {
            log.error("login item: \(error.localizedDescription, privacy: .public)")
            showMessage(L("Launch at Login could not be changed."),
                        detail: L("Move Seasons to the Applications folder and try again, or add it in System Settings › General › Login Items."))
        }
    }

    @objc private func openLoginSettings() { LoginItem.openSystemSettings() }

    @objc private func openPrivacySettings() {
        // Asking once registers Seasons in the list so it can be switched on there.
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: L("Seasonal effects for your desktop. Built entirely with AI (Claude Code). No data leaves your Mac."),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func showMessage(_ text: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = text
        alert.informativeText = detail
        alert.runModal()
    }
}

import AppKit
import Testing
@testable import Seasons
@testable import SeasonsCore

/// Exercises the real status menu: builds it, triggers items like a click would and checks
/// that settings change and are persisted. Unbundled test runs use the English keys as titles.
/// Not clicked here: "Launch at Login" (would register the test runner as a login item),
/// "Open Privacy Settings…", "About Seasons" and "Quit Seasons".
@MainActor
@Suite("Status menu and settings", .serialized)
struct MenuTests {
    private let defaults: UserDefaults
    private let suiteName: String

    init() {
        suiteName = "SeasonsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    private func makeMenu() -> (AppModel, StatusMenuController) {
        let model = AppModel(store: SettingsStore(defaults: defaults))
        let controller = StatusMenuController(model: model, windows: WindowTracker())
        controller.menuNeedsUpdate(controller.menu)
        return (model, controller)
    }

    private func item(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        for mi in menu.items {
            if mi.title == title { return mi }
            if let sub = mi.submenu, let found = item(title, in: sub) { return found }
        }
        return nil
    }

    /// Triggers a menu item and rebuilds the menu, as reopening it would.
    private func click(_ title: String, _ controller: StatusMenuController) {
        guard let mi = item(title, in: controller.menu), let parent = mi.menu else {
            Issue.record("menu item '\(title)' not found")
            return
        }
        parent.performActionForItem(at: parent.index(of: mi))
        controller.menuNeedsUpdate(controller.menu)
    }

    private func reloaded() -> Settings { SettingsStore(defaults: defaults).load() }

    @Test("Defaults: snow, medium, piles on, hidden in screenshots")
    func defaultsAreSensible() {
        let s = SettingsStore(defaults: defaults).load()
        #expect(s == Settings())
        #expect(s.hideInScreenshots)
        #expect(s.accumulate)
        #expect(s.effect == .snow)
        #expect(s.intensity == .medium)
    }

    @Test("Settings survive a save/load round trip")
    func roundTrip() {
        let store = SettingsStore(defaults: defaults)
        var s = Settings()
        s.effect = .rain
        s.flowers = true
        s.automatic = true
        s.rainInSummer = true
        s.intensity = .variable
        s.paused = true
        s.accumulate = false
        s.hideInScreenshots = false
        s.melting = true
        store.save(s)
        #expect(store.load() == s)
    }

    @Test("Effect items select the effect, switch automatic off and persist",
          arguments: [("Autumn Leaves", EffectKind.leaves), ("Rain", .rain), ("Cherry Blossoms", .blossoms), ("Snow", .snow)])
    func selectEffect(title: String, effect: EffectKind) {
        let (model, controller) = makeMenu()
        model.update { $0.automatic = true }
        controller.menuNeedsUpdate(controller.menu)
        click(title, controller)
        #expect(model.settings.effect == effect)
        #expect(!model.settings.automatic)
        #expect(reloaded().effect == effect)
        #expect(item(title, in: controller.menu)?.state == .on)
    }

    @Test("Toggles flip their setting, show a checkmark and persist")
    func toggles() {
        let (model, controller) = makeMenu()
        click("Flowers on the Dock", controller)
        #expect(model.settings.flowers && reloaded().flowers)
        #expect(item("Flowers on the Dock", in: controller.menu)?.state == .on)

        click("Pile Up on Windows and Dock", controller)
        #expect(!model.settings.accumulate && !reloaded().accumulate)

        click("Hide in Screenshots and Screen Sharing", controller)
        #expect(!model.settings.hideInScreenshots && !reloaded().hideInScreenshots)

        click("Melt Away", controller)
        #expect(model.settings.melting && reloaded().melting)
        #expect(item("Melt Away", in: controller.menu)?.state == .on)
        click("Melt Away", controller)
        #expect(!model.settings.melting && !reloaded().melting)

        click("Choose Automatically by Season", controller)
        #expect(model.settings.automatic && reloaded().automatic)
        // The summer-rain option only appears in automatic mode.
        click("Rain in Summer", controller)
        #expect(model.settings.rainInSummer && reloaded().rainInSummer)
    }

    @Test("Pause turns into Resume and back")
    func pause() {
        let (model, controller) = makeMenu()
        click("Pause", controller)
        #expect(model.settings.paused && reloaded().paused)
        #expect(item("Resume", in: controller.menu) != nil)
        click("Resume", controller)
        #expect(!model.settings.paused && !reloaded().paused)
    }

    @Test("Amount submenu sets the intensity", arguments: [
        ("Off", Intensity.off), ("Light", .light), ("Heavy", .heavy), ("Variable", .variable), ("Medium", .medium),
    ])
    func amount(title: String, value: Intensity) {
        let (model, controller) = makeMenu()
        click(title, controller)
        #expect(model.settings.intensity == value)
        #expect(reloaded().intensity == value)
    }

    @Test("Clear Now sends a one-off command to the overlays")
    func commands() {
        let (model, controller) = makeMenu()
        var received: [String] = []
        model.onCommand { received.append("\($0)") }
        click("Clear Now", controller)
        #expect(received == ["clear"])
    }

    @Test("Automatic mode derives the scene from the season")
    func automaticScene() {
        let (model, _) = makeMenu()
        model.update { $0.automatic = true; $0.effect = .rain }
        let expected = SceneSelection.automatic(for: model.season, rainInSummer: false)
        #expect(model.scene == expected)
        model.update { $0.automatic = false }
        #expect(model.scene == SceneSelection(effect: .rain, flowers: false))
    }
}

import Foundation
import SeasonsCore

/// Commands the overlays execute once.
enum OverlayCommand {
    case clear
    case melt
}

/// Central app state: settings plus the derived scene (what is actually shown).
@MainActor
final class AppModel {
    private let store: SettingsStore
    private(set) var settings: Settings
    private(set) var season: Season
    private var seasonTimer: Timer?
    private var observers: [(Settings) -> Void] = []
    private var commandObservers: [(OverlayCommand) -> Void] = []

    init(store: SettingsStore) {
        self.store = store
        settings = store.load()
        season = Self.currentSeason()
    }

    /// Effect and flowers after applying the automatic season choice.
    var scene: SceneSelection {
        if settings.automatic {
            return SceneSelection.automatic(for: season, rainInSummer: settings.rainInSummer)
        }
        return SceneSelection(effect: settings.effect, flowers: settings.flowers)
    }

    func observe(_ handler: @escaping (Settings) -> Void) {
        observers.append(handler)
        handler(settings)
    }

    func onCommand(_ handler: @escaping (OverlayCommand) -> Void) {
        commandObservers.append(handler)
    }

    func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        store.save(next)
        observers.forEach { $0(next) }
    }

    func send(_ command: OverlayCommand) {
        commandObservers.forEach { $0(command) }
    }

    /// Re-checks the season every hour so "automatic" switches on the right day.
    func startSeasonClock() {
        seasonTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSeason() }
        }
    }

    private func refreshSeason() {
        let now = Self.currentSeason()
        guard now != season else { return }
        season = now
        observers.forEach { $0(settings) }
    }

    private static func currentSeason() -> Season {
        Season.of(month: Calendar.current.component(.month, from: Date()))
    }
}

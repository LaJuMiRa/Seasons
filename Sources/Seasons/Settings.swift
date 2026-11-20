import Foundation
import SeasonsCore

/// User settings. Value type; changes go through `AppModel.update`.
struct Settings: Equatable {
    var effect: EffectKind = .snow
    var flowers = false
    var automatic = false
    var rainInSummer = false
    var intensity: Intensity = .medium
    var paused = false
    var accumulate = true
    var hideInScreenshots = true
    /// "Melt Away" switch: while on, nothing stays lying around.
    var melting = false
    /// While on, an overlay hides while its screen shows a full-screen app.
    var desktopOnly = false
}

/// Persists `Settings` in UserDefaults. Launch-at-login is not stored here:
/// `SMAppService` is the source of truth for that.
struct SettingsStore {
    private let defaults: UserDefaults
    private enum Key {
        static let effect = "effect"
        static let flowers = "flowers"
        static let automatic = "automatic"
        static let rainInSummer = "rainInSummer"
        static let intensity = "intensity"
        static let paused = "paused"
        static let accumulate = "accumulate"
        static let hideInScreenshots = "hideInScreenshots"
        static let melting = "melting"
        static let desktopOnly = "desktopOnly"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Settings {
        var s = Settings()
        if let raw = defaults.string(forKey: Key.effect), let e = EffectKind(rawValue: raw) { s.effect = e }
        if let raw = defaults.string(forKey: Key.intensity), let i = Intensity(rawValue: raw) { s.intensity = i }
        s.flowers = bool(Key.flowers, default: s.flowers)
        s.automatic = bool(Key.automatic, default: s.automatic)
        s.rainInSummer = bool(Key.rainInSummer, default: s.rainInSummer)
        s.paused = bool(Key.paused, default: s.paused)
        s.accumulate = bool(Key.accumulate, default: s.accumulate)
        s.hideInScreenshots = bool(Key.hideInScreenshots, default: s.hideInScreenshots)
        s.melting = bool(Key.melting, default: s.melting)
        s.desktopOnly = bool(Key.desktopOnly, default: s.desktopOnly)
        return s
    }

    func save(_ s: Settings) {
        defaults.set(s.effect.rawValue, forKey: Key.effect)
        defaults.set(s.intensity.rawValue, forKey: Key.intensity)
        defaults.set(s.flowers, forKey: Key.flowers)
        defaults.set(s.automatic, forKey: Key.automatic)
        defaults.set(s.rainInSummer, forKey: Key.rainInSummer)
        defaults.set(s.paused, forKey: Key.paused)
        defaults.set(s.accumulate, forKey: Key.accumulate)
        defaults.set(s.hideInScreenshots, forKey: Key.hideInScreenshots)
        defaults.set(s.melting, forKey: Key.melting)
        defaults.set(s.desktopOnly, forKey: Key.desktopOnly)
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }
}

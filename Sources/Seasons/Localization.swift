import Foundation

/// Looks up a localized string. Keys are the English texts; `de.lproj` holds the German ones.
/// Unbundled builds (`swift run`) have no .lproj folders and fall back to the English key.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

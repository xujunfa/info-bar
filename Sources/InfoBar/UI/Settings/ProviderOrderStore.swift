import Foundation

public final class ProviderOrderStore {
    private let defaults: UserDefaults
    private let key = "InfoBar.providerOrder"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns stored order if it exactly matches the set of defaultIDs; otherwise returns defaultIDs.
    public func orderedIDs(defaultIDs: [String]) -> [String] {
        guard let raw = defaults.object(forKey: key),
              let stored = raw as? [String],
              !stored.isEmpty,
              Set(stored) == Set(defaultIDs) else {
            return defaultIDs
        }
        return stored
    }

    public func setOrder(_ ids: [String]) {
        defaults.set(ids, forKey: key)
    }
}

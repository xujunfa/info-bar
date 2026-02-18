import Foundation

public final class ProviderVisibilityStore {
    private let defaults: UserDefaults
    private let key = "InfoBar.providerVisibility"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isVisible(providerID: String) -> Bool {
        guard let raw = defaults.object(forKey: key),
              let dict = raw as? [String: Bool] else {
            return true // invalid or missing → default visible
        }
        return dict[providerID] ?? true
    }

    public func setVisible(_ visible: Bool, providerID: String) {
        var dict = (defaults.object(forKey: key) as? [String: Bool]) ?? [:]
        dict[providerID] = visible
        defaults.set(dict, forKey: key)
    }
}

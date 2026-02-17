import Foundation

@MainActor
public final class Store {
    public static let shared = Store()

    private init() {}

    public func bool(key: String, defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    public func set(key: String, value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

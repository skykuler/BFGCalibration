import Foundation

/// Stores vehicle identity only. Passwords remain in the injected credential store.
public final class PairedVehicleStore {
    private let defaults: UserDefaults
    private let serialsKey = "bfg.paired-vehicles.v1"
    private let selectedKey = "bfg.selected-vehicle.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public static func normalizedSerial(_ value: String) -> String? {
        let serial = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard serial.range(of: "^[A-Z0-9]{14}$", options: .regularExpression) != nil else { return nil }
        return serial
    }

    public var serials: [String] {
        Array(Set((defaults.stringArray(forKey: serialsKey) ?? [])
            .compactMap(Self.normalizedSerial))).sorted()
    }

    public var selectedSerial: String? {
        guard let value = defaults.string(forKey: selectedKey), serials.contains(value) else { return nil }
        return value
    }

    /// Reconciles metadata against passwords actually available on this device.
    /// Also migrates credentials saved by earlier versions without metadata.
    public func reconcile(availableSerials: [String]) {
        let available = Array(Set(availableSerials.compactMap(Self.normalizedSerial))).sorted()
        defaults.set(available, forKey: serialsKey)
        if let selected = defaults.string(forKey: selectedKey), available.contains(selected) { return }
        if let first = available.first { defaults.set(first, forKey: selectedKey) }
        else { defaults.removeObject(forKey: selectedKey) }
    }

    @discardableResult
    public func select(_ value: String) -> Bool {
        guard let serial = Self.normalizedSerial(value), serials.contains(serial) else { return false }
        defaults.set(serial, forKey: selectedKey)
        return true
    }

    public func clear() {
        defaults.removeObject(forKey: serialsKey)
        defaults.removeObject(forKey: selectedKey)
    }
}

import Foundation

/// Original Android write restrictions. No expert mode or serial waiver.
public enum WriteAccessPolicy {
    public static func isReadOnlySerial(_ serial: String?) -> Bool {
        serial?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("N") ?? false
    }
    public static func needsMeterCompatibilityWarning(_ rawVersion: Int) -> Bool {
        rawVersion != 0x0286 && rawVersion != 0x0429
    }
    public static func riskGateSeconds(isDashboard: Bool) -> Int {
        isDashboard ? TimedRiskGate.dashboardSeconds : TimedRiskGate.meterSeconds
    }
}

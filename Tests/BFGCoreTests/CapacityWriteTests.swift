import XCTest
@testable import BFGCore

/// Capacity selection uses the original profile byte, never an independent 0x0E write.
final class CapacityProfileWriteTests: XCTestCase {
    func testOriginalProfileWriteHasExactlyOnePayloadByteAtIndexZero() {
        for value in [0x00, 0x51, 0x52, 0xD0, 0xF2] {
            let frame = NinebotFrame.writeProfile(value)
            XCTAssertEqual(frame, [0x5A, 0xA5, 1, 0x3E, 0x10, 2, 0, UInt8(value)])
        }
    }
    func testCapacityBackupLegacySlotsAreAlsoCleared() {
        let name = "legacy-clear-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let serial = "A1234567890123"
        defaults.set(26000, forKey: serial + "_rated_capacity")
        defaults.set(55000, forKey: serial + "_prewrite_rated_capacity")
        BackupStore(defaults: defaults).clear(serial: serial)
        XCTAssertNil(defaults.object(forKey: serial + "_rated_capacity"))
        XCTAssertNil(defaults.object(forKey: serial + "_prewrite_rated_capacity"))
    }
}

import XCTest
@testable import BFGCore

/// The release no longer exposes experimental policy overrides.
final class OriginalWriteScopeTests: XCTestCase {
    func testOriginalSerialRestrictionCannotBeWaived() {
        XCTAssertTrue(WriteAccessPolicy.isReadOnlySerial("N1234567890123"))
        XCTAssertTrue(WriteAccessPolicy.isReadOnlySerial(" n1234567890123 "))
        XCTAssertFalse(WriteAccessPolicy.isReadOnlySerial("B1234567890123"))
    }
    func testOriginalGateTimesAndCompatibilityWarningRemain() {
        XCTAssertEqual(WriteAccessPolicy.riskGateSeconds(isDashboard: false), 3)
        XCTAssertEqual(WriteAccessPolicy.riskGateSeconds(isDashboard: true), 30)
        XCTAssertFalse(WriteAccessPolicy.needsMeterCompatibilityWarning(0x0286))
        XCTAssertFalse(WriteAccessPolicy.needsMeterCompatibilityWarning(0x0429))
        XCTAssertTrue(WriteAccessPolicy.needsMeterCompatibilityWarning(0x0426))
    }
}

import XCTest
@testable import BFGCore
import BFGSimulator

final class Regression220Tests: XCTestCase {
    private func wire(_ payload: Int) -> [UInt8] {
        [0x5A, 0xA5, UInt8(payload)] + [UInt8](repeating: 0x11, count: payload + 10)
    }
    func testEverySingleSplitPositionReassemblesOneFrame() {
        let frame = wire(30)
        for split in 1..<frame.count {
            var buffer = BleFrameBuffer()
            XCTAssertTrue(buffer.accept(Data(frame.prefix(split))).isEmpty)
            XCTAssertEqual(buffer.accept(Data(frame.dropFirst(split))), [frame], "split=\(split)")
            XCTAssertEqual(buffer.pendingBytes, 0)
        }
    }
    func testCoalescedFramesAndNoiseAndHeaderSplit() {
        let first = wire(0), second = wire(2)
        var buffer = BleFrameBuffer()
        XCTAssertTrue(buffer.accept(Data([1, 2, 0x5A])).isEmpty)
        XCTAssertEqual(buffer.accept(Data(Array(first.dropFirst()) + second)), [first, second])
        XCTAssertEqual(buffer.pendingBytes, 0)
    }
    func testMalformedInputHasABoundedBuffer() {
        var buffer = BleFrameBuffer()
        for _ in 0..<100 { _ = buffer.accept(Data(repeating: 0x31, count: 8000)) }
        XCTAssertLessThanOrEqual(buffer.pendingBytes, 268)
        XCTAssertEqual(buffer.accept(Data(wire(0))), [wire(0)])
    }
    func testPairingPasswordsAndAuthenticationEchoesAreRedacted() {
        let secret = String(repeating: "AB", count: 32)
        for command in ["5B", "5C", "5D"] {
            let line = "TX plain=5AA5203E04\(command)00\(secret)"
            let sanitized = ProtocolLogSanitizer.sanitize(line)
            XCTAssertFalse(sanitized.contains(secret))
            XCTAssertTrue(sanitized.contains("authentication-payload-hidden"))
        }
        XCTAssertEqual(ProtocolLogSanitizer.sanitize("TX plain=5AA5013E10020051"), "TX plain=5AA5013E10020051")
    }
    func testPairedSelectionSurvivesRelaunchAndMigratesKnownCredentials() {
        let suite = "paired-vehicle-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = "A1234567890123", b = "B1234567890123"
        let store = PairedVehicleStore(defaults: defaults)
        store.reconcile(availableSerials: [a, b, b.lowercased(), "invalid"])
        XCTAssertTrue(store.select(b))
        let reopened = PairedVehicleStore(defaults: defaults)
        XCTAssertEqual(reopened.selectedSerial, b)
        XCTAssertEqual(reopened.serials, [a, b])
        reopened.reconcile(availableSerials: [a])
        XCTAssertEqual(reopened.selectedSerial, a)
        reopened.clear()
        XCTAssertNil(reopened.selectedSerial)
        XCTAssertTrue(reopened.serials.isEmpty)
    }
    func testPrewriteSnapshotIsRecoverableAndInvalidIdentityIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RegisterDumpStore(directory: directory)
        let dump = RegisterDump(serial: "A1234567890123",
            fingerprint: .init(dashboard: 1, colorDisplay: 2, centre: 3, meter: 4),
            timestamp: 1000, entries: [.init(module: 0x10, index: 0, length: 1, value: 0x51, stable: true, responded: true)])
        let saved = try store.savePrewrite(dump)
        XCTAssertEqual(try RegisterDump.decode(Data(contentsOf: saved)), dump)
        let bad = RegisterDump(serial: "../../other", fingerprint: dump.fingerprint, timestamp: 1000, entries: [])
        XCTAssertThrowsError(try store.savePrewrite(bad))
    }
    func testPairingWorksWithFragmentedNotificationsAndLogsContainNoPassword() {
        var config = VirtualVehicle.Config()
        config.hasStoredPassword = false
        let vehicle = VirtualVehicle(config: config), store = InMemoryCredentialStore()
        let link = VirtualLink(vehicle: vehicle, notificationChunkSize: 5)
        let listener = RegressionRecorder()
        let client = BfgBleClient(record: record(config.serial), operation: .pairAndRead,
            transport: link, credentialStore: store, listener: listener)
        client.start()
        XCTAssertEqual(listener.done.wait(timeout: .now() + 15), .success)
        XCTAssertNil(listener.failure)
        XCTAssertNotNil(listener.result)
        if let password = store.load(serial: config.serial) {
            XCTAssertFalse(listener.logs.contains(Hex.encode(password)))
        } else { XCTFail("Pairing did not persist its credential") }
        client.cancel()
    }
    func testInvalidPairingMacCannotSaveCredentials() {
        var config = VirtualVehicle.Config(); config.hasStoredPassword = false
        let vehicle = VirtualVehicle(config: config), store = InMemoryCredentialStore()
        let link = VirtualLink(vehicle: vehicle, corruptPairConfirmation: true)
        let listener = RegressionRecorder()
        let client = BfgBleClient(record: record(config.serial), operation: .pairAndRead,
            transport: link, credentialStore: store, listener: listener)
        client.start()
        XCTAssertEqual(listener.done.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(listener.failure?.contains("校验") == true)
        XCTAssertNil(store.load(serial: config.serial))
        client.cancel()
    }
    func testFirstPassTimeoutDoesNotBecomeAStableBackup() {
        var config = VirtualVehicle.Config()
        let password = [UInt8](repeating: 7, count: 32)
        config.storedPassword32 = password
        config.silentFirstRead = [VirtualVehicle.Register(0x10, 0x00)]
        let vehicle = VirtualVehicle(config: config), store = InMemoryCredentialStore()
        _ = store.save(serial: config.serial, password32: password)
        let link = VirtualLink(vehicle: vehicle, notificationChunkSize: 7)
        let listener = RegressionRecorder()
        let client = BfgBleClient(record: record(config.serial), operation: .dumpRegisters,
            dumpModules: [0x10], transport: link, credentialStore: store, listener: listener)
        client.start()
        XCTAssertEqual(listener.done.wait(timeout: .now() + 60), .success)
        XCTAssertNil(listener.failure)
        let entry = listener.result?.registerDump?.entry(module: 0x10, index: 0x00)
        XCTAssertEqual(entry?.responded, true)
        XCTAssertEqual(entry?.value, 0x51)
        XCTAssertEqual(entry?.stable, false, "A single successful read cannot verify a two-pass backup")
        client.cancel()
    }

    private func record(_ serial: String) -> DeviceRecord {
        DeviceRecord(id: -1, mac: "", sn: serial, name: serial, deviceType: "",
            password16: [UInt8](repeating: 0, count: 16), source: "regression")
    }
}

private final class RegressionRecorder: BfgBleClient.Listener {
    let done = DispatchSemaphore(value: 0)
    private(set) var result: BfgBleClient.Result?
    private(set) var failure: String?
    private(set) var logs = ""
    func bleClient(didUpdateStatus status: String) { }
    func bleClient(didLog line: String) { logs += line + "\n" }
    func bleClient(didFinish result: BfgBleClient.Result) { self.result = result; done.signal() }
    func bleClient(didFailWith message: String) { failure = message; done.signal() }
}

import Foundation
import BFGCore
import CoreBluetooth

// Executes the actual iOS adapter against a deterministic CoreBluetooth stub.
// It does not claim radio, iOS runtime, or iPhone performance validation.
var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: " + label) }
    passed += 1
    print("PASS: " + label)
}
final class RadioPeripheral: CBPeripheral {
    var ready = false
    var readinessReads = 0
    var writes: [Data] = []
    override var canSendWriteWithoutResponse: Bool {
        get { readinessReads += 1; return ready }
        set { ready = newValue }
    }
    override func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writes.append(data)
    }
}
final class RadioSpy: BleTransportDelegate {
    var notifications: [Data] = []
    var errors = 0
    var states: [Bool] = []
    func bleTransportDidUpdateState(poweredOn: Bool) { states.append(poweredOn) }
    func bleTransport(didDiscover identifier: String, name: String) { }
    func bleTransportDidConnect() { }
    func bleTransport(didDisconnect error: Error?) { }
    func bleTransport(didDiscoverServices error: Error?) { if error != nil { errors += 1 } }
    func bleTransport(didUpdateNotificationState error: Error?) { if error != nil { errors += 1 } }
    func bleTransport(didReceive data: Data) { notifications.append(data) }
    func bleTransport(didWrite error: Error?) { if error != nil { errors += 1 } }
}
func connected(_ properties: CBCharacteristicProperties) -> (CoreBluetoothTransport, CBCentralManager, RadioPeripheral, CBCharacteristic, CBCharacteristic, RadioSpy) {
    let transport = CoreBluetoothTransport()
    let central = CBCentralManager.lastCreated!
    let item = RadioPeripheral(), spy = RadioSpy()
    let service = CBService(), tx = CBCharacteristic(), rx = CBCharacteristic()
    transport.delegate = spy
    item.name = "A1234567890123"
    service.uuid = CoreBluetoothTransport.serviceUUID
    tx.uuid = CoreBluetoothTransport.txUUID; tx.properties = properties
    rx.uuid = CoreBluetoothTransport.rxUUID; rx.properties = [.notify]
    service.characteristics = [tx, rx]; item.services = [service]
    central.performAndWait {
        central.state = .poweredOn
        central.delegate?.centralManagerDidUpdateState(central)
        central.delegate?.centralManager(central, didDiscover: item, advertisementData: [:], rssi: -30)
    }
    transport.connect(identifier: item.identifier.uuidString)
    central.performAndWait {
        central.delegate?.centralManager(central, didConnect: item)
        item.delegate?.peripheral(item, didDiscoverServices: nil)
        item.delegate?.peripheral(item, didDiscoverCharacteristicsFor: service, error: nil)
        rx.isNotifying = true
        item.delegate?.peripheral(item, didUpdateNotificationStateFor: rx, error: nil)
    }
    return (transport, central, item, tx, rx, spy)
}

do {
    let (transport, central, item, _, rx, spy) = connected([.writeWithoutResponse])
    let payload = Data((0..<45).map { UInt8($0) })
    transport.write(payload)
    central.performAndWait { check(item.writes.isEmpty, "blocked radio does not transmit") }
    let reads = item.readinessReads
    Thread.sleep(forTimeInterval: 0.12)
    central.performAndWait { check(item.readinessReads == reads, "blocked radio has no 20ms polling wakeups") }
    central.performAndWait {
        item.ready = true
        item.delegate?.peripheralIsReady(toSendWriteWithoutResponse: item)
        check(item.writes.map(\.count) == [20,20,5], "readiness event drains negotiated chunks")
        check(Data(item.writes.flatMap { [UInt8]($0) }) == payload, "chunks preserve frame bytes and order")
        rx.value = Data([1,2,3])
        let stale = RadioPeripheral()
        item.delegate?.peripheral(stale, didUpdateValueFor: rx, error: nil)
        check(spy.notifications.isEmpty, "stale peripheral notifications are ignored")
        item.delegate?.peripheral(item, didUpdateValueFor: rx, error: nil)
        check(spy.notifications == [Data([1,2,3])], "active RX notification reaches the client")
        rx.isNotifying = false
        item.delegate?.peripheral(item, didUpdateNotificationStateFor: rx, error: nil)
        check(spy.errors == 1, "inactive notify is not reported as ready")
    }
    transport.disconnect()
    central.performAndWait {
        item.delegate?.peripheral(item, didUpdateValueFor: rx, error: nil)
        check(spy.notifications.count == 1, "disconnect prevents late RX delivery")
    }
}
do {
    let (transport, central, item, tx, _, _) = connected([.write])
    transport.write(Data(repeating: 9, count: 45))
    central.performAndWait {
        check(item.writes.count == 1, "acknowledged writes allow one chunk in flight")
        item.delegate?.peripheral(RadioPeripheral(), didWriteValueFor: tx, error: nil)
        check(item.writes.count == 1, "stale ACK cannot advance TX")
        item.delegate?.peripheral(item, didWriteValueFor: tx, error: nil)
        check(item.writes.count == 2, "first ACK advances one chunk")
        item.delegate?.peripheral(item, didWriteValueFor: tx, error: nil)
        check(item.writes.count == 3, "second ACK advances the final chunk")
        item.delegate?.peripheral(item, didWriteValueFor: tx, error: nil)
    }
    transport.disconnect()
    central.performAndWait { }
}
print("Transport adapter regression: \(passed) passed, 0 failed")

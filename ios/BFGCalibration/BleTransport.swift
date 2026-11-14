import Foundation
import CoreBluetooth
import BFGCore

/// The radio adapter; all mutable state belongs to one serial queue.
final class CoreBluetoothTransport: NSObject, BFGCore.BleTransport {
    static let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    static let txUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    static let rxUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    weak var delegate: BleTransportDelegate?
    private let queue = DispatchQueue(label: "com.bfgtools.calibration.ble")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var scanned: [String: CBPeripheral] = [:]
    private var txCharacteristic: CBCharacteristic?
    private var writeType: BleWriteType?
    private var poweredOn = false
    private var connected = false
    private var pending: [Data] = []
    private var pendingIndex = 0
    private var writeInFlight = false
    private var discoveryRetry: DispatchWorkItem?
    private var servicesDiscovered = false
    private var discoveryAttempts = 0

    override init() {
        super.init()
        queue.setSpecific(key: queueKey, value: true)
        central = CBCentralManager(delegate: self, queue: queue)
    }
    var isPoweredOn: Bool {
        if DispatchQueue.getSpecific(key: queueKey) == true { return poweredOn }
        return queue.sync { poweredOn }
    }
    private func log(_ text: String) { delegate?.bleTransport(log: text) }
    func startScan() {
        queue.async { [weak self] in
            guard let self, self.central.state == .poweredOn else { return }
            self.scanned.removeAll()
            for item in self.central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]) {
                self.scanned[item.identifier.uuidString] = item
                self.delegate?.bleTransport(didDiscover: item.identifier.uuidString, name: item.name ?? "")
            }
            self.central.scanForPeripherals(withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    func stopScan() { queue.async { self.central.stopScan() } }
    func connect(identifier: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let item = self.scanned[identifier] else {
                self.delegate?.bleTransport(didDisconnect: BleError.deviceNotFound)
                return
            }
            self.peripheral = item
            self.servicesDiscovered = false
            self.discoveryAttempts = 0
            item.delegate = self
            self.central.connect(item, options: nil)
        }
    }
    func disconnect() {
        // Retain until teardown executes even if the client has been released.
        queue.async {
            self.central.stopScan()
            if let item = self.peripheral { self.central.cancelPeripheralConnection(item) }
            self.resetConnection()
            self.peripheral = nil
        }
    }
    private func resetConnection() {
        connected = false
        txCharacteristic = nil
        writeType = nil
        pending.removeAll()
        pendingIndex = 0
        writeInFlight = false
        servicesDiscovered = false
        discoveryAttempts = 0
        discoveryRetry?.cancel()
        discoveryRetry = nil
    }
    private func discoverServices() {
        guard connected, let item = peripheral else { return }
        discoveryAttempts += 1
        log("BLE_DISCOVER_SERVICES attempt=\(discoveryAttempts)")
        item.discoverServices(nil)
        discoveryRetry?.cancel()
        let retry = DispatchWorkItem { [weak self, weak item] in
            guard let self, let item, self.peripheral === item, self.connected,
                  !self.servicesDiscovered, self.discoveryAttempts < 3 else { return }
            self.discoverServices()
        }
        discoveryRetry = retry
        queue.asyncAfter(deadline: .now() + 3, execute: retry)
    }
    func write(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.connected, let item = self.peripheral, self.txCharacteristic != nil,
                  let type = self.writeType else {
                self.delegate?.bleTransport(didWrite: BleError.txNotReady)
                return
            }
            let systemType: CBCharacteristicWriteType = type == .withResponse ? .withResponse : .withoutResponse
            let limit = max(1, item.maximumWriteValueLength(for: systemType))
            let chunks = (data.count + limit - 1) / limit
            guard self.pending.count - self.pendingIndex + chunks <= 128 else {
                self.delegate?.bleTransport(didWrite: BleError.txNotReady)
                return
            }
            if self.pendingIndex == self.pending.count {
                self.pending.removeAll(keepingCapacity: true)
                self.pendingIndex = 0
            }
            var offset = 0
            while offset < data.count {
                let end = min(offset + limit, data.count)
                self.pending.append(data.subdata(in: offset..<end))
                offset = end
            }
            self.pump()
        }
    }
    private func pump() {
        guard connected, let item = peripheral, let tx = txCharacteristic, let type = writeType else { return }
        while pendingIndex < pending.count {
            if type == .withResponse {
                guard !writeInFlight else { return }
                writeInFlight = true
            } else {
                // CoreBluetooth wakes us through peripheralIsReady. No polling timer.
                guard item.canSendWriteWithoutResponse else { return }
            }
            let chunk = pending[pendingIndex]
            pendingIndex += 1
            log("BLE_TX len=\(chunk.count) type=\(type.label)")
            item.writeValue(chunk, for: tx, type: type == .withResponse ? .withResponse : .withoutResponse)
        }
        if !writeInFlight {
            pending.removeAll(keepingCapacity: true)
            pendingIndex = 0
        }
    }
}

extension CoreBluetoothTransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        poweredOn = central.state == .poweredOn
        log("BLE_STATE poweredOn=\(poweredOn) raw=\(central.state.rawValue)")
        if central.state == .unknown || central.state == .resetting { return }
        delegate?.bleTransportDidUpdateState(poweredOn: poweredOn)
    }
    func centralManager(_ central: CBCentralManager, didDiscover item: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? item.name ?? ""
        scanned[item.identifier.uuidString] = item
        log("BLE_DISCOVER name=\(name) rssi=\(RSSI)")
        delegate?.bleTransport(didDiscover: item.identifier.uuidString, name: name)
    }
    func centralManager(_ central: CBCentralManager, didConnect item: CBPeripheral) {
        guard peripheral === item else { return }
        connected = true
        log("BLE_CONNECTED")
        delegate?.bleTransportDidConnect()
        discoverServices()
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect item: CBPeripheral, error: Error?) {
        guard peripheral === item else { return }
        resetConnection()
        delegate?.bleTransport(didDisconnect: error ?? BleError.deviceNotFound)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral item: CBPeripheral, error: Error?) {
        guard peripheral === item else { return }
        resetConnection()
        log("BLE_DISCONNECTED")
        delegate?.bleTransport(didDisconnect: error)
    }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
    func peripheral(_ item: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === item, connected, !servicesDiscovered else { return }
        servicesDiscovered = true
        discoveryRetry?.cancel()
        guard error == nil else {
            delegate?.bleTransport(didDiscoverServices: error)
            return
        }
        let uuids = (item.services ?? []).map { $0.uuid.uuidString }
        log("BLE_SERVICES \(uuids.joined(separator: ","))")
        guard let service = item.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            delegate?.bleTransport(didDiscoverServices: BleError.serviceNotFound)
            return
        }
        delegate?.bleTransport(didDiscoverServices: nil)
        item.discoverCharacteristics(nil, for: service)
    }
    func peripheral(_ item: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === item, connected, txCharacteristic == nil, service.uuid == Self.serviceUUID else { return }
        guard error == nil else {
            delegate?.bleTransport(didDiscoverServices: error)
            return
        }
        guard let tx = service.characteristics?.first(where: { $0.uuid == Self.txUUID }),
              let rx = service.characteristics?.first(where: { $0.uuid == Self.rxUUID }) else {
            delegate?.bleTransport(didWrite: BleError.characteristicNotFound)
            return
        }
        writeType = BleWritePolicy.writeType(supportsWrite: tx.properties.contains(.write),
            supportsWriteWithoutResponse: tx.properties.contains(.writeWithoutResponse))
        guard let type = writeType else {
            delegate?.bleTransport(didWrite: BleError.writeNotPermitted)
            return
        }
        txCharacteristic = tx
        log("BLE_CHARS props=\(tx.properties.rawValue) chosen=\(type.label) "
            + "limit=\(item.maximumWriteValueLength(for: type == .withResponse ? .withResponse : .withoutResponse))")
        item.setNotifyValue(true, for: rx)
    }
    func peripheral(_ item: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === item, connected, characteristic.uuid == Self.rxUUID else { return }
        log("BLE_NOTIFY \(characteristic.isNotifying)")
        delegate?.bleTransport(didUpdateNotificationState: error ?? (characteristic.isNotifying ? nil : BleError.txNotReady))
    }
    func peripheral(_ item: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === item, connected, characteristic.uuid == Self.rxUUID else { return }
        guard error == nil, let data = characteristic.value else { return }
        log("BLE_RX len=\(data.count)")
        delegate?.bleTransport(didReceive: data)
    }
    func peripheral(_ item: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === item, connected, characteristic.uuid == Self.txUUID, writeInFlight else { return }
        writeInFlight = false
        if error != nil { pending.removeAll(); pendingIndex = 0 }
        else { pump() }
        delegate?.bleTransport(didWrite: error)
    }
    func peripheralIsReady(toSendWriteWithoutResponse item: CBPeripheral) {
        guard peripheral === item, connected else { return }
        pump()
    }
}

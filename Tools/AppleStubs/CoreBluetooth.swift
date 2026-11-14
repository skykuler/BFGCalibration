// Type-checking stub for CoreBluetooth. See Tools/typecheck-ios.sh.
import Foundation

open class CBUUID: NSObject {
    public let uuidString: String
    public init(string: String) { uuidString = string.uppercased(); super.init() }
    public init(data: Data) { uuidString = data.map { String(format: "%02X", $0) }.joined(); super.init() }
    open override func isEqual(_ object: Any?) -> Bool { (object as? CBUUID)?.uuidString == uuidString }
    open override var hash: Int { uuidString.hashValue }
}

open class CBPeer: NSObject {}

open class CBService: NSObject {
    open var uuid: CBUUID = CBUUID(string: "")
    open var characteristics: [CBCharacteristic]?
}

public struct CBCharacteristicProperties: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let broadcast = CBCharacteristicProperties(rawValue: 0x01)
    public static let read = CBCharacteristicProperties(rawValue: 0x02)
    public static let writeWithoutResponse = CBCharacteristicProperties(rawValue: 0x04)
    public static let write = CBCharacteristicProperties(rawValue: 0x08)
    public static let notify = CBCharacteristicProperties(rawValue: 0x10)
    public static let indicate = CBCharacteristicProperties(rawValue: 0x20)
    public static let authenticatedSignedWrites = CBCharacteristicProperties(rawValue: 0x40)
    public static let extendedProperties = CBCharacteristicProperties(rawValue: 0x80)
}

open class CBCharacteristic: NSObject {
    open var uuid: CBUUID = CBUUID(string: "")
    open var value: Data?
    /// What the characteristic permits. The transport picks its write type from
    /// this instead of assuming one, so the stub has to model it.
    open var properties: CBCharacteristicProperties = []
    open var isNotifying: Bool = false
}

public enum CBManagerState: Int, Sendable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

public enum CBCharacteristicWriteType: Int, Sendable {
    case withResponse, withoutResponse
}

open class CBPeripheral: CBPeer {
    open var identifier: UUID = UUID()
    open var name: String?
    open weak var delegate: CBPeripheralDelegate?
    open var services: [CBService]?
    /// Whether a without-response write fits in the radio's buffer right now.
    open var canSendWriteWithoutResponse: Bool = true

    open func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    open func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {}
    open func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {}
    open func readValue(for characteristic: CBCharacteristic) {}
    open func writeValue(_ data: Data, for characteristic: CBCharacteristic,
                         type: CBCharacteristicWriteType) {}
    open func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int { 20 }
}

open class CBCentralManager: NSObject {
    open var state: CBManagerState = .unknown

    public static var lastCreated: CBCentralManager?
    public weak var delegate: CBCentralManagerDelegate?
    private let callbackQueue: DispatchQueue
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) {
        self.delegate = delegate
        callbackQueue = queue ?? DispatchQueue(label: "stub-central")
        super.init()
        Self.lastCreated = self
    }
    public func performAndWait(_ body: () -> Void) { callbackQueue.sync(execute: body) }
    open func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [CBPeripheral] { [] }
    open func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?,
                                 options: [String: Any]?) {}
    open func stopScan() {}
    open func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {}
    open func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
    open func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { [] }
}

public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?)
}

public protocol CBPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?)
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?)
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)
}

public let CBAdvertisementDataLocalNameKey = "kCBAdvDataLocalName"
public let CBCentralManagerScanOptionAllowDuplicatesKey = "kCBScanOptionAllowDuplicates"

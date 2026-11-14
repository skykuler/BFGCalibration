import Foundation

/// Durable pre-write evidence. Call on the host's serial I/O queue.
public struct RegisterDumpStore {
    public enum Failure: Error { case invalidSerial, verificationFailed }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func savePrewrite(_ dump: RegisterDump) throws -> URL {
        guard let serial = PairedVehicleStore.normalizedSerial(dump.serial) else { throw Failure.invalidSerial }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("bfg-prewrite-\(serial).json")
        try dump.json().write(to: url, options: .atomic)
        guard try RegisterDump.decode(Data(contentsOf: url)) == dump else { throw Failure.verificationFailed }
        return url
    }
}

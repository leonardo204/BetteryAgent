import Foundation
import IOKit

// MARK: - Types

public typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8)

public typealias FourCharCode = UInt32

extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)
        self = str.utf8.reduce(0) { sum, char in sum << 8 | UInt32(char) }
    }

    func toString() -> String {
        String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
        String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
        String(describing: UnicodeScalar(self >> 8  & 0xff)!) +
        String(describing: UnicodeScalar(self       & 0xff)!)
    }
}

// MARK: - SMCParamStruct (80 bytes)

struct SMCParamStruct {
    enum Selector: UInt8 {
        case handleYPCEvent  = 2
        case readKey         = 5
        case writeKey        = 6
        case getKeyFromIndex = 8
        case getKeyInfo      = 9
    }

    struct Version {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                           0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

// MARK: - SMCController

enum SMCError: Error, LocalizedError {
    case driverNotFound
    case failedToOpen
    case keyNotFound(String)
    case notPrivileged
    case callFailed(kern_return_t, UInt8)

    var errorDescription: String? {
        switch self {
        case .driverNotFound: return "AppleSMC driver not found"
        case .failedToOpen: return "Failed to open SMC connection"
        case .keyNotFound(let k): return "SMC key '\(k)' not found"
        case .notPrivileged: return "Root privileges required"
        case .callFailed(let io, let smc): return "SMC call failed (IOReturn=\(io), SMC=\(smc))"
        }
    }
}

final class SMCController {
    private var connection: io_connect_t = 0
    private var isTahoe = false

    init() {
        let size = MemoryLayout<SMCParamStruct>.stride
        fputs("INFO: SMCParamStruct size = \(size) bytes (expected 80)\n", stderr)
    }

    func open() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { throw SMCError.driverNotFound }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else { throw SMCError.failedToOpen }

        // Detect firmware type: try Tahoe key first
        isTahoe = keyExists("CHTE")
        fputs("INFO: Firmware type: \(isTahoe ? "Tahoe" : "Legacy")\n", stderr)
    }

    func close() {
        IOServiceClose(connection)
    }

    func keyExists(_ key: String) -> Bool {
        do {
            _ = try getKeyInfo(key)
            return true
        } catch {
            return false
        }
    }

    private func callDriver(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        let inSize = MemoryLayout<SMCParamStruct>.stride
        var outSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCParamStruct.Selector.handleYPCEvent.rawValue),
            &input, inSize,
            &output, &outSize
        )

        if result == kIOReturnNotPrivileged { throw SMCError.notPrivileged }
        guard result == kIOReturnSuccess, output.result == 0 else {
            if output.result == 132 {
                throw SMCError.keyNotFound(input.key.toString())
            }
            throw SMCError.callFailed(result, output.result)
        }
        return output
    }

    func getKeyInfo(_ key: String) throws -> (dataSize: UInt32, dataType: UInt32) {
        var input = SMCParamStruct()
        input.key = FourCharCode(fromString: key)
        input.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue
        let output = try callDriver(&input)
        return (UInt32(output.keyInfo.dataSize), output.keyInfo.dataType)
    }

    func readKey(_ key: String) throws -> [UInt8] {
        let info = try getKeyInfo(key)
        var input = SMCParamStruct()
        input.key = FourCharCode(fromString: key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCParamStruct.Selector.readKey.rawValue
        let output = try callDriver(&input)

        let mirror = Mirror(reflecting: output.bytes)
        let all = mirror.children.map { $0.value as! UInt8 }
        return Array(all.prefix(Int(info.dataSize)))
    }

    func writeKey(_ key: String, data: [UInt8]) throws {
        let info = try getKeyInfo(key)
        var input = SMCParamStruct()
        input.key = FourCharCode(fromString: key)
        input.data8 = SMCParamStruct.Selector.writeKey.rawValue
        input.keyInfo.dataSize = info.dataSize

        var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutablePointer(to: &bytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 32) { bytePtr in
                for i in 0..<min(data.count, 32) {
                    bytePtr[i] = data[i]
                }
            }
        }
        input.bytes = bytes
        _ = try callDriver(&input)
    }

    // MARK: - Charging Control (auto-detect firmware)

    func disableCharging() throws {
        if isTahoe {
            fputs("INFO: Disabling charging via CHTE (Tahoe)\n", stderr)
            try writeKey("CHTE", data: [0x01, 0x00, 0x00, 0x00])
        } else {
            fputs("INFO: Disabling charging via CH0B+CH0C (Legacy)\n", stderr)
            try writeKey("CH0B", data: [0x02])
            try writeKey("CH0C", data: [0x02])
        }
    }

    func enableCharging() throws {
        if isTahoe {
            fputs("INFO: Enabling charging via CHTE (Tahoe)\n", stderr)
            try writeKey("CHTE", data: [0x00, 0x00, 0x00, 0x00])
        } else {
            fputs("INFO: Enabling charging via CH0B+CH0C (Legacy)\n", stderr)
            try writeKey("CH0B", data: [0x00])
            try writeKey("CH0C", data: [0x00])
        }
    }

    func enableForceDischarge() throws {
        if isTahoe {
            fputs("INFO: Force discharge via CHIE (Tahoe)\n", stderr)
            if keyExists("CHIE") {
                try writeKey("CHIE", data: [0x08])
            } else {
                try writeKey("CH0I", data: [0x01])
            }
        } else {
            fputs("INFO: Force discharge via CH0I (Legacy)\n", stderr)
            try writeKey("CH0I", data: [0x01])
        }
    }

    func disableForceDischarge() throws {
        if isTahoe {
            if keyExists("CHIE") {
                try writeKey("CHIE", data: [0x00])
            } else {
                try writeKey("CH0I", data: [0x00])
            }
        } else {
            try writeKey("CH0I", data: [0x00])
        }
    }
}

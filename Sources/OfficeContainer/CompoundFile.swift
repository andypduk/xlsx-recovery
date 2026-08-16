import Foundation

public enum CompoundFileError: Error, Equatable {
    case invalidHeader
    case unsupportedByteOrder
    case unsupportedSectorSize
    case corruptChain
    case streamNotFound(String)
    case streamTooLarge
}

public struct CompoundFile: Sendable {
    private static let end: UInt32 = 0xFFFFFFFE
    private static let free: UInt32 = 0xFFFFFFFF
    private let data: Data
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: UInt64
    private let fat: [UInt32]
    private let miniFat: [UInt32]
    private let miniStream: Data
    private let entries: [DirectoryEntry]

    public static func openReadOnly(_ url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.readToEnd() else { throw CompoundFileError.invalidHeader }
        return try Self(data: data)
    }

    public init(data: Data) throws {
        guard data.count >= 512,
              Array(data[0..<8]) == [0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1] else {
            throw CompoundFileError.invalidHeader
        }
        guard data.u16(28) == 0xFFFE else { throw CompoundFileError.unsupportedByteOrder }
        let sectorShift = Int(data.u16(30)), miniShift = Int(data.u16(32))
        guard sectorShift == 9 || sectorShift == 12, miniShift == 6 else {
            throw CompoundFileError.unsupportedSectorSize
        }
        self.data = data
        self.sectorSize = 1 << sectorShift
        self.miniSectorSize = 1 << miniShift
        self.miniCutoff = UInt64(data.u32(56))

        let totalSectors = data.count / sectorSize - 1
        var difat: [UInt32] = []
        for offset in stride(from: 76, to: 512, by: 4) {
            let value = data.u32(offset)
            if value != Self.free { difat.append(value) }
        }
        var nextDifat = data.u32(68)
        let difatCount = Int(data.u32(72))
        var seenDifat = Set<UInt32>()
        for _ in 0..<difatCount {
            guard nextDifat != Self.end, seenDifat.insert(nextDifat).inserted,
                  Int(nextDifat) < totalSectors else { throw CompoundFileError.corruptChain }
            let sector = try Self.sector(data, size: sectorSize, id: nextDifat)
            for offset in stride(from: 0, to: sectorSize - 4, by: 4) {
                let value = sector.u32(offset)
                if value != Self.free { difat.append(value) }
            }
            nextDifat = sector.u32(sectorSize - 4)
        }
        let fatSectorCount = Int(data.u32(44))
        guard difat.count >= fatSectorCount else { throw CompoundFileError.corruptChain }
        var fat: [UInt32] = []
        for id in difat.prefix(fatSectorCount) {
            guard Int(id) < totalSectors else { throw CompoundFileError.corruptChain }
            let sector = try Self.sector(data, size: sectorSize, id: id)
            for offset in stride(from: 0, to: sectorSize, by: 4) { fat.append(sector.u32(offset)) }
        }
        self.fat = fat

        let directoryBytes = try Self.readChain(data: data, sectorSize: sectorSize, fat: fat,
                                                start: data.u32(48), limit: data.count)
        var entries: [DirectoryEntry] = []
        for offset in stride(from: 0, to: directoryBytes.count - 127, by: 128) {
            let nameLength = Int(directoryBytes.u16(offset + 64))
            guard nameLength == 0 || (nameLength >= 2 && nameLength <= 64 && nameLength.isMultiple(of: 2)) else {
                throw CompoundFileError.corruptChain
            }
            let nameData = nameLength > 1 ? directoryBytes[(offset)..<(offset + nameLength - 2)] : Data()
            let name = String(data: nameData, encoding: .utf16LittleEndian) ?? ""
            entries.append(.init(name: name, type: directoryBytes[offset + 66],
                                 start: directoryBytes.u32(offset + 116), size: directoryBytes.u64(offset + 120)))
        }
        self.entries = entries

        let firstMiniFat = data.u32(60), miniFatCount = Int(data.u32(64))
        if miniFatCount > 0 {
            let bytes = try Self.readChain(data: data, sectorSize: sectorSize, fat: fat,
                                           start: firstMiniFat, limit: miniFatCount * sectorSize)
            var values: [UInt32] = []
            for offset in stride(from: 0, to: bytes.count, by: 4) { values.append(bytes.u32(offset)) }
            self.miniFat = values
        } else { self.miniFat = [] }
        if let root = entries.first(where: { $0.type == 5 }), root.size > 0 {
            let bytes = try Self.readChain(data: data, sectorSize: sectorSize, fat: fat,
                                           start: root.start, limit: Int(min(root.size, UInt64(Int.max))))
            self.miniStream = bytes.prefix(Int(min(root.size, UInt64(bytes.count))))
        } else { self.miniStream = Data() }
    }

    public func readStream(named name: String, maxBytes: Int = Int.max) throws -> Data {
        guard let entry = entries.first(where: { $0.type == 2 && $0.name == name }) else {
            throw CompoundFileError.streamNotFound(name)
        }
        guard entry.size <= UInt64(maxBytes), entry.size <= UInt64(Int.max) else { throw CompoundFileError.streamTooLarge }
        let count = Int(entry.size)
        if entry.size < miniCutoff {
            var result = Data(), current = entry.start, seen = Set<UInt32>()
            while current != Self.end, result.count < count {
                guard Int(current) < miniFat.count, seen.insert(current).inserted else { throw CompoundFileError.corruptChain }
                let offset = Int(current) * miniSectorSize
                guard offset + miniSectorSize <= miniStream.count else { throw CompoundFileError.corruptChain }
                result.append(miniStream[offset..<(offset + miniSectorSize)])
                current = miniFat[Int(current)]
            }
            guard result.count >= count else { throw CompoundFileError.corruptChain }
            return result.prefix(count)
        }
        return try Self.readChain(data: data, sectorSize: sectorSize, fat: fat, start: entry.start, limit: count).prefix(count)
    }

    private static func sector(_ data: Data, size: Int, id: UInt32) throws -> Data {
        let offset = (Int(id) + 1) * size
        guard offset >= 0, offset + size <= data.count else { throw CompoundFileError.corruptChain }
        return data[offset..<(offset + size)]
    }

    private static func readChain(data: Data, sectorSize: Int, fat: [UInt32], start: UInt32, limit: Int) throws -> Data {
        var result = Data(), current = start, seen = Set<UInt32>()
        while current != end, result.count < limit {
            guard Int(current) < fat.count, seen.insert(current).inserted else { throw CompoundFileError.corruptChain }
            result.append(try sector(data, size: sectorSize, id: current))
            current = fat[Int(current)]
        }
        return result.prefix(min(result.count, limit))
    }
}

private struct DirectoryEntry: Sendable { let name: String; let type: UInt8; let start: UInt32; let size: UInt64 }

private extension Data {
    func u16(_ offset: Int) -> UInt16 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian } }
    func u32(_ offset: Int) -> UInt32 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian } }
    func u64(_ offset: Int) -> UInt64 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian } }
}

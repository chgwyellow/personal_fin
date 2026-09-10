import Foundation

/// The small part of Yahoo Finance's protobuf stream that FinTrack needs.
/// This intentionally accepts only regular-session ticks (marketHours == 1).
enum YahooMarketStream {
    struct Tick {
        let symbol: String
        let price: Double
        let currency: String?
        let previousClose: Double?
        let marketHours: Int?
    }

    static func subscribeMessage(symbols: [String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: ["subscribe": symbols]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ data: Data) -> Tick? {
        var reader = ProtobufReader(bytes: Array(data))
        var symbol: String?
        var price: Double?
        var currency: String?
        var previousClose: Double?
        var marketHours: Int?

        while let field = reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 2): symbol = reader.readString()
            case (2, 1): price = reader.readDouble()
            case (4, 2): currency = reader.readString()
            case (7, 0): marketHours = Int(reader.readVarint())
            case (16, 1): previousClose = reader.readDouble()
            default: reader.skip(wireType: field.wireType)
            }
        }

        guard let symbol, let price, price > 0 else { return nil }
        return Tick(symbol: symbol, price: price, currency: currency, previousClose: previousClose, marketHours: marketHours)
    }

    private struct ProtobufReader {
        struct Field { let number: Int; let wireType: Int }
        let bytes: [UInt8]
        var index = 0

        mutating func nextField() -> Field? {
            guard index < bytes.count else { return nil }
            let tag = readVarint()
            return Field(number: Int(tag >> 3), wireType: Int(tag & 0x07))
        }

        mutating func readVarint() -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
                if shift >= 64 { break }
            }
            return value
        }

        mutating func readDouble() -> Double? {
            guard index + 8 <= bytes.count else { return nil }
            let value = bytes[index..<(index + 8)].withUnsafeBytes {
                Double(bitPattern: UInt64(littleEndian: $0.load(as: UInt64.self)))
            }
            index += 8
            return value
        }

        mutating func readString() -> String? {
            let length = Int(readVarint())
            guard length >= 0, index + length <= bytes.count else { return nil }
            defer { index += length }
            return String(bytes: bytes[index..<(index + length)], encoding: .utf8)
        }

        mutating func skip(wireType: Int) {
            switch wireType {
            case 0: _ = readVarint()
            case 1: index = min(index + 8, bytes.count)
            case 2: index = min(index + Int(readVarint()), bytes.count)
            case 5: index = min(index + 4, bytes.count)
            default: index = bytes.count
            }
        }
    }
}

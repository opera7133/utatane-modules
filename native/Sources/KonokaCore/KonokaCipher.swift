import Foundation

public enum KonokaError: Error, Equatable {
    case invalidDictionary(String)
    case limitExceeded
    case invalidExpression(String)
}

/// Standard XDC byte transform and custom XDI base-95/seven-bit format.
/// This is a dictionary compatibility format, not a confidentiality mechanism.
public enum KonokaCipher {
    public enum Format: String { case xdi, xdc }

    /// Standard Konoka's cumulative byte transform. Counters span the whole file.
    private static func transformXDC(_ input: Data, encoding: Bool) throws -> Data {
        guard input.count <= limit else { throw KonokaError.limitExceeded }
        let first = Array("METAMORPHOSIS".utf8), second = Array("psychologicalmotion".utf8)
        var previous: UInt8 = 0
        var output = Data(capacity: input.count)
        for (index, byte) in input.enumerated() {
            let key = first[index % first.count] &+ second[index % second.count]
            let converted = encoding ? previous &+ byte &+ key : byte &- previous &- key
            output.append(converted)
            previous = encoding ? converted : byte
        }
        return output
    }

    private static let limit = 8 * 1024 * 1024

    public static func decode(_ input: Data, format: Format = .xdi) throws -> Data {
        if format == .xdc {
            return try transformXDC(input, encoding: false)
        }
        guard input.count <= limit else { throw KonokaError.limitExceeded }
        let bytes = Array(input)
        var unpacked: [UInt8] = []
        var bit = 0
        while bit / 8 + 1 < bytes.count {
            let index = bit / 8, shift = bit % 8
            unpacked.append(UInt8(((UInt16(bytes[index]) << shift) | (UInt16(bytes[index + 1]) >> (8 - shift))) >> 1 & 127))
            bit += 7
        }
        var output = Data()
        var work = 0
        for line in unpacked.split(separator: 10, omittingEmptySubsequences: true) {
            guard line.count <= 8192, line.allSatisfy({ (32 ... 126).contains($0) }) else {
                throw KonokaError.invalidDictionary("XDI line")
            }
            var number: [UInt8] = [0]
            for digit in line.reversed() {
                work += number.count
                guard work <= 32_000_000 else { throw KonokaError.limitExceeded }
                var carry = Int(digit) - 32
                for index in number.indices {
                    carry += Int(number[index]) * 95
                    number[index] = UInt8(carry & 255)
                    carry >>= 8
                }
                while carry > 0 {
                    number.append(UInt8(carry & 255)); carry >>= 8
                }
            }
            guard let padding = number.popLast(), (32 ... 126).contains(padding), !number.contains(0) else {
                throw KonokaError.invalidDictionary("XDI padding")
            }
            output.append(contentsOf: number)
            output.append(contentsOf: [13, 10])
            guard output.count <= limit else { throw KonokaError.limitExceeded }
        }
        guard !input.isEmpty, !output.isEmpty else { throw KonokaError.invalidDictionary("empty XDI") }
        return output
    }

    public static func encode(_ input: Data, format: Format = .xdi) throws -> Data {
        if format == .xdc {
            return try transformXDC(input, encoding: true)
        }
        guard input.count <= limit, !input.contains(0) else { throw KonokaError.invalidDictionary("text") }
        var printable: [UInt8] = []
        var work = 0
        var lines = Array(input).split(separator: 10, omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        for line in lines {
            var number = Array(line)
            if number.last == 13 {
                number.removeLast()
            }
            guard number.count <= 4096 else { throw KonokaError.limitExceeded }
            number.append(32) // The original appends a random printable byte; any printable byte is valid.
            while !number.isEmpty {
                work += number.count
                guard work <= 32_000_000 else { throw KonokaError.limitExceeded }
                var carry = 0
                for index in number.indices.reversed() {
                    let value = carry * 256 + Int(number[index])
                    number[index] = UInt8(value / 95)
                    carry = value % 95
                }
                printable.append(UInt8(carry + 32))
                while number.last == 0 {
                    number.removeLast()
                }
            }
            printable.append(10)
        }
        var output = Data(), accumulator: UInt32 = 0, bits = 0
        for byte in printable {
            accumulator = (accumulator << 7) | UInt32(byte)
            bits += 7
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((accumulator >> bits) & 255))
                accumulator &= (1 << bits) - 1
            }
        }
        if bits > 0 {
            output.append(UInt8(accumulator << (8 - bits)))
        }
        return output
    }
}

// Based on Hitomi Phase 0.2 by Holonics and Kawari Phase 0.42 by NAKAUE.T.
// See recipes/hitomi/licenses/Hitomi-BSD.txt for their distribution conditions.
import Foundation

public enum HitomiError: Error, Equatable {
    case invalidDictionary(String)
    case unsupportedSyntax(String)
    case limitExceeded
}

/// Kawari 0.42 / Hitomi's line format: !KAWA0000, Base64, XOR 0xcc.
public enum HitomiCipher {
    public static func decodeLine(_ line: Data) throws -> Data {
        guard line.count <= 1024 * 1024 else { throw HitomiError.limitExceeded }
        let prefix = Data("!KAWA0000".utf8)
        guard line.starts(with: prefix), let decoded = Data(base64Encoded: line.dropFirst(prefix.count)) else {
            throw HitomiError.invalidDictionary("encrypted line")
        }
        return Data(decoded.map { $0 ^ 0xCC })
    }

    public static func encodeLine(_ line: Data) throws -> Data {
        guard line.count <= 512 * 1024, !line.contains(0), !line.contains(10), !line.contains(13) else {
            throw HitomiError.invalidDictionary("plain line")
        }
        return Data("!KAWA0000".utf8) + Data(line.map { $0 ^ 0xCC }).base64EncodedData()
    }
}

import CryptoKit
import Foundation
import Security

/// The public totp_saori command interface, implemented independently with CryptoKit.
/// Secrets live only in the request; no key file or diagnostic output is produced.
final class NativeTOTP: NativeSaoriModule {
    private let now: () -> UInt64
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

    init(now: @escaping () -> UInt64 = { UInt64(max(0, Date().timeIntervalSince1970)) }) {
        self.now = now
    }

    func execute(_ arguments: [String]) -> SaoriExecution {
        guard let command = arguments.first else { return .init(400) }
        switch command {
        case "keygen":
            let length = arguments.count > 1 ? Int(arguments[1]) : 30
            guard let length, (1 ... 1024).contains(length) else { return .init(400) }
            var bytes = [UInt8](repeating: 0, count: length)
            guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else { return .init(500) }
            return .init(200, [Self.encode(bytes)])
        case "totp":
            guard arguments.count >= 2, let secret = Self.decode(arguments[1]), !secret.isEmpty else { return .init(400) }
            let time = arguments.count > 2 ? UInt64(arguments[2]) : now()
            let digits = arguments.count > 3 ? Int(arguments[3]) : 6
            let interval = arguments.count > 4 ? UInt32(arguments[4]) : 30
            guard let time, let digits, (1 ... 9).contains(digits), let interval, interval > 0 else { return .init(400) }
            var counter = (time / UInt64(interval)).bigEndian
            let message = withUnsafeBytes(of: &counter) { Data($0) }
            let digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
            let offset = Int(digest[19] & 15)
            let binary = digest[offset ..< offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & 0x7FFF_FFFF
            let modulus = (0 ..< digits).reduce(UInt32(1)) { value, _ in value * 10 }
            let code = String(binary % modulus)
            return .init(200, [String(repeating: "0", count: max(0, digits - code.count)) + code])
        default: return .init(400)
        }
    }

    func call(_ arguments: [String]) -> String { execute(arguments).values.first ?? "" }
    func unload() {}

    private static func encode(_ bytes: [UInt8]) -> String {
        var output: [UInt8] = [], buffer: UInt32 = 0, bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte); bits += 8
            while bits >= 5 {
                bits -= 5; output.append(alphabet[Int((buffer >> bits) & 31)])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { output.append(alphabet[Int((buffer << (5 - bits)) & 31)]) }
        return String(decoding: output, as: UTF8.self)
    }

    private static func decode(_ text: String) -> Data? {
        guard !text.isEmpty, text.utf8.count <= 8192 else { return nil }
        let bytes = Array(text.utf8)
        let end = bytes.firstIndex(of: 61) ?? bytes.count
        guard [0, 2, 4, 5, 7].contains(end % 8),
              end == bytes.count || (bytes.count == (end + 7) / 8 * 8 && bytes[end...].allSatisfy { $0 == 61 }) else { return nil }
        var output = Data(), buffer: UInt32 = 0, bits = 0
        for byte in bytes[..<end] {
            let value: UInt8
            switch byte {
            case 65 ... 90: value = byte - 65
            case 97 ... 122: value = byte - 97
            case 50 ... 55: value = byte - 50 + 26
            default: return nil
            }
            buffer = (buffer << 5) | UInt32(value); bits += 5
            if bits >= 8 {
                bits -= 8; output.append(UInt8((buffer >> bits) & 255))
            }
            buffer &= (1 << bits) - 1
        }
        guard buffer == 0 else { return nil }
        return output
    }
}

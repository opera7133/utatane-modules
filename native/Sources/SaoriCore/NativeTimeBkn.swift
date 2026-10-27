import Darwin
import Foundation

/// Conventional timebkn date commands. QREKI is explicitly unavailable.
final class NativeTimeBkn: NativeSaoriModule {
    private let now: () -> Int64
    private let uptimeMilliseconds: () -> UInt64
    init(now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) },
         uptimeMilliseconds: @escaping () -> UInt64 = { UInt64(ProcessInfo.processInfo.systemUptime * 1000) }) {
        self.now = now; self.uptimeMilliseconds = uptimeMilliseconds
    }

    func execute(_ arguments: [String]) -> SaoriExecution {
        guard let command = arguments.first?.lowercased() else { return .init(400) }
        switch command {
        case "time": return .init(200, [String(now())])
        case "tick": return .init(200, [String(UInt32(truncatingIfNeeded: uptimeMilliseconds()))])
        case "system": return .init(200, [String(UInt32(truncatingIfNeeded: uptimeMilliseconds()) / 1000)])
        case "qreki": return .init(501)
        case "fromdate":
            guard arguments.count >= 2, let year = Int(arguments[1]), (1 ... 9999).contains(year) else { return .init(400) }
            var date = tm()
            date.tm_year = Int32(year - 1900)
            // Match the original zero-initialized tm (January, day zero,
            // standard time), including mktime's component normalization.
            let defaults = [Int32(1), 0, 0, 0, 0]
            var components: [Int32] = []
            for index in 0 ..< 5 {
                let value = arguments.count > index + 2 ? Int32(arguments[index + 2]) : defaults[index]
                guard let value, index != 0 || value > Int32.min else { return .init(400) }
                components.append(value)
            }
            date.tm_mon = components[0] - 1; date.tm_mday = components[1]
            date.tm_hour = components[2]; date.tm_min = components[3]; date.tm_sec = components[4]
            let result = mktime(&date)
            guard (1 ... 9999).contains(Int(date.tm_year) + 1900) else { return .init(400) }
            return .init(200, [String(result)])
        case "local", "strftime":
            guard command != "strftime" || arguments.count >= 3 else { return .init(400) }
            let epoch = arguments.count >= 2 ? Int64(arguments[1]) : now()
            guard let epoch else { return .init(400) }
            var time = time_t(epoch), date = tm()
            guard localtime_r(&time, &date) != nil, (1 ... 9999).contains(Int(date.tm_year) + 1900) else { return .init(400) }
            if command == "local" {
                var text = [CChar](repeating: 0, count: 64)
                guard asctime_r(&date, &text) != nil else { return .init(500) }
                return .init(200, [String(cString: text)] + [date.tm_year + 1900, date.tm_mon + 1, date.tm_mday,
                    date.tm_hour, date.tm_min, date.tm_sec, date.tm_wday, date.tm_yday].map(String.init))
            }
            guard arguments[2].utf8.count < 8192 else { return .init(400) }
            if arguments[2].isEmpty { return .init(200, [""]) }
            var text = [CChar](repeating: 0, count: 8192)
            let length = arguments[2].withCString { strftime(&text, text.count, $0, &date) }
            guard length > 0 else { return .init(500) }
            return .init(200, [String(cString: text)])
        default: return .init(400)
        }
    }

    func call(_ arguments: [String]) -> String { execute(arguments).values.joined(separator: "\u{1}") }
    func unload() {}
}

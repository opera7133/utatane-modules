import Foundation
import LegacyText
import SystemConfiguration

/// Conventional httpc compatibility. Background requests use the private owning
/// host bridge; no external DirectSSTP endpoint is opened by this library.
final class NativeHttpc: NativeSaoriModule {
    private let directory: URL
    private let connected: () -> Bool
    private let fetch: (URL) -> (data: Data, charset: String?)?
    private var hasBackgroundRequests = false

    init(directory: URL, connected: @escaping () -> Bool = NativeHttpc.isConnected,
         fetch: @escaping (URL) -> (data: Data, charset: String?)? = HttpcTransfer.fetch) {
        self.fetch = fetch
        self.directory = directory
        self.connected = connected
    }

    func call(_ arguments: [String]) -> String { callValues(arguments).first ?? "" }

    /// Each request returns its first match and all subsequent matches together.
    /// Do not use the generic U+0001 separator: it can occur in an HTTP body.
    func callValues(_ arguments: [String]) -> [String] {
        if arguments.isEmpty { return [connected() ? "1" : "0"] }
        if arguments[0].caseInsensitiveCompare("bg") == .orderedSame {
            guard arguments.count >= 3, !arguments[1].isEmpty else { return [""] }
            if HttpcHostBridge.submit(directory: directory, arguments: ["bg"] + arguments.dropFirst()) {
                hasBackgroundRequests = true
            }
            return [""]
        }
        var args = arguments
        var charset: String?
        if let first = args.first?.lowercased(), ["euc", "jis", "sjis", "utf8", "utf-8", "utf-16be", "utf-16le"].contains(first) {
            charset = ["euc": "EUC-JP", "jis": "ISO-2022-JP", "sjis": "CP932", "utf8": "UTF-8"][first] ?? first
            args.removeFirst()
        }
        guard (1 ... 3).contains(args.count), let url = URL(string: args[0]),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return [""] }
        guard let response = fetch(url) else { return [args.count == 2 ? "0" : ""] }
        if args.count == 2 {
            let path = args[1].replacingOccurrences(of: "\\", with: "/")
            guard !path.isEmpty, !path.utf8.contains(0) else { return ["0"] }
            let output = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appending(path: path)
            do { try response.data.write(to: output, options: .atomic); return ["1"] } catch { return ["0"] }
        }
        let text: String?
        if let charset, let encoding = LegacyTextDecoder.encoding(named: charset) { text = String(data: response.data, encoding: encoding) }
        else { text = LegacyTextDecoder.decode(response.data, preferredCharset: response.charset) }
        guard let text else { return [""] }
        let clean = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\0", with: "")
        guard args.count == 3 else { return [clean] }
        guard !args[1].isEmpty, !args[2].isEmpty else { return [""] }
        var values: [String] = [], start = clean.startIndex
        while values.count < 254, let left = clean.range(of: args[1], range: start ..< clean.endIndex),
              let right = clean.range(of: args[2], range: left.upperBound ..< clean.endIndex) {
            values.append(String(clean[left.upperBound ..< right.lowerBound])); start = right.upperBound
        }
        return values.isEmpty ? [""] : values
    }

    func unload() {
        if hasBackgroundRequests { _ = HttpcHostBridge.submit(directory: directory, arguments: ["cancel"]) }
        hasBackgroundRequests = false
    }

    private static func isConnected() -> Bool {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, "example.com") else { return false }
        var flags = SCNetworkReachabilityFlags()
        return SCNetworkReachabilityGetFlags(reachability, &flags) && flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }
}

final class HttpcTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var succeeded = false
    private static let limit = 32 * 1024 * 1024

    static func fetch(_ url: URL) -> (data: Data, charset: String?)? {
        let transfer = HttpcTransfer()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: url).resume()
        guard transfer.waitForCompletion(timeout: 35) else { return nil }
        return transfer.lock.withLock {
            guard transfer.succeeded else { return nil }
            return (transfer.data, transfer.response?.textEncodingName)
        }
    }

    /// Conventional DLL hosts can call us on their main thread without a
    /// running application loop. Older CFNetwork versions need main-run-loop
    /// callbacks during setup; blocking that thread on a semaphore stalls them.
    private func waitForCompletion(timeout: TimeInterval) -> Bool {
        guard Thread.isMainThread else { return ready.wait(timeout: .now() + timeout) == .success }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if ready.wait(timeout: .now()) == .success { return true }
            _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.02)))
        }
        return ready.wait(timeout: .now()) == .success
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              response.expectedContentLength <= Int64(Self.limit) else { completionHandler(.cancel); return }
        lock.withLock { self.response = http }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let accepted = lock.withLock {
            guard self.data.count <= Self.limit - data.count else { return false }
            self.data.append(data)
            return true
        }
        if !accepted { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.withLock { succeeded = error == nil && response != nil }
        ready.signal()
    }
}

import Foundation
import LegacyText
import SystemConfiguration

/// Synchronous httpc compatibility used by existing plugins. The original
/// module's bg/DirectSSTP notifications and HTML transformation options are not
/// provided by this dylib.
final class NativeHttpc: NativeSaoriModule {
    private let directory: URL
    private let connected: () -> Bool
    private let fetch: (URL) -> (data: Data, charset: String?)?
    private var cursorKey: [String] = []
    private var cursor = 0
    private var cachedText = ""

    init(directory: URL, connected: @escaping () -> Bool = NativeHttpc.isConnected,
         fetch: @escaping (URL) -> (data: Data, charset: String?)? = HttpcTransfer.fetch) {
        self.fetch = fetch
        self.directory = directory
        self.connected = connected
    }

    func call(_ arguments: [String]) -> String {
        if arguments.isEmpty { return connected() ? "1" : "0" }
        var args = arguments
        var charset: String?
        if let first = args.first?.lowercased(), ["euc", "jis", "sjis", "utf-8", "utf-16be", "utf-16le"].contains(first) {
            charset = ["euc": "EUC-JP", "jis": "ISO-2022-JP", "sjis": "CP932"][first] ?? first
            args.removeFirst()
        }
        guard (1 ... 3).contains(args.count), let url = URL(string: args[0]),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return "" }
        let key = arguments
        if args.count != 3 || key != cursorKey {
            guard let response = fetch(url) else { return args.count == 2 ? "0" : "" }
            if args.count == 2 {
                let path = args[1].replacingOccurrences(of: "\\", with: "/")
                guard !path.isEmpty, !path.contains("\0") else { return "0" }
                let output = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appending(path: path)
                do { try response.data.write(to: output, options: .atomic); return "1" } catch { return "0" }
            }
            let body = response.data
            let text: String?
            if let charset, let encoding = LegacyTextDecoder.encoding(named: charset) { text = String(data: body, encoding: encoding) }
            else { text = LegacyTextDecoder.decode(body, preferredCharset: response.charset) }
            guard let text else { return "" }
            cachedText = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\0", with: "")
            cursorKey = key
            cursor = 0
        }
        guard args.count == 3 else { return cachedText }
        guard !args[1].isEmpty, !args[2].isEmpty, cursor <= cachedText.count else { return "" }
        let start = cachedText.index(cachedText.startIndex, offsetBy: cursor)
        guard let left = cachedText.range(of: args[1], range: start ..< cachedText.endIndex),
              let right = cachedText.range(of: args[2], range: left.upperBound ..< cachedText.endIndex) else { return "" }
        cursor = cachedText.distance(from: cachedText.startIndex, to: right.upperBound)
        return String(cachedText[left.upperBound ..< right.lowerBound])
    }

    func unload() { cachedText = ""; cursorKey = []; cursor = 0 }

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
        guard transfer.ready.wait(timeout: .now() + 35) == .success else { return nil }
        return transfer.lock.withLock {
            guard transfer.succeeded else { return nil }
            return (transfer.data, transfer.response?.textEncodingName)
        }
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

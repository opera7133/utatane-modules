/// Host-supplied services; the evaluator has no AppKit or application dependency.
public protocol NativeSaoriCalling: Sendable {
    func load(_ path: String)
    func unload(_ path: String)
    func call(_ path: String, arguments: [String]) -> String
}

public struct UnavailableSaoriCaller: NativeSaoriCalling {
    public init() {}
    public func load(_: String) {}
    public func unload(_: String) {}
    public func call(_: String, arguments _: [String]) -> String {
        ""
    }
}

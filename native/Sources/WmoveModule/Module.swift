import SaoriRuntime

private let session = ConventionalSaoriSession(kind: .wmove)

@_cdecl("loadu")
public func saoriLoadUTF8(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    session.load(input, length)
}

@_cdecl("load")
public func saoriLoad(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    session.load(input, length)
}

@_cdecl("request")
public func saoriRequest(_ input: UnsafeMutableRawPointer?, _ length: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    session.request(input, length)
}

@_cdecl("unload")
public func saoriUnload() -> Int32 {
    session.unload()
}

/// Private connection to the owning ghost's windows; optional for ordinary SAORI hosts.
@_cdecl("utatane_wmove_set_window_callback")
public func setWindowCallback(_ callback: SaoriWindowCallback?) -> Int32 {
    session.setWindowCallback(callback)
}

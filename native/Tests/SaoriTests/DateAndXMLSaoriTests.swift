import Foundation
import Testing
@testable import SaoriCore

@Test func timebknClockWrapNormalizationAndCalendarValues() throws {
    let time = NativeTimeBkn(now: { 1_700_000_000 }, uptimeMilliseconds: { UInt64(UInt32.max) + 2001 })
    #expect(time.execute(["TIME"]).values == ["1700000000"])
    #expect(time.execute(["tick"]).values == ["2000"])
    #expect(time.execute(["system"]).values == ["2"])
    #expect(time.execute(["fromdate", "2024", "1", "32"]).values == time.execute(["fromdate", "2024", "2", "1"]).values)
    #expect(time.execute(["fromdate", "2024", "1", "2", "3", "4", "65"]).values == time.execute(["fromdate", "2024", "1", "2", "3", "5", "5"]).values)
    let local = time.execute(["local"])
    #expect(local.status == 200)
    #expect(local.values.count == 9)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let fields: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
    #expect(Array(local.values[1 ... 6]) == fields.map { String(calendar.component($0, from: date)) })
    #expect(local.values[7] == String(calendar.component(.weekday, from: date) - 1))
    #expect(local.values[8] == String(try #require(calendar.ordinality(of: .day, in: .year, for: date)) - 1))
    #expect(time.execute(["strftime", "1700000000", "%Y年%m月"]).values == ["\(local.values[1])年\(String(format: "%02d", Int(local.values[2])!))月"])
    #expect(time.execute(["strftime", "1700000000", ""]).values == [""])
    #expect(time.execute(["qreki"]).status == 501)
    for args in [[], ["unknown"], ["fromdate"], ["fromdate", "0"], ["fromdate", "2024", "x"],
                 ["local", "bad"], ["local", String(Int64.max)], ["strftime", "0"]] {
        #expect(time.execute(args).status == 400)
    }
}

@Test func xpathKeepsIDsAndOriginalNodeAndScalarReturnShapes() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "XML 日本語 \(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "辞書.xml")
    try "<root><item key=\"a\">日本語</item><item key=\"b\">次</item><nested><b>除外</b></nested><empty/><c><![CDATA[そのまま]]></c></root>".write(to: file, atomically: true, encoding: .utf8)
    let xpath = NativeXPath(directory: root)
    let opened = xpath.execute(["OPEN", "辞書.xml"])
    #expect(opened.status == 200)
    let id = try #require(opened.values.first)
    #expect(xpath.execute(["open", "辞書.xml"]).values == [id])
    #expect(xpath.execute(["get", id, "/root/item"]).values == ["日本語\u{1}次", "日本語", "次"])
    #expect(xpath.execute(["get", id, "/root/item/@key"]).values == ["a\u{1}b", "a", "b"])
    #expect(xpath.execute(["get", id, "item[1]/text()"]).values == ["日本語", "日本語"])
    #expect(xpath.execute(["get", id, "count(/root/item)"]).values == ["2", "2"])
    #expect(xpath.execute(["get", id, "boolean(/root/missing)"]).values == ["0", "0"])
    #expect(xpath.execute(["get", id, "string(/root/item[2])"]).values == ["次", "次"])
    #expect(xpath.execute(["get", id, "/root/nested | /root/empty"]).values == [""])
    #expect(xpath.execute(["get", id, "/root/c"]).values == ["そのまま", "そのまま"])
    #expect(xpath.execute(["get", id, "/root/missing"]).status == 200)
    try "<changed/>".write(to: file, atomically: true, encoding: .utf8)
    #expect(xpath.execute(["open", "辞書.xml"]).values == [id])
    #expect(xpath.execute(["get", id, "count(/root/item)"]).values == ["2", "2"])
    #expect(xpath.execute(["get", id, "["]).status == 500)
    #expect(xpath.execute(["get", id, "doc('file:///etc/passwd')"]).status == 500)
    #expect(xpath.execute(["close", id]).status == 204)
    #expect(xpath.execute(["get", id, "/root"]).status == 400)
    #expect(xpath.execute(["open", "辞書.xml"]).values != [id])
    try #require("<?xml version=\"1.0\" encoding=\"Shift_JIS\"?><根><値>日本語</値></根>".data(using: .shiftJIS)).write(to: root.appending(path: "sjis.xml"))
    let sjis = try #require(xpath.execute(["open", "sjis.xml"]).values.first)
    #expect(xpath.execute(["get", sjis, "/根/値"]).values == ["日本語", "日本語"])
    xpath.unload()
    #expect(xpath.execute(["get", id, "/root"]).status == 400)
}

@Test func xpathRejectsExternalEntitiesMalformedFilesAndResourceOverflow() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "LOCAL_SENTINEL".write(to: root.appending(path: "secret.txt"), atomically: true, encoding: .utf8)
    for (name, xml) in [
        ("external.xml", "<!DOCTYPE r [<!ENTITY x SYSTEM '\(root.appending(path: "secret.txt").absoluteString)'>]><r>&x;</r>"),
        ("internal.xml", "<!DOCTYPE r [<!ENTITY x 'no expansion'>]><r>&x;</r>"),
        ("bad.xml", "<r>"), ("empty.xml", ""),
    ] {
        try xml.write(to: root.appending(path: name), atomically: true, encoding: .utf8)
        #expect(NativeXPath(directory: root).execute(["open", name]).status == 400)
    }
    let xpath = NativeXPath(directory: root)
    try #require("<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE r [<!ENTITY x 'denied'>]><r>&x;</r>".data(using: .utf16)).write(to: root.appending(path: "utf16-dtd.xml"))
    #expect(xpath.execute(["open", "utf16-dtd.xml"]).status == 400)
    for index in 0 ..< 32 {
        try "<r>\(index)</r>".write(to: root.appending(path: "\(index).xml"), atomically: true, encoding: .utf8)
        #expect(xpath.execute(["open", "\(index).xml"]).status == 200)
    }
    #expect(xpath.execute(["open", "overflow.xml"]).status == 400)
    let id = try #require(xpath.execute(["open", "0.xml"]).values.first)
    #expect(xpath.execute(["get", id, String(repeating: "a", count: 4097)]).status == 400)
    xpath.unload()
    try ("<r>" + String(repeating: "x", count: 2 * 1024 * 1024 + 1) + "</r>").write(to: root.appending(path: "big.xml"), atomically: true, encoding: .utf8)
    let big = try #require(xpath.execute(["open", "big.xml"]).values.first)
    #expect(xpath.execute(["get", big, "/r"]).status == 500)
    try ("<r>" + String(repeating: "<x/>", count: 8193) + "</r>").write(to: root.appending(path: "nodes.xml"), atomically: true, encoding: .utf8)
    let nodes = try #require(xpath.execute(["open", "nodes.xml"]).values.first)
    #expect(xpath.execute(["get", nodes, "/r/x"]).status == 500)
    try ("<r>" + String(repeating: "<x>1</x>", count: 1000) + "</r>").write(to: root.appending(path: "work.xml"), atomically: true, encoding: .utf8)
    let work = try #require(xpath.execute(["open", "work.xml"]).values.first)
    #expect(xpath.execute(["get", work, "count(/r/x[sum(/r/x) >= 0])"]).status == 500)
}

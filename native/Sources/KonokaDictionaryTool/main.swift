import Darwin
import Foundation
import KonokaCore

let arguments = CommandLine.arguments
if ![4, 6].contains(arguments.count) || !["encode", "decode"].contains(arguments[1]) {
    FileHandle.standardError.write(Data("Usage: konoka-dictionary encode|decode INPUT OUTPUT [--format xdi|xdc]\n".utf8))
    exit(64)
}

do {
    let input = URL(fileURLWithPath: arguments[2])
    let output = URL(fileURLWithPath: arguments[3])
    guard let size = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024 else {
        throw KonokaError.limitExceeded
    }
    let format: KonokaCipher.Format
    if arguments.count == 6 {
        guard arguments[4] == "--format", let selected = KonokaCipher.Format(rawValue: arguments[5]) else {
            throw KonokaError.invalidDictionary("format must be xdi or xdc")
        }
        format = selected
    } else {
        let ext = (arguments[1] == "encode" ? output : input).pathExtension.lowercased()
        format = ext == "xdc" ? .xdc : .xdi
    }
    let data = try Data(contentsOf: input)
    let converted = try arguments[1] == "encode" ? KonokaCipher.encode(data, format: format) : KonokaCipher.decode(data, format: format)
    try converted.write(to: output, options: .withoutOverwriting)
} catch {
    FileHandle.standardError.write(Data("konoka-dictionary: \(error)\n".utf8))
    exit(1)
}

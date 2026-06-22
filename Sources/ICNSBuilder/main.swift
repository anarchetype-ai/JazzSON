import Foundation

struct IconEntry {
    let type: String
    let url: URL
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, arguments.count % 2 == 1 else {
    fatalError("Usage: ICNSBuilder output.icns type image.png [type image.png ...]")
}

let outputURL = URL(fileURLWithPath: arguments[0])
let entries = stride(from: 1, to: arguments.count, by: 2).map {
    IconEntry(type: arguments[$0], url: URL(fileURLWithPath: arguments[$0 + 1]))
}

func bigEndianData(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
}

var fileData = Data()
var chunks = Data()

for entry in entries {
    let imageData = try Data(contentsOf: entry.url)
    guard let typeData = entry.type.data(using: .ascii), typeData.count == 4 else {
        fatalError("ICNS entry types must be 4 ASCII bytes")
    }

    chunks.append(typeData)
    chunks.append(bigEndianData(UInt32(imageData.count + 8)))
    chunks.append(imageData)
}

fileData.append("icns".data(using: .ascii)!)
fileData.append(bigEndianData(UInt32(chunks.count + 8)))
fileData.append(chunks)

try fileData.write(to: outputURL)

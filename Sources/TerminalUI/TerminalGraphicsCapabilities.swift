import Core

/// Graphics-oriented terminal capabilities detected by the host runtime.
public struct TerminalGraphicsCapabilities: Equatable, Sendable {
  public enum GraphicsProtocol: String, Equatable, Sendable {
    case kitty
    case sixel
  }

  public var supportedProtocols: [GraphicsProtocol]
  public var preferredProtocol: GraphicsProtocol?
  public var sixelColorRegisters: Int?
  public var sixelGeometry: PixelSize?
  public var cellPixelSize: PixelSize?

  public init(
    supportedProtocols: [GraphicsProtocol] = [],
    preferredProtocol: GraphicsProtocol? = nil,
    sixelColorRegisters: Int? = nil,
    sixelGeometry: PixelSize? = nil,
    cellPixelSize: PixelSize? = nil
  ) {
    self.supportedProtocols = supportedProtocols
    self.preferredProtocol = preferredProtocol
    self.sixelColorRegisters = sixelColorRegisters
    self.sixelGeometry = sixelGeometry
    self.cellPixelSize = cellPixelSize
  }

  public static let none = Self()

  public var supportsKitty: Bool {
    supportedProtocols.contains(.kitty)
  }

  public var supportsSixel: Bool {
    supportedProtocols.contains(.sixel)
  }
}

package struct TerminalSurfaceCapabilities: Equatable, Sendable {
  package var cellPixelSize: PixelSize?
  package var pointerInputCapabilities: PointerInputCapabilities

  package init(
    cellPixelSize: PixelSize? = nil,
    pointerInputCapabilities: PointerInputCapabilities = .cellOnly
  ) {
    self.cellPixelSize = cellPixelSize
    self.pointerInputCapabilities = pointerInputCapabilities
  }
}

enum TerminalGraphicsQuery {
  case kittySupport(id: UInt32)
  case primaryDeviceAttributes
  case sixelColorRegisters
  case sixelGeometry
  case textAreaPixels
  case cellPixels

  var request: String {
    switch self {
    case .kittySupport(let id):
      return "\u{001B}_Gi=\(id),s=1,v=1,a=q,t=d,f=24;AAAA\u{001B}\\\u{001B}[c"
    case .primaryDeviceAttributes:
      return "\u{001B}[c"
    case .sixelColorRegisters:
      return "\u{001B}[?1;1;0S"
    case .sixelGeometry:
      return "\u{001B}[?2;1;0S"
    case .textAreaPixels:
      return "\u{001B}[14t"
    case .cellPixels:
      return "\u{001B}[16t"
    }
  }
}

func terminalStrictUTF8String(
  from bytes: [UInt8]
) -> String? {
  let decoded = String(decoding: bytes, as: UTF8.self)
  return Array(decoded.utf8) == bytes ? decoded : nil
}

func parseKittySupportResponse(
  in bytes: [UInt8],
  id: UInt32
) -> Bool? {
  guard let response = terminalStrictUTF8String(from: bytes) else {
    return nil
  }
  let prefix = "\u{001B}_Gi=\(id);"
  guard let range = response.firstLiteralRange(of: prefix) else {
    return nil
  }
  let suffix = response[range.upperBound...]
  if suffix.hasPrefix("OK") {
    return true
  }
  return false
}

func parsePrimaryDeviceAttributes(
  from bytes: [UInt8]
) -> [Int]? {
  guard let response = terminalStrictUTF8String(from: bytes) else {
    return nil
  }
  guard let prefixRange = response.firstLiteralRange(of: "\u{001B}[?") else {
    return nil
  }

  let suffix = response[prefixRange.upperBound...]
  guard let terminator = suffix.firstIndex(of: "c") else {
    return nil
  }

  return String(suffix[..<terminator])
    .split(separator: ";")
    .compactMap { Int($0) }
}

func parseXTSMGraphicsResponse(
  from bytes: [UInt8],
  item: Int
) -> (status: Int, values: [Int])? {
  guard let response = terminalStrictUTF8String(from: bytes) else {
    return nil
  }
  let prefix = "\u{001B}[?\(item);"
  guard let range = response.firstLiteralRange(of: prefix) else {
    return nil
  }

  let suffix = response[range.upperBound...]
  guard let terminator = suffix.firstIndex(of: "S") else {
    return nil
  }

  let values = String(suffix[..<terminator])
    .split(separator: ";")
    .compactMap { Int($0) }
  guard let status = values.first else {
    return nil
  }
  return (status, Array(values.dropFirst()))
}

func parseWindowSizeResponse(
  from bytes: [UInt8],
  expectedCode: Int
) -> PixelSize? {
  guard let response = terminalStrictUTF8String(from: bytes) else {
    return nil
  }
  let prefix = "\u{001B}[\(expectedCode);"
  guard let range = response.firstLiteralRange(of: prefix) else {
    return nil
  }

  let suffix = response[range.upperBound...]
  guard let terminator = suffix.firstIndex(of: "t") else {
    return nil
  }

  let values = String(suffix[..<terminator])
    .split(separator: ";")
    .compactMap { Int($0) }
  guard values.count >= 2 else {
    return nil
  }

  return .init(width: values[1], height: values[0])
}

import SwiftTUICore

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

enum TerminalInputCapabilityQuery {
  case decPrivateMode(mode: Int)
  case kittyKeyboardFlags

  var request: String {
    switch self {
    case .decPrivateMode(let mode):
      return "\u{001B}[?\(mode)$p"
    case .kittyKeyboardFlags:
      // The flags query piggybacks a primary-device-attributes query, the
      // same trick as the kitty graphics probe: every terminal answers
      // `\e[c`, so the DA report is the guaranteed terminator that keeps
      // the probe from stalling on terminals that ignore `\e[?u`.
      return "\u{001B}[?u\u{001B}[c"
    }
  }
}

enum DECPrivateModeState: Int, Equatable, Sendable {
  case notRecognized = 0
  case set = 1
  case reset = 2
  case permanentlySet = 3
  case permanentlyReset = 4

  var canEnable: Bool {
    switch self {
    case .set, .reset, .permanentlySet:
      return true
    case .notRecognized, .permanentlyReset:
      return false
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

/// Extracts the flags value from a kitty keyboard protocol flags report
/// (`ESC [ ? <flags> u`). The probe buffer may also hold the piggybacked
/// primary-device-attributes report (`ESC [ ? … c`), so every `ESC [ ?`
/// occurrence is tested until one terminates in `u` with a purely numeric
/// parameter.
func parseKittyKeyboardFlagsReport(
  from bytes: [UInt8]
) -> Int? {
  guard let response = terminalStrictUTF8String(from: bytes) else {
    return nil
  }

  var remainder = response
  while let prefixRange = remainder.firstLiteralRange(of: "\u{001B}[?") {
    let suffix = remainder[prefixRange.upperBound...]
    let digits = suffix.prefix(while: \.isNumber)
    let terminatorIndex = digits.endIndex
    if terminatorIndex < suffix.endIndex,
      suffix[terminatorIndex] == "u",
      let flags = Int(digits)
    {
      return flags
    }
    remainder = String(suffix)
  }
  return nil
}

func parseDECPrivateModeReport(
  from bytes: [UInt8],
  mode: Int
) -> DECPrivateModeState? {
  guard let response = terminalStrictUTF8String(from: bytes) else {
    return nil
  }
  let prefix = "\u{001B}[?\(mode);"
  guard let range = response.firstLiteralRange(of: prefix) else {
    return nil
  }

  let suffix = response[range.upperBound...]
  guard let dollarIndex = suffix.firstIndex(of: "$") else {
    return nil
  }
  let yIndex = suffix.index(after: dollarIndex)
  guard yIndex < suffix.endIndex, suffix[yIndex] == "y" else {
    return nil
  }

  let stateValue = String(suffix[..<dollarIndex])
  guard let rawValue = Int(stateValue) else {
    return nil
  }
  return DECPrivateModeState(rawValue: rawValue)
}

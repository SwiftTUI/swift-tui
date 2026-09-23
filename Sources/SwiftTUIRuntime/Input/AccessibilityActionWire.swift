/// Shared typed-action command parser for browser and Android ingress.
/// Framing belongs to the host; malformed commands never become terminal keys.
package enum AccessibilityActionWire {
  package static func parseCommand(_ text: String) -> AccessibilityActionRequest? {
    guard text.utf8.count <= HostWireBudget.recordBytes else { return nil }
    var parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    var requestID: UInt64?
    if parts.count == 4 || parts.count == 6 {
      guard let parsedID = UInt64(parts[1]) else { return nil }
      requestID = parsedID
      parts.remove(at: 1)
    }
    guard parts.count >= 3, parts[0] == "accessibility",
      let target = percentDecodedString(parts[1]), !target.isEmpty,
      let kind = AccessibilityActionKind(rawValue: parts[2])
    else { return nil }
    let action: AccessibilityAction
    switch kind {
    case .focus, .activate, .increment, .decrement:
      guard parts.count == 3 else { return nil }
      switch kind {
      case .focus: action = .focus
      case .activate: action = .activate
      case .increment: action = .increment
      default: action = .decrement
      }
    case .setValue:
      guard parts.count == 5, let rawValue = percentDecodedString(parts[4]) else { return nil }
      switch parts[3] {
      case "text": action = .setValue(.text(rawValue))
      case "boolean":
        guard rawValue == "true" || rawValue == "false" else { return nil }
        action = .setValue(.boolean(rawValue == "true"))
      case "number":
        guard let number = Double(rawValue), number.isFinite else { return nil }
        action = .setValue(.number(number))
      default: return nil
      }
    }
    return .init(target: target, action: action, requestID: requestID)
  }

  private static func percentDecodedString(
    _ text: String
  ) -> String? {
    var bytes: [UInt8] = []
    let source = Array(text.utf8)
    var index = 0

    while index < source.count {
      let byte = source[index]
      if byte == 0x25 {
        guard index + 2 < source.count,
          let high = hexadecimalValue(source[index + 1]),
          let low = hexadecimalValue(source[index + 2])
        else {
          return nil
        }
        bytes.append(UInt8(high * 16 + low))
        index += 3
      } else {
        bytes.append(byte)
        index += 1
      }
    }

    return String(validating: bytes, as: UTF8.self)
  }

  private static func hexadecimalValue(
    _ byte: UInt8
  ) -> Int? {
    switch byte {
    case 0x30...0x39:
      return Int(byte - 0x30)
    case 0x41...0x46:
      return Int(byte - 0x41 + 10)
    case 0x61...0x66:
      return Int(byte - 0x61 + 10)
    default:
      return nil
    }
  }
}

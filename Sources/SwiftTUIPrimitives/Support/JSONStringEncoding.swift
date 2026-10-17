/// Shared JSON string spelling and byte accounting at host boundaries.
/// Control scalars are escaped even when JSON would permit their raw form.
package enum JSONStringEncoding {
  package static func quoted(_ text: String) -> String { "\"" + contents(text) + "\"" }

  package static func contents(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)
    for scalar in text.unicodeScalars {
      if let escape = escape(for: scalar) {
        result += escape
      } else {
        result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  package static func byteCount(of scalar: Unicode.Scalar) -> Int {
    if let escape = escape(for: scalar) { return escape.utf8.count }
    switch scalar.value {
    case 0...0x7F: return 1
    case 0...0x7FF: return 2
    case 0...0xFFFF: return 3
    default: return 4
    }
  }

  private static func escape(for scalar: Unicode.Scalar) -> String? {
    switch scalar.value {
    case 0x22: return "\\\""
    case 0x5C: return "\\\\"
    case 0x08: return "\\b"
    case 0x0C: return "\\f"
    case 0x0A: return "\\n"
    case 0x0D: return "\\r"
    case 0x09: return "\\t"
    case 0x00...0x1F, 0x7F...0x9F:
      let hex = String(scalar.value, radix: 16, uppercase: true)
      return "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
    default: return nil
    }
  }
}

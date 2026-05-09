/// Host capability for clipboard writes initiated by authored views or embedded clients.
public protocol ClipboardWritingPresentationSurface: AnyObject {
  @discardableResult
  @MainActor
  func writeClipboard(_ text: String) throws -> Bool
}

package func terminalClipboardSequence(
  for text: String
) -> String {
  "\u{001B}]52;c;\(terminalClipboardBase64Encoded(Array(text.utf8)))\u{0007}"
}

private func terminalClipboardBase64Encoded(
  _ bytes: [UInt8]
) -> String {
  guard !bytes.isEmpty else {
    return ""
  }

  let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
  var result: [UInt8] = []
  result.reserveCapacity(((bytes.count + 2) / 3) * 4)

  var index = 0
  while index < bytes.count {
    let first = Int(bytes[index])
    let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
    let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
    let combined = (first << 16) | (second << 8) | third

    result.append(alphabet[(combined >> 18) & 0x3F])
    result.append(alphabet[(combined >> 12) & 0x3F])
    result.append(index + 1 < bytes.count ? alphabet[(combined >> 6) & 0x3F] : UInt8(ascii: "="))
    result.append(index + 2 < bytes.count ? alphabet[combined & 0x3F] : UInt8(ascii: "="))
    index += 3
  }

  return String(decoding: result, as: UTF8.self)
}

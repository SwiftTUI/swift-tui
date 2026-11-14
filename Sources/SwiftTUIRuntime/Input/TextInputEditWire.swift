/// Parser for a host input method's full-state edit record.
///
/// The record carries the complete text of the focused editor after one input
/// method edit, its directed selection, and its composing (marked) range:
///
/// ```text
/// textInput:<requestID>:<target>:<text>:<anchor>:<head>:<compositionStart>:<compositionEnd>
/// ```
///
/// `target` and `text` are percent-encoded UTF-8. Offsets are decimal UTF-16
/// code units of `text`; `-1:-1` means nothing is composing. Framing (RS and
/// LF) belongs to the host ingress. The parsed request is an ordinary
/// correlated `editText` action, so target lifetime, modal scope, enablement
/// and the frame acknowledgement follow the assistive action contract.
/// A malformed record never becomes terminal input.
package enum TextInputEditWire {
  package static func parseCommand(_ text: String) -> AccessibilityActionRequest? {
    guard text.utf8.count <= HostWireBudget.recordBytes else { return nil }
    let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 8, parts[0] == "textInput",
      let requestID = HostContract.uint64(parts[1]),
      let target = AccessibilityActionWire.percentDecodedString(parts[2]), !target.isEmpty,
      let text = AccessibilityActionWire.percentDecodedString(parts[3]),
      let anchor = offset(parts[4]), let head = offset(parts[5])
    else { return nil }
    let composition: Range<Int>?
    if parts[6] == "-1", parts[7] == "-1" {
      composition = nil
    } else {
      guard let start = offset(parts[6]), let end = offset(parts[7]), start <= end else {
        return nil
      }
      composition = start..<end
    }
    return AccessibilityActionRequest(
      target: target,
      action: .editText(
        .init(
          text: text, anchor: anchor, head: head,
          inputMethod: .init(composition: composition))),
      requestID: requestID)
  }

  /// A canonical nonnegative decimal offset: ASCII digits only, so a sign,
  /// a separator or a non-ASCII digit cannot pass as a position.
  private static func offset(_ text: String) -> Int? {
    guard (1...10).contains(text.utf8.count),
      text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 })
    else { return nil }
    return Int(text)
  }
}

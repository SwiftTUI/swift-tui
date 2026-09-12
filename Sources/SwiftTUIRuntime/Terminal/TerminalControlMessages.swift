public enum TerminalControlMessage: Equatable, Sendable {
  case resize(CellSize)
  case style(TerminalRenderStyle)
}

package struct ControlMessageParser {
  private static let introducer: UInt8 = 0x1E
  private var bufferedCommand: [UInt8]? = nil
  private var isPasting = false
  private var pasteBoundaryOffset = 0
  private static let pasteStart: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
  private static let pasteEnd: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]

  package init() {}

  package mutating func feed(
    _ bytes: [UInt8]
  ) -> (payload: [UInt8], messages: [TerminalControlMessage]) {
    var payload: [UInt8] = []
    payload.reserveCapacity(bytes.count)
    var messages: [TerminalControlMessage] = []

    for byte in bytes {
      if bufferedCommand != nil {
        if byte == 0x0A {
          if let message = parseBufferedCommand() {
            messages.append(message)
          }
          bufferedCommand = nil
        } else if byte == Self.introducer {
          bufferedCommand = []
        } else {
          bufferedCommand?.append(byte)
        }
        continue
      }

      if !isPasting, byte == Self.introducer {
        bufferedCommand = []
        continue
      }

      payload.append(byte)
      // Bracketed paste is an opaque payload even on an armed transport.
      // Match on the bytes we forward, retaining partial delimiters across
      // reads; a nested paste start inside the payload has no special role.
      let boundary = isPasting ? Self.pasteEnd : Self.pasteStart
      if byte == boundary[pasteBoundaryOffset] {
        pasteBoundaryOffset += 1
        if pasteBoundaryOffset == boundary.count {
          isPasting.toggle()
          pasteBoundaryOffset = 0
        }
      } else {
        pasteBoundaryOffset = byte == boundary[0] ? 1 : 0
      }
    }

    return (payload, messages)
  }

  private func parseBufferedCommand() -> TerminalControlMessage? {
    guard let bufferedCommand else {
      return nil
    }

    let text = String(decoding: bufferedCommand, as: UTF8.self)
    if let message = parseResizeCommand(text) {
      return message
    }

    if let message = parseStyleCommand(text) {
      return message
    }

    return nil
  }

  private func parseResizeCommand(
    _ text: String
  ) -> TerminalControlMessage? {
    let components = text.split(separator: ":")
    guard components.count == 3, components[0] == "resize",
      let width = Int(components[1]),
      let height = Int(components[2])
    else {
      return nil
    }

    return .resize(
      .init(
        width: max(1, width),
        height: max(1, height)
      )
    )
  }

  private func parseStyleCommand(
    _ text: String
  ) -> TerminalControlMessage? {
    let prefix = "style:"
    guard text.hasPrefix(prefix) else {
      return nil
    }

    let encoded = String(text.dropFirst(prefix.count))
    guard let style = TerminalRenderStyleCodec.decodeBase64(encoded) else {
      return nil
    }
    return .style(style)
  }
}

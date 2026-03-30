public enum TerminalControlMessage: Equatable, Sendable {
  case resize(Size)
}

package struct ControlMessageParser {
  private static let introducer: UInt8 = 0x1E
  private var bufferedCommand: [UInt8]? = nil

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
        } else {
          bufferedCommand?.append(byte)
        }
        continue
      }

      if byte == Self.introducer {
        bufferedCommand = []
        continue
      }

      payload.append(byte)
    }

    return (payload, messages)
  }

  private func parseBufferedCommand() -> TerminalControlMessage? {
    guard let bufferedCommand else {
      return nil
    }

    let text = String(decoding: bufferedCommand, as: UTF8.self)
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
}

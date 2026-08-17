// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
  import Foundation

  /// RFC 6455 wire-level pieces: the handshake accept key, the frame codec, and
  /// the fragment assembler. Everything here is pure — bytes in, values out —
  /// so the protocol logic is testable without a socket.
  enum WebHostWebSocketWire {
    static let handshakeGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// Frame payload ceiling, shared with the assembler's message ceiling: a
    /// single frame larger than the largest acceptable message can never
    /// complete one, so it is refused at the header instead of buffered.
    static let maxPayloadBytes = 8 * 1024 * 1024

    enum Opcode: UInt8, Equatable, Sendable {
      case continuation = 0x0
      case text = 0x1
      case binary = 0x2
      case close = 0x8
      case ping = 0x9
      case pong = 0xA
    }

    static func acceptKey(
      forClientKey clientKey: String
    ) -> String {
      let digest = WebHostSHA1.digest(Array((clientKey + handshakeGUID).utf8))
      return Data(digest).base64EncodedString()
    }

    /// One unmasked, unfragmented server frame.
    static func encodeFrame(
      opcode: Opcode,
      payload: [UInt8]
    ) -> [UInt8] {
      var frame: [UInt8] = [0x80 | opcode.rawValue]
      if payload.count <= 125 {
        frame.append(UInt8(payload.count))
      } else if payload.count <= 0xFFFF {
        frame.append(126)
        frame.append(UInt8(truncatingIfNeeded: payload.count >> 8))
        frame.append(UInt8(truncatingIfNeeded: payload.count))
      } else {
        frame.append(127)
        for shift in stride(from: 56, through: 0, by: -8) {
          frame.append(UInt8(truncatingIfNeeded: payload.count >> shift))
        }
      }
      frame.append(contentsOf: payload)
      return frame
    }

    static func encodeClose(
      code: UInt16,
      reason: String
    ) -> [UInt8] {
      var payload: [UInt8] = [
        UInt8(truncatingIfNeeded: code >> 8),
        UInt8(truncatingIfNeeded: code),
      ]
      // A close payload is capped at 125 bytes; two are the code.
      payload.append(contentsOf: Array(reason.utf8).prefix(123))
      return encodeFrame(opcode: .close, payload: payload)
    }

    struct Frame: Equatable, Sendable {
      var fin: Bool
      var opcode: Opcode
      var payload: [UInt8]
    }

    enum DecodeError: Error, Equatable, Sendable {
      case reservedBitsSet
      case unknownOpcode(UInt8)
      case unmaskedClientFrame
      case fragmentedControlFrame
      case oversizedControlFrame
      case payloadTooLarge(declared: Int)
    }

    /// Incremental frame decoder for the client-to-server direction: feed raw
    /// bytes, pull complete frames. Client frames must be masked.
    struct FrameDecoder: Sendable {
      private var buffer: [UInt8] = []
      private var consumedOffset = 0

      init() {}

      mutating func append(
        _ bytes: some Sequence<UInt8>
      ) {
        if consumedOffset > 0 {
          buffer.removeFirst(consumedOffset)
          consumedOffset = 0
        }
        buffer.append(contentsOf: bytes)
      }

      mutating func nextFrame() throws(DecodeError) -> Frame? {
        let available = buffer.count - consumedOffset
        guard available >= 2 else {
          return nil
        }
        let first = buffer[consumedOffset]
        let second = buffer[consumedOffset + 1]

        guard first & 0x70 == 0 else {
          throw .reservedBitsSet
        }
        guard let opcode = Opcode(rawValue: first & 0x0F) else {
          throw .unknownOpcode(first & 0x0F)
        }
        guard second & 0x80 != 0 else {
          throw .unmaskedClientFrame
        }
        let fin = first & 0x80 != 0

        var headerLength = 2
        var payloadLength = Int(second & 0x7F)
        if payloadLength == 126 {
          headerLength += 2
          guard available >= headerLength else {
            return nil
          }
          payloadLength =
            (Int(buffer[consumedOffset + 2]) << 8) | Int(buffer[consumedOffset + 3])
        } else if payloadLength == 127 {
          headerLength += 8
          guard available >= headerLength else {
            return nil
          }
          var length = 0
          for byteIndex in 0..<8 {
            let byte = Int(buffer[consumedOffset + 2 + byteIndex])
            guard length <= (Int.max >> 8) else {
              throw .payloadTooLarge(declared: Int.max)
            }
            length = (length << 8) | byte
          }
          payloadLength = length
        }

        if isControl(opcode) {
          guard fin else {
            throw .fragmentedControlFrame
          }
          guard payloadLength <= 125 else {
            throw .oversizedControlFrame
          }
        }
        // Refused at the header: buffering an over-limit payload just to refuse
        // the assembled message would let a hostile client hold 8 MiB hostage
        // per frame.
        guard payloadLength <= maxPayloadBytes else {
          throw .payloadTooLarge(declared: payloadLength)
        }

        let maskLength = 4
        let frameLength = headerLength + maskLength + payloadLength
        guard available >= frameLength else {
          return nil
        }

        let maskStart = consumedOffset + headerLength
        let payloadStart = maskStart + maskLength
        var payload = [UInt8](repeating: 0, count: payloadLength)
        for index in 0..<payloadLength {
          payload[index] = buffer[payloadStart + index] ^ buffer[maskStart + (index & 3)]
        }

        consumedOffset += frameLength
        return Frame(fin: fin, opcode: opcode, payload: payload)
      }

      private func isControl(
        _ opcode: Opcode
      ) -> Bool {
        switch opcode {
        case .close, .ping, .pong:
          return true
        case .continuation, .text, .binary:
          return false
        }
      }
    }

    enum AssembledEvent: Equatable, Sendable {
      case message(WebHostSocketMessage)
      case ping(payload: [UInt8])
      case pong
      case closeReceived
    }

    enum AssemblyError: Error, Equatable, Sendable {
      case continuationWithoutStart
      case newMessageDuringFragmentation
      case invalidTextEncoding
      case messageTooLarge(limit: Int)
    }

    /// Reassembles fragmented messages and classifies control frames. Control
    /// frames may interleave between fragments; data frames may not.
    struct MessageAssembler: Sendable {
      private var fragmentOpcode: Opcode?
      private var fragmentPayload: [UInt8] = []
      private let maxMessageBytes: Int

      init(
        maxMessageBytes: Int
      ) {
        self.maxMessageBytes = maxMessageBytes
      }

      mutating func assemble(
        _ frame: Frame
      ) throws(AssemblyError) -> AssembledEvent? {
        switch frame.opcode {
        case .ping:
          return .ping(payload: frame.payload)
        case .pong:
          return .pong
        case .close:
          return .closeReceived
        case .text, .binary:
          guard fragmentOpcode == nil else {
            throw .newMessageDuringFragmentation
          }
          if frame.fin {
            return try completedMessage(opcode: frame.opcode, payload: frame.payload)
          }
          try checkAggregateSize(frame.payload.count)
          fragmentOpcode = frame.opcode
          fragmentPayload = frame.payload
          return nil
        case .continuation:
          guard let opcode = fragmentOpcode else {
            throw .continuationWithoutStart
          }
          try checkAggregateSize(fragmentPayload.count + frame.payload.count)
          fragmentPayload.append(contentsOf: frame.payload)
          if frame.fin {
            let payload = fragmentPayload
            fragmentOpcode = nil
            fragmentPayload = []
            return try completedMessage(opcode: opcode, payload: payload)
          }
          return nil
        }
      }

      private func completedMessage(
        opcode: Opcode,
        payload: [UInt8]
      ) throws(AssemblyError) -> AssembledEvent {
        try checkAggregateSize(payload.count)
        switch opcode {
        case .text:
          guard let text = String(bytes: payload, encoding: .utf8) else {
            throw .invalidTextEncoding
          }
          return .message(.text(text))
        default:
          return .message(.data(payload))
        }
      }

      private func checkAggregateSize(
        _ count: Int
      ) throws(AssemblyError) {
        guard count <= maxMessageBytes else {
          throw .messageTooLarge(limit: maxMessageBytes)
        }
      }
    }
  }
#endif

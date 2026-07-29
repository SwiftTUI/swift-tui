/// Host-declared wire capabilities: what a connected host has said it can
/// accept beyond today's deployed defaults.
///
/// This is the single Swift-side currency behind the three capability
/// ingresses (WASI environment keys, the WebSocket `caps:` control record,
/// and the Android `declareCapabilities` host call — see
/// ``HostWireSchema/capabilityMappings`` for the canonical key/ingress
/// manifest). The defaults reproduce today's behavior exactly: a host that
/// declares nothing gets today's bytes, byte for byte.
///
/// Capabilities are **named feature bits, not a version ceiling.** A record
/// shape newer than the deployed decoders may be emitted only after the host
/// declared that shape acceptable, and the safety net beneath that is
/// decoder-side: both deployed decoders hard-reject a `surface` record whose
/// `version` exceeds what they understand (the F57 skew guard), which does
/// not depend on a client declaring its ceiling honestly. A declared ceiling
/// would be a second, weaker copy of that guard — and, being an integer only
/// ever compared against one threshold, a boolean wearing an integer.
package struct HostWireCapabilities: Equatable, Sendable {
  /// Whether the host accepts v3 `deltaRows` surface records. The one bit
  /// the declaration carries: it gates the delta record shape and nothing
  /// else.
  package var acceptsDeltaFrames: Bool

  package init(
    acceptsDeltaFrames: Bool = false
  ) {
    self.acceptsDeltaFrames = acceptsDeltaFrames
  }

  /// The encoding state a host with these capabilities receives.
  ///
  /// Constructing one **always** re-anchors the delta baseline and the
  /// transmitted-image set: a declaration marks a connection epoch. That is
  /// why every transport routes both its undeclared default and its
  /// post-declaration reset through here rather than building an encoding
  /// state itself — a transport that assembles its own can, and once did,
  /// disagree with the declaration it was handed.
  package func negotiatedEncodingState() -> HostWireEncodingState {
    HostWireEncodingState(deltaEnabled: acceptsDeltaFrames)
  }

  /// Parses the JSON object payload of a `caps:` declaration.
  ///
  /// Tolerant by policy: unknown keys are skipped (including nested
  /// containers, so future declarations can carry structured values without
  /// breaking older parsers), known keys with mistyped values are ignored,
  /// and any malformed payload returns `nil` — the caller keeps the
  /// defaults, which is exactly the absence-means-today contract. Hand
  /// parsed because this type ships in the WASI-compiled runtime, which
  /// carries no JSON dependency.
  ///
  /// The tolerance is load-bearing for retirement, not just for growth: the
  /// retired `maxWebSurfaceVersion` and `supportsResync` keys now fall
  /// through to the unknown-key skip, so a client still sending either one
  /// parses exactly as if it had not. That is what lets the Swift side land
  /// this collapse ahead of the clients that emit those keys.
  package static func fromDeclarationJSON(
    _ text: String
  ) -> HostWireCapabilities? {
    var scanner = CapsJSONScanner(text)
    scanner.skipWhitespace()
    guard scanner.consume("{") else {
      return nil
    }

    var capabilities = HostWireCapabilities()
    scanner.skipWhitespace()
    if scanner.consume("}") {
      scanner.skipWhitespace()
      return scanner.isAtEnd ? capabilities : nil
    }

    while true {
      scanner.skipWhitespace()
      guard let key = scanner.consumeString() else {
        return nil
      }
      scanner.skipWhitespace()
      guard scanner.consume(":") else {
        return nil
      }
      scanner.skipWhitespace()

      switch key {
      case "acceptsDeltaFrames":
        if let value = scanner.consumeBool() {
          capabilities.acceptsDeltaFrames = value
        } else {
          guard scanner.skipValue() else { return nil }
        }
      default:
        guard scanner.skipValue() else {
          return nil
        }
      }

      scanner.skipWhitespace()
      if scanner.consume(",") {
        continue
      }
      guard scanner.consume("}") else {
        return nil
      }
      scanner.skipWhitespace()
      return scanner.isAtEnd ? capabilities : nil
    }
  }
}

/// A host request to repair delivery state without creating a new negotiated
/// connection epoch.
package struct HostWireResyncRequest: Equatable, Sendable {
  package enum Scope: Equatable, Sendable {
    case keyframe
    /// An empty list requests every image payload.
    case images([String])
  }

  package let scope: Scope

  package init(scope: Scope) {
    self.scope = scope
  }

  /// Parses the JSON object payload of a `resync:` control record.
  ///
  /// Unknown keys are ignored for additive compatibility. Known keys and the
  /// scope token are strict so malformed repair requests cannot accidentally
  /// invalidate broader encoder state.
  package static func fromRequestJSON(
    _ text: String
  ) -> HostWireResyncRequest? {
    var scanner = CapsJSONScanner(text)
    scanner.skipWhitespace()
    guard scanner.consume("{") else {
      return nil
    }

    var scope: String?
    var imageIDs: [String]?
    scanner.skipWhitespace()
    if scanner.consume("}") {
      return nil
    }

    while true {
      scanner.skipWhitespace()
      guard let key = scanner.consumeString() else {
        return nil
      }
      scanner.skipWhitespace()
      guard scanner.consume(":") else {
        return nil
      }
      scanner.skipWhitespace()

      switch key {
      case "scope":
        guard let value = scanner.consumeString() else {
          return nil
        }
        scope = value
      case "ids":
        guard let value = scanner.consumeStringArray() else {
          return nil
        }
        imageIDs = value
      default:
        guard scanner.skipValue() else {
          return nil
        }
      }

      scanner.skipWhitespace()
      if scanner.consume(",") {
        continue
      }
      guard scanner.consume("}") else {
        return nil
      }
      scanner.skipWhitespace()
      guard scanner.isAtEnd else {
        return nil
      }
      switch scope {
      case "keyframe":
        return HostWireResyncRequest(scope: .keyframe)
      case "images":
        return HostWireResyncRequest(scope: .images(imageIDs ?? []))
      default:
        return nil
      }
    }
  }
}

/// Minimal JSON scanner for the `caps:` and `resync:` objects. It validates
/// the full grammar of skipped values, including nested containers, so
/// unknown future keys remain additive without admitting malformed records.
private struct CapsJSONScanner {
  private let scalars: [Unicode.Scalar]
  private var index = 0

  init(_ text: String) {
    scalars = Array(text.unicodeScalars)
  }

  var isAtEnd: Bool {
    index >= scalars.count
  }

  mutating func skipWhitespace() {
    while index < scalars.count {
      switch scalars[index] {
      case " ", "\t", "\n", "\r":
        index += 1
      default:
        return
      }
    }
  }

  mutating func consume(
    _ scalar: Unicode.Scalar
  ) -> Bool {
    guard index < scalars.count, scalars[index] == scalar else {
      return false
    }
    index += 1
    return true
  }

  mutating func consumeString() -> String? {
    guard consume("\"") else {
      return nil
    }
    var value = String.UnicodeScalarView()
    while index < scalars.count {
      let scalar = scalars[index]
      index += 1
      if scalar == "\"" {
        return String(value)
      }
      if scalar == "\\" {
        guard index < scalars.count else {
          return nil
        }
        let escaped = scalars[index]
        index += 1
        switch escaped {
        case "\"", "\\", "/":
          value.append(escaped)
        case "b":
          value.append("\u{0008}")
        case "f":
          value.append("\u{000C}")
        case "n":
          value.append("\n")
        case "t":
          value.append("\t")
        case "r":
          value.append("\r")
        case "u":
          guard let firstCodeUnit = consumeHexCodeUnit() else {
            return nil
          }
          let scalarValue: UInt32
          if (0xD800...0xDBFF).contains(firstCodeUnit) {
            guard consume("\\"), consume("u"),
              let secondCodeUnit = consumeHexCodeUnit(),
              (0xDC00...0xDFFF).contains(secondCodeUnit)
            else {
              return nil
            }
            scalarValue =
              0x1_0000
              + (UInt32(firstCodeUnit - 0xD800) << 10)
              + UInt32(secondCodeUnit - 0xDC00)
          } else {
            guard !(0xDC00...0xDFFF).contains(firstCodeUnit) else {
              return nil
            }
            scalarValue = UInt32(firstCodeUnit)
          }
          guard let decoded = Unicode.Scalar(scalarValue) else {
            return nil
          }
          value.append(decoded)
        default:
          return nil
        }
        continue
      }
      guard scalar.value >= 0x20 else {
        return nil
      }
      value.append(scalar)
    }
    return nil
  }

  private mutating func consumeHexCodeUnit() -> UInt16? {
    guard index + 4 <= scalars.count else {
      return nil
    }
    var value: UInt16 = 0
    for _ in 0..<4 {
      let scalar = scalars[index]
      let digit: UInt16
      switch scalar.value {
      case 0x30...0x39:
        digit = UInt16(scalar.value - 0x30)
      case 0x41...0x46:
        digit = UInt16(scalar.value - 0x41 + 10)
      case 0x61...0x66:
        digit = UInt16(scalar.value - 0x61 + 10)
      default:
        return nil
      }
      value = (value << 4) | digit
      index += 1
    }
    return value
  }

  private mutating func consumeNumber() -> Bool {
    let start = index
    _ = consume("-")
    guard index < scalars.count else {
      index = start
      return false
    }

    if scalars[index] == "0" {
      index += 1
      if index < scalars.count, ("0"..."9").contains(scalars[index]) {
        index = start
        return false
      }
    } else if ("1"..."9").contains(scalars[index]) {
      repeat {
        index += 1
      } while index < scalars.count && ("0"..."9").contains(scalars[index])
    } else {
      index = start
      return false
    }

    if consume(".") {
      guard index < scalars.count, ("0"..."9").contains(scalars[index]) else {
        index = start
        return false
      }
      repeat {
        index += 1
      } while index < scalars.count && ("0"..."9").contains(scalars[index])
    }

    if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
      index += 1
      if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" {
        index += 1
      }
      guard index < scalars.count, ("0"..."9").contains(scalars[index]) else {
        index = start
        return false
      }
      repeat {
        index += 1
      } while index < scalars.count && ("0"..."9").contains(scalars[index])
    }
    return true
  }

  mutating func consumeBool() -> Bool? {
    if consumeLiteral("true") {
      return true
    }
    if consumeLiteral("false") {
      return false
    }
    return nil
  }

  mutating func consumeStringArray() -> [String]? {
    guard consume("[") else {
      return nil
    }
    skipWhitespace()
    if consume("]") {
      return []
    }

    var values: [String] = []
    while true {
      skipWhitespace()
      guard let value = consumeString() else {
        return nil
      }
      values.append(value)
      skipWhitespace()
      if consume(",") {
        continue
      }
      guard consume("]") else {
        return nil
      }
      return values
    }
  }

  private mutating func consumeLiteral(
    _ literal: String
  ) -> Bool {
    let literalScalars = Array(literal.unicodeScalars)
    guard index + literalScalars.count <= scalars.count else {
      return false
    }
    for (offset, scalar) in literalScalars.enumerated()
    where scalars[index + offset] != scalar {
      return false
    }
    index += literalScalars.count
    return true
  }

  /// Skips one well-formed JSON value of any shape. Nesting is capped so an
  /// untrusted control record cannot exhaust the native stack.
  mutating func skipValue(
    nestingDepth: Int = 0
  ) -> Bool {
    skipWhitespace()
    guard index < scalars.count else {
      return false
    }
    switch scalars[index] {
    case "\"":
      return consumeString() != nil
    case "{":
      return skipObject(nestingDepth: nestingDepth)
    case "[":
      return skipArray(nestingDepth: nestingDepth)
    default:
      if consumeBool() != nil {
        return true
      }
      if consumeLiteral("null") {
        return true
      }
      return consumeNumber()
    }
  }

  private mutating func skipObject(
    nestingDepth: Int
  ) -> Bool {
    guard nestingDepth < 128, consume("{") else {
      return false
    }
    skipWhitespace()
    if consume("}") {
      return true
    }
    while true {
      skipWhitespace()
      guard consumeString() != nil else {
        return false
      }
      skipWhitespace()
      guard consume(":") else {
        return false
      }
      guard skipValue(nestingDepth: nestingDepth + 1) else {
        return false
      }
      skipWhitespace()
      if consume(",") {
        continue
      }
      return consume("}")
    }
  }

  private mutating func skipArray(
    nestingDepth: Int
  ) -> Bool {
    guard nestingDepth < 128, consume("[") else {
      return false
    }
    skipWhitespace()
    if consume("]") {
      return true
    }
    while true {
      guard skipValue(nestingDepth: nestingDepth + 1) else {
        return false
      }
      skipWhitespace()
      if consume(",") {
        continue
      }
      return consume("]")
    }
  }
}

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

/// Minimal JSON scanner for the flat `caps:` declaration object. Recognizes
/// strings, integers, booleans, and null as values, and skips balanced
/// nested containers so unknown future keys cannot wedge the parse.
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
        case "n":
          value.append("\n")
        case "t":
          value.append("\t")
        case "r":
          value.append("\r")
        default:
          // Escapes the declaration never needs (\b, \f, \uXXXX): reject
          // rather than mis-decode.
          return nil
        }
        continue
      }
      value.append(scalar)
    }
    return nil
  }

  mutating func consumeInteger() -> Int? {
    var digits = ""
    let start = index
    if index < scalars.count, scalars[index] == "-" {
      digits.unicodeScalars.append(scalars[index])
      index += 1
    }
    while index < scalars.count, ("0"..."9").contains(scalars[index]) {
      digits.unicodeScalars.append(scalars[index])
      index += 1
    }
    guard let value = Int(digits) else {
      index = start
      return nil
    }
    return value
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

  /// Skips one well-formed JSON value of any shape, including balanced
  /// nested objects/arrays. Returns false when the value is malformed.
  mutating func skipValue() -> Bool {
    skipWhitespace()
    guard index < scalars.count else {
      return false
    }
    switch scalars[index] {
    case "\"":
      return consumeString() != nil
    case "{", "[":
      var depth = 0
      while index < scalars.count {
        let scalar = scalars[index]
        switch scalar {
        case "\"":
          guard consumeString() != nil else {
            return false
          }
          continue
        case "{", "[":
          depth += 1
        case "}", "]":
          depth -= 1
          if depth == 0 {
            index += 1
            return true
          }
        default:
          break
        }
        index += 1
      }
      return false
    default:
      if consumeBool() != nil {
        return true
      }
      if consumeLiteral("null") {
        return true
      }
      if consumeInteger() != nil {
        // Tolerate a fractional/exponent tail on numbers we skip.
        while index < scalars.count,
          scalars[index] == "." || scalars[index] == "e" || scalars[index] == "E"
            || scalars[index] == "+" || scalars[index] == "-"
            || ("0"..."9").contains(scalars[index])
        {
          index += 1
        }
        return true
      }
      return false
    }
  }
}

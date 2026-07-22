/// Host-declared wire capabilities: what a connected host has said it can
/// accept beyond today's deployed defaults.
///
/// This is the single Swift-side currency behind the three capability
/// ingresses (WASI environment keys, the WebSocket `caps:` control record,
/// and the Android `declareCapabilities` host call — see
/// ``HostWireSchema/capabilityMappings`` for the canonical field/ingress
/// manifest). The defaults reproduce today's behavior exactly: a host that
/// declares nothing gets today's bytes, byte for byte. Anything newer than
/// the deployed decoder versions may be emitted **only** after the host has
/// declared it acceptable here — deployed decoders hard-reject unknown
/// versions, so a version literal must never move outside a
/// capability-gated branch.
package struct HostWireCapabilities: Equatable, Sendable {
  /// Highest web `surface` record version the host accepts. Deployed
  /// decoders hard-match `1|2` (full) and `3` (delta).
  package var maxWebSurfaceVersion: Int
  /// Whether the host accepts v3 `deltaRows` surface records.
  package var acceptsDeltaFrames: Bool
  /// Whether the host understands the resync flow (encoder-state reset +
  /// full keyframe re-transmission). Semantics land with the resync stage;
  /// until a consumer exists this is plumbing only.
  package var supportsResync: Bool
  /// Highest Android `schemaVersion` the host accepts. The deployed decoder
  /// hard-rejects anything newer than its supported version.
  package var maxAndroidSchemaVersion: Int

  package init(
    maxWebSurfaceVersion: Int = 2,
    acceptsDeltaFrames: Bool = false,
    supportsResync: Bool = false,
    maxAndroidSchemaVersion: Int = 2
  ) {
    self.maxWebSurfaceVersion = maxWebSurfaceVersion
    self.acceptsDeltaFrames = acceptsDeltaFrames
    self.supportsResync = supportsResync
    self.maxAndroidSchemaVersion = maxAndroidSchemaVersion
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
      case "maxWebSurfaceVersion":
        if let value = scanner.consumeInteger() {
          capabilities.maxWebSurfaceVersion = value
        } else {
          guard scanner.skipValue() else { return nil }
        }
      case "acceptsDeltaFrames":
        if let value = scanner.consumeBool() {
          capabilities.acceptsDeltaFrames = value
        } else {
          guard scanner.skipValue() else { return nil }
        }
      case "supportsResync":
        if let value = scanner.consumeBool() {
          capabilities.supportsResync = value
        } else {
          guard scanner.skipValue() else { return nil }
        }
      case "maxAndroidSchemaVersion":
        if let value = scanner.consumeInteger() {
          capabilities.maxAndroidSchemaVersion = value
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

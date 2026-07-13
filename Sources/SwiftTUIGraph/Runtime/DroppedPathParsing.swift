/// Parses a bracketed-paste burst into an ordered list of dropped
/// paths. Accepts the three forms macOS terminals emit when a file is
/// dragged into them: backslash-escaped POSIX paths, single-quoted
/// POSIX paths, and `file://`-prefixed URLs with percent-encoding.
///
/// Returns an empty list for input that contains no path-shaped
/// tokens; callers treat empty as "not a drop, fall through to text
/// paste". A token is considered path-shaped when it starts with `/`
/// or `~`, or when it is a `file://`-prefixed URL (the URL decodes to
/// an absolute POSIX path). Pasted text that happens to be
/// whitespace-separated words (e.g. "plain typed text") yields an
/// empty result so bracketed paste of ordinary prose still falls
/// through to the character-input pipeline.
public func parseDroppedPaths(_ pasted: String) -> [DroppedPath] {
  var results: [DroppedPath] = []
  var current = ""
  var currentIsQuoted = false
  var index = pasted.startIndex
  let end = pasted.endIndex

  func flushCurrent() {
    defer {
      current.removeAll(keepingCapacity: true)
      currentIsQuoted = false
    }
    guard !current.isEmpty else { return }
    let decoded = decodeFileURLIfNeeded(current)
    // A token is path-shaped only if it starts with `/` or `~`.
    // Single-quoted segments also count — terminals quote paths that
    // contain spaces, and quoted prose is extremely unusual here.
    guard looksLikePath(decoded) || currentIsQuoted else { return }
    results.append(DroppedPath(decoded))
  }

  while index < end {
    let character = pasted[index]
    switch character {
    case " ", "\t", "\n", "\r":
      flushCurrent()
      index = pasted.index(after: index)
    case "\\":
      let next = pasted.index(after: index)
      if next < end {
        current.append(pasted[next])
        index = pasted.index(after: next)
      } else {
        index = pasted.index(after: index)
      }
    case "'":
      currentIsQuoted = true
      var inside = pasted.index(after: index)
      while inside < end, pasted[inside] != "'" {
        current.append(pasted[inside])
        inside = pasted.index(after: inside)
      }
      index = inside < end ? pasted.index(after: inside) : inside
    default:
      current.append(character)
      index = pasted.index(after: index)
    }
  }
  flushCurrent()
  return results
}

private func looksLikePath(_ token: String) -> Bool {
  guard let first = token.first else { return false }
  return first == "/" || first == "~"
}

private func decodeFileURLIfNeeded(_ token: String) -> String {
  guard token.hasPrefix("file://") else { return token }
  let pathPart = String(token.dropFirst("file://".count))
  return percentDecode(pathPart)
}

private func percentDecode(_ input: String) -> String {
  var output = ""
  output.reserveCapacity(input.count)
  var byteBuffer: [UInt8] = []

  func flushBytes() {
    guard !byteBuffer.isEmpty else { return }
    appendMixedUTF8AndLatin1(byteBuffer, to: &output)
    byteBuffer.removeAll(keepingCapacity: true)
  }

  var scalars = input.unicodeScalars.makeIterator()
  while let scalar = scalars.next() {
    guard scalar == "%" else {
      flushBytes()
      output.unicodeScalars.append(scalar)
      continue
    }
    guard let hi = scalars.next() else {
      flushBytes()
      output.append("%")
      continue
    }
    guard let lo = scalars.next() else {
      flushBytes()
      output.append("%")
      output.unicodeScalars.append(hi)
      continue
    }
    guard let hiValue = hexValue(hi), let loValue = hexValue(lo) else {
      flushBytes()
      output.append("%")
      output.unicodeScalars.append(hi)
      output.unicodeScalars.append(lo)
      continue
    }
    byteBuffer.append(UInt8(hiValue << 4 | loValue))
  }
  flushBytes()
  return output
}

/// Decodes every well-formed UTF-8 subsequence while preserving each malformed
/// byte as its corresponding Latin-1 scalar. A single bad byte must not force
/// otherwise valid neighboring multibyte sequences through the fallback path.
private func appendMixedUTF8AndLatin1(
  _ bytes: [UInt8],
  to output: inout String
) {
  var index = 0
  while index < bytes.count {
    if let length = validUTF8SequenceLength(in: bytes, at: index) {
      let end = index + length
      if let decoded = String(validating: Array(bytes[index..<end]), as: UTF8.self) {
        output.append(decoded)
        index = end
        continue
      }
    }

    output.unicodeScalars.append(UnicodeScalar(bytes[index]))
    index += 1
  }
}

private func validUTF8SequenceLength(
  in bytes: [UInt8],
  at index: Int
) -> Int? {
  let lead = bytes[index]
  if lead < 0x80 {
    return 1
  }

  func continuation(_ offset: Int, in range: ClosedRange<UInt8> = 0x80...0xBF) -> Bool {
    let position = index + offset
    return position < bytes.count && range.contains(bytes[position])
  }

  switch lead {
  case 0xC2...0xDF:
    return continuation(1) ? 2 : nil
  case 0xE0:
    return continuation(1, in: 0xA0...0xBF) && continuation(2) ? 3 : nil
  case 0xE1...0xEC, 0xEE...0xEF:
    return continuation(1) && continuation(2) ? 3 : nil
  case 0xED:
    return continuation(1, in: 0x80...0x9F) && continuation(2) ? 3 : nil
  case 0xF0:
    return continuation(1, in: 0x90...0xBF) && continuation(2) && continuation(3) ? 4 : nil
  case 0xF1...0xF3:
    return continuation(1) && continuation(2) && continuation(3) ? 4 : nil
  case 0xF4:
    return continuation(1, in: 0x80...0x8F) && continuation(2) && continuation(3) ? 4 : nil
  default:
    return nil
  }
}

private func hexValue(_ scalar: UnicodeScalar) -> UInt8? {
  switch scalar {
  case "0"..."9": return UInt8(scalar.value - UnicodeScalar("0").value)
  case "a"..."f": return UInt8(scalar.value - UnicodeScalar("a").value + 10)
  case "A"..."F": return UInt8(scalar.value - UnicodeScalar("A").value + 10)
  default: return nil
  }
}

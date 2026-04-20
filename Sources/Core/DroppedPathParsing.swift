/// Parses a bracketed-paste burst into an ordered list of dropped
/// paths. Accepts the three forms macOS terminals emit when a file is
/// dragged into them: backslash-escaped POSIX paths, single-quoted
/// POSIX paths, and `file://`-prefixed URLs with percent-encoding.
///
/// Returns an empty list for input that contains no path-shaped
/// tokens; callers treat empty as "not a drop, fall through to text
/// paste".
public func parseDroppedPaths(_ pasted: String) -> [DroppedPath] {
  var results: [DroppedPath] = []
  var current = ""
  var index = pasted.startIndex
  let end = pasted.endIndex

  func flushCurrent() {
    guard !current.isEmpty else { return }
    results.append(DroppedPath(decodeFileURLIfNeeded(current)))
    current.removeAll(keepingCapacity: true)
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
    if let decoded = String(validating: byteBuffer, as: UTF8.self) {
      output.append(decoded)
    } else {
      // Lossy fallback: emit each byte as its Latin-1 scalar.
      for byte in byteBuffer {
        output.unicodeScalars.append(UnicodeScalar(byte))
      }
    }
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

private func hexValue(_ scalar: UnicodeScalar) -> UInt8? {
  switch scalar {
  case "0"..."9": return UInt8(scalar.value - UnicodeScalar("0").value)
  case "a"..."f": return UInt8(scalar.value - UnicodeScalar("a").value + 10)
  case "A"..."F": return UInt8(scalar.value - UnicodeScalar("A").value + 10)
  default: return nil
  }
}

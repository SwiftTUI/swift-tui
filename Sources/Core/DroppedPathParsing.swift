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
  var scalars = input.unicodeScalars.makeIterator()
  while let scalar = scalars.next() {
    guard scalar == "%" else {
      output.unicodeScalars.append(scalar)
      continue
    }
    guard
      let hi = scalars.next(), let lo = scalars.next(),
      let hiValue = hexValue(hi), let loValue = hexValue(lo)
    else {
      output.append("%")
      continue
    }
    let byte = UInt8(hiValue << 4 | loValue)
    if let decoded = UnicodeScalar(UInt32(byte)) {
      output.unicodeScalars.append(decoded)
    }
  }
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

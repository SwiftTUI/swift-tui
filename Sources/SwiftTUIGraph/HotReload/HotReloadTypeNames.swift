/// Only driver-declared ABI module aliases may share a logical Codable schema.
/// User data and identity keys are never rewritten.
package enum HotReloadTypeNames {
  package static func canonical(_ name: String, aliases: [String: String]) -> String {
    guard !aliases.isEmpty else { return name }
    let bytes = Array(name.utf8)
    var result: [UInt8] = []
    var index = 0
    while index < bytes.count {
      let start = index
      while index < bytes.count, isIdentifier(bytes[index]) { index += 1 }
      if index > start {
        let token = String(decoding: bytes[start..<index], as: UTF8.self)
        let extensionPrefix = Array("(extension in ".utf8)
        let isExtensionModule =
          index < bytes.count && bytes[index] == 41
          && start >= extensionPrefix.count
          && bytes[(start - extensionPrefix.count)..<start].elementsEqual(extensionPrefix)
        let isQualifiedModule =
          index < bytes.count && bytes[index] == 46
          && (start == 0 || bytes[start - 1] != 46)
        if isQualifiedModule || isExtensionModule, let logical = aliases[token] {
          result.append(contentsOf: logical.utf8)
        } else {
          result.append(contentsOf: bytes[start..<index])
        }
      }
      if index < bytes.count {
        result.append(bytes[index])
        index += 1
      }
    }
    return String(decoding: result, as: UTF8.self)
  }

  private static func isIdentifier(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
      || byte == 95 || byte >= 128
  }
}

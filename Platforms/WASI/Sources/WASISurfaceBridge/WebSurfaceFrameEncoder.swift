@_spi(Runners) package import SwiftTUIRuntime

/// Container format the web-surface transport advertises to the JS
/// side. Mirrors the JSON `format` field on each transmitted image
/// record, and disambiguates the MIME type that the consumer will
/// pass to `Blob`/`<img>` when decoding.
enum WebSurfaceImageFormat: Sendable, Equatable {
  case png
  case jpeg
  case gif

  /// String that appears in the surface JSON's `format` field — and
  /// becomes the suffix of `image/<value>` in the consumer's MIME.
  var jsonValue: String {
    switch self {
    case .png: return "png"
    case .jpeg: return "jpeg"
    case .gif: return "gif"
    }
  }
}

package enum WebSurfaceFrameEncoder {
  package static func encodeClipboard(
    _ text: String
  ) -> String {
    "\u{001E}clipboard:{\"text\":\(jsonString(text))}\n"
  }

  package static func encodeRuntimeIssue(
    _ issue: RuntimeIssue
  ) -> String {
    var fields = [
      "\"severity\":\(jsonString(issue.severity.rawValue))",
      "\"code\":\(jsonString(issue.code))",
      "\"message\":\(jsonString(issue.message))",
      "\"description\":\(jsonString(issue.description))",
    ]
    if let identity = issue.identity {
      fields.append("\"identity\":\(jsonString(identity.path))")
    }
    if let source = issue.source {
      fields.append("\"source\":\(jsonString(source))")
    }
    return "\u{001E}runtimeIssue:{\(fields.joined(separator: ","))}\n"
  }

  package static func encode(
    _ surface: RasterSurface
  ) -> String {
    var knownImageIDs: Set<String> = []
    return encode(
      surface,
      damage: nil,
      knownImageIDs: &knownImageIDs
    )
  }

  package static func encode(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) -> String {
    var knownImageIDs: Set<String> = []
    return encode(
      surface,
      damage: damage,
      knownImageIDs: &knownImageIDs
    )
  }

  package static func encode(
    _ surface: RasterSurface,
    damage: PresentationDamage? = nil,
    knownImageIDs: inout Set<String>
  ) -> String {
    encode(
      surface,
      sequence: nil,
      semanticSnapshot: nil,
      focusedIdentity: nil,
      damage: damage,
      knownImageIDs: &knownImageIDs
    )
  }

  package static func encode(
    _ frame: SemanticHostFrame
  ) -> String {
    var knownImageIDs: Set<String> = []
    return encode(
      frame,
      knownImageIDs: &knownImageIDs
    )
  }

  package static func encode(
    _ frame: SemanticHostFrame,
    knownImageIDs: inout Set<String>
  ) -> String {
    encode(
      frame.raster,
      sequence: frame.sequence,
      semanticSnapshot: frame.semantics,
      focusedIdentity: frame.focusedIdentity,
      damage: frame.rasterDamage,
      knownImageIDs: &knownImageIDs
    )
  }

  private static func encode(
    _ surface: RasterSurface,
    sequence: UInt64?,
    semanticSnapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    damage: PresentationDamage?,
    knownImageIDs: inout Set<String>
  ) -> String {
    var styles: [ResolvedTextStyle?] = [nil]
    let rows = surface.cells.enumerated().map { y, row in
      encodeRow(
        row,
        y: y,
        styles: &styles
      )
    }
    let accessibilityTree = semanticSnapshot.map {
      encodeAccessibilityTree(
        $0.accessibilityNodes,
        focusedIdentity: focusedIdentity
      )
    }
    let accessibilityAnnouncements = semanticSnapshot.map {
      encodeAccessibilityAnnouncements($0.accessibilityAnnouncements)
    }
    let hasV2Fields =
      sequence != nil || accessibilityTree?.isEmpty == false
      || accessibilityAnnouncements?.isEmpty == false
    let version = hasV2Fields ? 2 : 1

    var json = "\u{001E}surface:{"
    json += "\"version\":\(version)"
    if let sequence {
      json += ",\"sequence\":\(sequence)"
    }
    json += ",\"width\":\(max(0, surface.size.width))"
    json += ",\"height\":\(max(0, surface.size.height))"
    json += ",\"styles\":["
    json += styles.map(encodeStyle).joined(separator: ",")
    json += "]"
    json += ",\"rows\":["
    json += rows.joined(separator: ",")
    json += "]"
    json += ",\"images\":["
    json += encodeImages(
      surface.imageAttachments,
      knownImageIDs: &knownImageIDs
    ).joined(separator: ",")
    json += "]"
    if let damage {
      json += ",\"damage\":"
      json += encodeDamage(damage)
    }
    if let accessibilityTree, !accessibilityTree.isEmpty {
      json += ",\"accessibilityTree\":["
      json += accessibilityTree.joined(separator: ",")
      json += "]"
    }
    if let accessibilityAnnouncements, !accessibilityAnnouncements.isEmpty {
      json += ",\"accessibilityAnnouncements\":["
      json += accessibilityAnnouncements.joined(separator: ",")
      json += "]"
    }
    json += "}\n"
    return json
  }

  private static func encodeDamage(
    _ damage: PresentationDamage
  ) -> String {
    let fields = [
      "\"textRows\":[\(damage.textRows.map(encodeDamageTextRow).joined(separator: ","))]",
      "\"requiresFullTextRepaint\":\(damage.requiresFullTextRepaint ? "true" : "false")",
      "\"requiresFullGraphicsReplay\":\(damage.requiresFullGraphicsReplay ? "true" : "false")",
    ]
    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func encodeDamageTextRow(
    _ row: PresentationDamage.TextRow
  ) -> String {
    let ranges = row.columnRanges.map { range in
      "[\(range.lowerBound),\(range.upperBound)]"
    }.joined(separator: ",")
    return "[\(row.row),[\(ranges)]]"
  }

  private static func encodeRow(
    _ row: [RasterCell],
    y _: Int,
    styles: inout [ResolvedTextStyle?]
  ) -> String {
    var encodedCells: [String] = []
    encodedCells.reserveCapacity(row.count)

    for (x, cell) in row.enumerated() {
      guard !cell.isContinuation else {
        continue
      }
      let styleIndex = index(of: cell.style, in: &styles)
      encodedCells.append(
        "[\(x),\(jsonString(String(cell.character))),\(max(1, cell.spanWidth)),\(styleIndex)]"
      )
    }

    return "[" + encodedCells.joined(separator: ",") + "]"
  }

  private static func encodeAccessibilityTree(
    _ nodes: [AccessibilityNode],
    focusedIdentity: Identity?
  ) -> [String] {
    nodes.map { node in
      var fields = [
        "\"id\":\(jsonString(node.identity.path))",
        "\"rect\":\(encodeRect(node.rect))",
        "\"role\":\(jsonString(node.role.description))",
        "\"isFocused\":\(node.identity == focusedIdentity ? "true" : "false")",
      ]
      if let parentIdentity = node.parentIdentity {
        fields.append("\"parentId\":\(jsonString(parentIdentity.path))")
      }
      if let label = node.label {
        fields.append("\"label\":\(jsonString(label))")
      }
      if let hint = node.hint {
        fields.append("\"hint\":\(jsonString(hint))")
      }
      if let liveRegion = node.liveRegion {
        fields.append("\"liveRegion\":\(jsonString(liveRegion.description))")
      }
      if let cursorAnchor = node.cursorAnchor {
        fields.append("\"cursorAnchor\":\(encodePoint(cursorAnchor))")
      }
      return "{" + fields.joined(separator: ",") + "}"
    }
  }

  private static func encodeAccessibilityAnnouncements(
    _ announcements: [AccessibilityAnnouncement]
  ) -> [String] {
    announcements.map { announcement in
      "{"
        + "\"message\":\(jsonString(announcement.message)),"
        + "\"politeness\":\(jsonString(announcement.politeness.description))"
        + "}"
    }
  }

  private static func encodeImages(
    _ attachments: [RasterImageAttachment],
    knownImageIDs: inout Set<String>
  ) -> [String] {
    attachments.compactMap { attachment in
      encodeImage(
        attachment,
        knownImageIDs: &knownImageIDs
      )
    }
  }

  private static func encodeImage(
    _ attachment: RasterImageAttachment,
    knownImageIDs: inout Set<String>
  ) -> String? {
    guard let bytes = imageBytes(for: attachment), !attachment.visibleBounds.isEmpty else {
      return nil
    }
    let format = imageFormat(for: bytes)

    let imageID = webImageID(for: bytes, format: format)
    let shouldTransmitData = knownImageIDs.insert(imageID).inserted
    var fields = [
      "\"id\":\(jsonString(imageID))",
      "\"format\":\(jsonString(format.jsonValue))",
      "\"bounds\":\(encodeRect(attachment.bounds))",
      "\"visibleBounds\":\(encodeRect(attachment.visibleBounds))",
      "\"scalingMode\":\(jsonString(attachment.scalingMode.rawValue))",
    ]
    if let pixelSize = attachment.pixelSize {
      fields.append("\"pixelSize\":\(encodeSize(pixelSize))")
    }
    if shouldTransmitData {
      fields.append("\"dataBase64\":\(jsonString(base64Encoded(bytes)))")
    }
    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func imageBytes(
    for attachment: RasterImageAttachment
  ) -> [UInt8]? {
    switch attachment.resolvedReference {
    case .embeddedImage(let bytes):
      return bytes
    case .filePath(let path):
      return webSurfaceReadFileBytes(at: path)
    case .namedResource, nil:
      break
    }

    if case .data(let bytes) = attachment.source {
      return bytes
    }
    return nil
  }

  /// Detects the container format from the leading magic bytes. Used
  /// to set the JSON `format` field and pick a MIME type on the JS
  /// side. Defaults to PNG so unknown blobs at least try the most
  /// common path.
  private static func imageFormat(
    for bytes: [UInt8]
  ) -> WebSurfaceImageFormat {
    if bytes.count >= 8,
      bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
      bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A
    {
      return .png
    }
    if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
      return .jpeg
    }
    if bytes.count >= 6,
      bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38,
      bytes[4] == 0x37 || bytes[4] == 0x39, bytes[5] == 0x61
    {
      return .gif
    }
    return .png
  }

  private static func encodeRect(
    _ rect: CellRect
  ) -> String {
    "[\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)]"
  }

  private static func encodeSize(
    _ size: PixelSize
  ) -> String {
    "[\(size.width),\(size.height)]"
  }

  private static func encodePoint(
    _ point: CellPoint
  ) -> String {
    "[\(point.x),\(point.y)]"
  }

  private static func webImageID(
    for bytes: [UInt8],
    format: WebSurfaceImageFormat
  ) -> String {
    "\(format.jsonValue):\(hexString(fnv1a64(bytes))):\(bytes.count)"
  }

  private static func fnv1a64(
    _ bytes: [UInt8]
  ) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
      hash ^= UInt64(byte)
      hash &*= 0x100_0000_01b3
    }
    return hash
  }

  private static func hexString(
    _ value: UInt64
  ) -> String {
    var text = String(value, radix: 16, uppercase: false)
    while text.count < 16 {
      text = "0" + text
    }
    return text
  }

  private static func base64Encoded(
    _ bytes: [UInt8]
  ) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    var result: [UInt8] = []
    result.reserveCapacity(((bytes.count + 2) / 3) * 4)

    var index = 0
    while index < bytes.count {
      let first = Int(bytes[index])
      let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
      let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
      let combined = (first << 16) | (second << 8) | third

      result.append(alphabet[(combined >> 18) & 0x3F])
      result.append(alphabet[(combined >> 12) & 0x3F])
      result.append(
        index + 1 < bytes.count ? alphabet[(combined >> 6) & 0x3F] : UInt8(ascii: "=")
      )
      result.append(index + 2 < bytes.count ? alphabet[combined & 0x3F] : UInt8(ascii: "="))
      index += 3
    }

    return String(decoding: result, as: UTF8.self)
  }

  private static func index(
    of style: ResolvedTextStyle?,
    in styles: inout [ResolvedTextStyle?]
  ) -> Int {
    if let existing = styles.firstIndex(where: { $0 == style }) {
      return existing
    }
    styles.append(style)
    return styles.count - 1
  }

  private static func encodeStyle(
    _ style: ResolvedTextStyle?
  ) -> String {
    guard let style else {
      return "null"
    }

    var fields: [String] = []
    if let foregroundColor = style.foregroundColor {
      fields.append("\"fg\":\(jsonString(foregroundColor.hexString(format: .rrggbbaa)))")
    }
    if let backgroundColor = style.backgroundColor {
      fields.append("\"bg\":\(jsonString(backgroundColor.hexString(format: .rrggbbaa)))")
    }
    if !style.emphasis.isEmpty {
      fields.append("\"em\":\(style.emphasis.rawValue)")
    }
    if let underlineStyle = style.underlineStyle {
      fields.append("\"underline\":\(encodeLineStyle(underlineStyle))")
    }
    if let strikethroughStyle = style.strikethroughStyle {
      fields.append("\"strikethrough\":\(encodeLineStyle(strikethroughStyle))")
    }
    if style.opacity < 1 {
      fields.append("\"opacity\":\(style.opacity)")
    }

    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func encodeLineStyle(
    _ style: TextLineStyle
  ) -> String {
    var fields = ["\"pattern\":\(jsonString(style.pattern.rawValue))"]
    if let color = style.color {
      fields.append("\"color\":\(jsonString(color.hexString(format: .rrggbbaa)))")
    }
    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func jsonString(
    _ text: String
  ) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x22:
        result += "\\\""
      case 0x5C:
        result += "\\\\"
      case 0x08:
        result += "\\b"
      case 0x0C:
        result += "\\f"
      case 0x0A:
        result += "\\n"
      case 0x0D:
        result += "\\r"
      case 0x09:
        result += "\\t"
      case 0x00...0x1F:
        var hex = String(scalar.value, radix: 16, uppercase: true)
        while hex.count < 4 {
          hex = "0" + hex
        }
        result += "\\u\(hex)"
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    result += "\""
    return result
  }
}

private func webSurfaceReadFileBytes(
  at path: String
) -> [UInt8]? {
  let fileDescriptor = webSurfaceOpenRead(path)
  guard fileDescriptor >= 0 else {
    return nil
  }
  defer {
    _ = webSurfaceClose(fileDescriptor)
  }

  var bytes: [UInt8] = []
  var buffer = [UInt8](repeating: 0, count: 8 * 1024)
  let bufferCount = buffer.count
  while true {
    let readCount = unsafe buffer.withUnsafeMutableBytes { rawBuffer in
      unsafe webSurfaceRead(
        fileDescriptor,
        rawBuffer.baseAddress,
        bufferCount
      )
    }
    if readCount < 0 {
      return nil
    }
    if readCount == 0 {
      return bytes
    }
    bytes.append(contentsOf: buffer.prefix(readCount))
  }
}

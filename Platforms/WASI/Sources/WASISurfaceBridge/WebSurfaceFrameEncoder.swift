@_spi(Runners) package import SwiftTUIRuntime

// `WebSurfaceImageFormat` and the image-attachment encoding cluster live in
// `WebSurfaceImageEncoder.swift`. `encodeRect` and `jsonString` are widened to
// `package` (still namespaced under `WebSurfaceFrameEncoder`) so that file can
// reach them.

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

  package static func encodeFrameDiagnostic(
    _ record: FrameDiagnosticRecord
  ) -> String {
    "\u{001E}frameDiagnostic:{"
      + "\"format\":\"swift-tui-frame-diagnostics-v1\","
      + "\"header\":[\(FrameDiagnosticsTSVFormatting.headerFields.map(jsonString).joined(separator: ","))],"
      + "\"fields\":[\(FrameDiagnosticsTSVFormatting.fields(for: record).map(jsonString).joined(separator: ","))]"
      + "}\n"
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
    _ surface: RasterSurface,
    state: inout WebSurfaceFrameEncodingState
  ) -> String {
    encode(
      surface,
      sequence: nil,
      semanticSnapshot: nil,
      focusedIdentity: nil,
      damage: nil,
      state: &state
    )
  }

  package static func encode(
    _ surface: RasterSurface,
    damage: PresentationDamage?,
    state: inout WebSurfaceFrameEncodingState
  ) -> String {
    encode(
      surface,
      sequence: nil,
      semanticSnapshot: nil,
      focusedIdentity: nil,
      damage: damage,
      state: &state
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

  package static func encode(
    _ frame: SemanticHostFrame,
    state: inout WebSurfaceFrameEncodingState
  ) -> String {
    encode(
      frame.raster,
      sequence: frame.sequence,
      semanticSnapshot: frame.semantics,
      focusedIdentity: frame.focusedIdentity,
      damage: frame.rasterDamage,
      state: &state
    )
  }

  package static func encode(
    _ surface: RasterSurface,
    sequence: UInt64?,
    semanticSnapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    damage: PresentationDamage?,
    state: inout WebSurfaceFrameEncodingState
  ) -> String {
    guard state.deltaEnabled else {
      return encode(
        surface,
        sequence: sequence,
        semanticSnapshot: semanticSnapshot,
        focusedIdentity: focusedIdentity,
        damage: damage,
        knownImageIDs: &state.knownImageIDs
      )
    }

    guard let damage,
      state.hasBaseline,
      let baselineSize = state.baselineSize,
      baselineSize == surface.size,
      !damage.requiresFullTextRepaint,
      !damage.requiresFullGraphicsReplay
    else {
      let output = encode(
        surface,
        sequence: sequence,
        semanticSnapshot: semanticSnapshot,
        focusedIdentity: focusedIdentity,
        damage: damage,
        knownImageIDs: &state.knownImageIDs
      )
      updateBaseline(for: surface, state: &state)
      return output
    }

    let output = encodeDelta(
      surface,
      sequence: sequence,
      semanticSnapshot: semanticSnapshot,
      focusedIdentity: focusedIdentity,
      damage: damage,
      state: &state
    )
    state.hasBaseline = true
    state.baselineSize = surface.size
    return output
  }

  private static func encode(
    _ surface: RasterSurface,
    sequence: UInt64?,
    semanticSnapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    damage: PresentationDamage?,
    knownImageIDs: inout Set<String>
  ) -> String {
    let encoded = encodedRowsAndStyles(for: surface)
    let styles = encoded.styles
    let rows = encoded.rows
    let accessibilityTree = semanticSnapshot.map {
      encodeAccessibilityTree(
        $0.accessibilityNodes,
        focusedIdentity: focusedIdentity
      )
    }
    let accessibilityAnnouncements = semanticSnapshot.map {
      encodeAccessibilityAnnouncements($0.accessibilityAnnouncements)
    }
    let scrollRegions = semanticSnapshot.map {
      encodeScrollRegions($0.scrollRoutes)
    }
    let hasV2Fields =
      sequence != nil || accessibilityTree?.isEmpty == false
      || accessibilityAnnouncements?.isEmpty == false
      || scrollRegions?.isEmpty == false
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
    if let scrollRegions, !scrollRegions.isEmpty {
      json += ",\"scrollRegions\":["
      json += scrollRegions.joined(separator: ",")
      json += "]"
    }
    json += "}\n"
    return json
  }

  private static func encodeDelta(
    _ surface: RasterSurface,
    sequence: UInt64?,
    semanticSnapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    damage: PresentationDamage,
    state: inout WebSurfaceFrameEncodingState
  ) -> String {
    let rowIndexes = uniqueSortedRowIndexes(
      from: damage,
      height: surface.size.height
    )
    let deltaRows = rowIndexes.map { rowIndex in
      "[\(rowIndex),\(encodeRow(surface.cells[rowIndex], y: rowIndex, styles: &state.persistentStyles))]"
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
    let scrollRegions = semanticSnapshot.map {
      encodeScrollRegions($0.scrollRoutes)
    }

    var json = "\u{001E}surface:{"
    json += "\"version\":3"
    json += ",\"encoding\":\"delta\""
    if let sequence {
      json += ",\"sequence\":\(sequence)"
    }
    json += ",\"width\":\(max(0, surface.size.width))"
    json += ",\"height\":\(max(0, surface.size.height))"
    json += ",\"styles\":["
    json += state.persistentStyles.map(encodeStyle).joined(separator: ",")
    json += "]"
    json += ",\"deltaRows\":["
    json += deltaRows.joined(separator: ",")
    json += "]"
    json += ",\"images\":["
    json += encodeImages(
      surface.imageAttachments,
      knownImageIDs: &state.knownImageIDs
    ).joined(separator: ",")
    json += "]"
    json += ",\"damage\":"
    json += encodeDamage(damage)
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
    if let scrollRegions, !scrollRegions.isEmpty {
      json += ",\"scrollRegions\":["
      json += scrollRegions.joined(separator: ",")
      json += "]"
    }
    json += "}\n"
    return json
  }

  private static func encodedRowsAndStyles(
    for surface: RasterSurface
  ) -> (rows: [String], styles: [ResolvedTextStyle?]) {
    var styles: [ResolvedTextStyle?] = [nil]
    let rows = surface.cells.enumerated().map { y, row in
      encodeRow(
        row,
        y: y,
        styles: &styles
      )
    }
    return (rows, styles)
  }

  private static func updateBaseline(
    for surface: RasterSurface,
    state: inout WebSurfaceFrameEncodingState
  ) {
    state.persistentStyles = encodedRowsAndStyles(for: surface).styles
    state.hasBaseline = true
    state.baselineSize = surface.size
  }

  private static func uniqueSortedRowIndexes(
    from damage: PresentationDamage,
    height: Int
  ) -> [Int] {
    Array(Set(damage.textRows.map(\.row)))
      .filter { $0 >= 0 && $0 < height }
      .sorted()
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

  /// Encodes per-region scroll extents for scroll-chaining: the viewport rect,
  /// the current clamped offset, and the total content size. The browser host
  /// recomputes the per-direction scroll headroom from these (mirroring the
  /// `min(max(0, offset), max(0, content - viewport))` clamp) to decide whether
  /// to capture the wheel or let it chain to the page. See
  /// `docs/proposals/EMBEDDED_WEB_SCROLL_CHAINING.md` in the coordination root.
  private static func encodeScrollRegions(
    _ routes: [ScrollRoute]
  ) -> [String] {
    routes.map { route in
      "{"
        + "\"id\":\(jsonString(route.identity.path)),"
        + "\"rect\":\(encodeRect(route.viewportRect)),"
        + "\"offset\":\(encodePoint(route.contentOffset)),"
        + "\"content\":[\(route.contentBounds.size.width),\(route.contentBounds.size.height)]"
        + "}"
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

  // Widened from `private` to `package` so `WebSurfaceImageEncoder.swift` can
  // encode image attachment rects.
  package static func encodeRect(
    _ rect: CellRect
  ) -> String {
    "[\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)]"
  }

  private static func encodePoint(
    _ point: CellPoint
  ) -> String {
    "[\(point.x),\(point.y)]"
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

  // Widened from `private` to `package` so `WebSurfaceImageEncoder.swift` can
  // JSON-escape image IDs and base64 payloads.
  package static func jsonString(
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

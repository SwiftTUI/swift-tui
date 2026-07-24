import SwiftTUICore

// `WebSurfaceImageFormat` and the image-attachment encoding cluster live in
// `WebSurfaceImageEncoder.swift`. `encodeRect` and `jsonString` are widened to
// `package` (still namespaced under `WebSurfaceFrameEncoder`) so that file can
// reach them.
//
// This encoder is a *format adapter* over the shared `HostWireFrameModel`
// (F18): every emitted value — traversal, style table, link runs, semantic
// projections — is read from the model, while the RS-framed hand-rolled JSON
// byte shape (key order, tuple arities, whitespace) stays owned here and
// frozen by the transport fixtures. It lives in the runtime (not the WASI
// bridge) because the wire is host-neutral: the WASI/WebHost transports and
// the converged Android host all emit it (convergence proposal
// 2026-07-22-002).

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
    fallbackBackground: Color = TerminalAppearance.fallback.backgroundColor,
    knownImageIDs: inout Set<String>
  ) -> String {
    encode(
      HostWireFrameModel(
        surface: surface,
        sequence: nil,
        semanticSnapshot: nil,
        focusedIdentity: nil,
        damage: damage,
        preferredLayoutSize: nil
      ),
      fallbackBackground: fallbackBackground,
      knownImageIDs: &knownImageIDs
    )
  }

  package static func encode(
    _ surface: RasterSurface,
    fallbackBackground: Color = TerminalAppearance.fallback.backgroundColor,
    state: inout HostWireEncodingState
  ) -> String {
    encode(
      surface,
      sequence: nil,
      semanticSnapshot: nil,
      focusedIdentity: nil,
      damage: nil,
      fallbackBackground: fallbackBackground,
      state: &state
    )
  }

  package static func encode(
    _ surface: RasterSurface,
    damage: PresentationDamage?,
    fallbackBackground: Color = TerminalAppearance.fallback.backgroundColor,
    state: inout HostWireEncodingState
  ) -> String {
    encode(
      surface,
      sequence: nil,
      semanticSnapshot: nil,
      focusedIdentity: nil,
      damage: damage,
      fallbackBackground: fallbackBackground,
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
    fallbackBackground: Color = TerminalAppearance.fallback.backgroundColor,
    knownImageIDs: inout Set<String>
  ) -> String {
    // Decompose the frame through the shared host-content projection so the
    // host-serialized field set lives in one place (see `HostFrameProjection`).
    encode(
      HostWireFrameModel(frame.hostProjection),
      fallbackBackground: fallbackBackground,
      knownImageIDs: &knownImageIDs
    )
  }

  package static func encode(
    _ frame: SemanticHostFrame,
    fallbackBackground: Color = TerminalAppearance.fallback.backgroundColor,
    state: inout HostWireEncodingState
  ) -> String {
    encode(
      HostWireFrameModel(frame.hostProjection),
      fallbackBackground: fallbackBackground,
      state: &state
    )
  }

  package static func encode(
    _ surface: RasterSurface,
    sequence: UInt64?,
    semanticSnapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    damage: PresentationDamage?,
    preferredLayoutSize: CellSize? = nil,
    fallbackBackground: Color = TerminalAppearance.fallback.backgroundColor,
    state: inout HostWireEncodingState
  ) -> String {
    encode(
      HostWireFrameModel(
        surface: surface,
        sequence: sequence,
        semanticSnapshot: semanticSnapshot,
        focusedIdentity: focusedIdentity,
        damage: damage,
        preferredLayoutSize: preferredLayoutSize
      ),
      fallbackBackground: fallbackBackground,
      state: &state
    )
  }

  package static func encode(
    _ model: HostWireFrameModel,
    fallbackBackground: Color,
    state: inout HostWireEncodingState
  ) -> String {
    guard state.deltaEnabled else {
      return encode(
        model,
        fallbackBackground: fallbackBackground,
        knownImageIDs: &state.knownImageIDs
      )
    }

    switch model.deltaDecision(for: state) {
    case .full:
      let full = encodeFull(
        model,
        fallbackBackground: fallbackBackground,
        knownImageIDs: &state.knownImageIDs
      )
      state.rebaseline(onFrameStyles: full.styles, gridSize: model.gridSize)
      return full.output
    case .delta(let damage):
      if let output = encodeDelta(
        model,
        damage: damage,
        fallbackBackground: fallbackBackground,
        state: &state
      ) {
        state.recordDeltaBaseline(gridSize: model.gridSize)
        return output
      }
      let full = encodeFull(
        model,
        fallbackBackground: fallbackBackground,
        knownImageIDs: &state.knownImageIDs
      )
      state.rebaseline(onFrameStyles: full.styles, gridSize: model.gridSize)
      return full.output
    }
  }

  package static func encode(
    _ model: HostWireFrameModel,
    fallbackBackground: Color,
    knownImageIDs: inout Set<String>
  ) -> String {
    encodeFull(
      model,
      fallbackBackground: fallbackBackground,
      knownImageIDs: &knownImageIDs
    ).output
  }

  private static func encodeFull(
    _ model: HostWireFrameModel,
    fallbackBackground: Color,
    knownImageIDs: inout Set<String>
  ) -> (output: String, styles: HostWireStyleTable) {
    var styles = HostWireStyleTable(gridSize: model.gridSize)
    var rows: [String] = []
    rows.reserveCapacity(model.surface.cells.count)
    for row in model.surface.cells {
      guard let encoded = encodeRow(row, interningInto: &styles) else {
        preconditionFailure("one full frame exceeded its grid-sized wire-style budget")
      }
      rows.append(encoded)
    }
    let accessibilityTree = encodeAccessibilityTree(model.accessibilityNodes)
    let accessibilityAnnouncements = encodeAccessibilityAnnouncements(
      model.accessibilityAnnouncements
    )
    let scrollRegions = encodeScrollRegions(model.scrollRegions)
    let hasV2Fields =
      model.sequence != nil || !accessibilityTree.isEmpty
      || !accessibilityAnnouncements.isEmpty
      || !scrollRegions.isEmpty
    let version = hasV2Fields ? 2 : 1

    var json = "\u{001E}surface:{"
    json += "\"version\":\(version)"
    if let sequence = model.sequence {
      json += ",\"sequence\":\(sequence)"
    }
    json += ",\"width\":\(max(0, model.gridSize.width))"
    json += ",\"height\":\(max(0, model.gridSize.height))"
    json += ",\"styles\":["
    json += styles.encodedElements.joined(separator: ",")
    json += "]"
    json += ",\"rows\":["
    json += rows.joined(separator: ",")
    json += "]"
    json += ",\"images\":["
    json += encodeImages(
      model.imageAttachments,
      fallbackBackground: fallbackBackground,
      knownImageIDs: &knownImageIDs
    ).joined(separator: ",")
    json += "]"
    if let damage = model.damage {
      json += ",\"damage\":"
      json += encodeDamage(damage)
    }
    if !accessibilityTree.isEmpty {
      json += ",\"accessibilityTree\":["
      json += accessibilityTree.joined(separator: ",")
      json += "]"
    }
    if !accessibilityAnnouncements.isEmpty {
      json += ",\"accessibilityAnnouncements\":["
      json += accessibilityAnnouncements.joined(separator: ",")
      json += "]"
    }
    if !scrollRegions.isEmpty {
      json += ",\"scrollRegions\":["
      json += scrollRegions.joined(separator: ",")
      json += "]"
    }
    json += encodeAdditiveFields(for: model)
    json += "}\n"
    return (json, styles)
  }

  private static func encodeDelta(
    _ model: HostWireFrameModel,
    damage: PresentationDamage,
    fallbackBackground: Color,
    state: inout HostWireEncodingState
  ) -> String? {
    var candidate = state
    var deltaRows: [String] = []
    deltaRows.reserveCapacity(model.deltaRowIndexes.count)
    for rowIndex in model.deltaRowIndexes {
      guard
        let encodedRow = encodeRow(
          model.surface.cells[rowIndex],
          interningInto: &candidate.persistentStyles
        )
      else {
        return nil
      }
      deltaRows.append("[\(rowIndex),\(encodedRow)]")
    }
    let accessibilityTree = encodeAccessibilityTree(model.accessibilityNodes)
    let accessibilityAnnouncements = encodeAccessibilityAnnouncements(
      model.accessibilityAnnouncements
    )
    let scrollRegions = encodeScrollRegions(model.scrollRegions)

    var json = "\u{001E}surface:{"
    json += "\"version\":3"
    json += ",\"encoding\":\"delta\""
    if let sequence = model.sequence {
      json += ",\"sequence\":\(sequence)"
    }
    json += ",\"width\":\(max(0, model.gridSize.width))"
    json += ",\"height\":\(max(0, model.gridSize.height))"
    json += ",\"styles\":["
    json += candidate.persistentStyles.encodedElements.joined(separator: ",")
    json += "]"
    json += ",\"deltaRows\":["
    json += deltaRows.joined(separator: ",")
    json += "]"
    json += ",\"images\":["
    json += encodeImages(
      model.imageAttachments,
      fallbackBackground: fallbackBackground,
      knownImageIDs: &candidate.knownImageIDs
    ).joined(separator: ",")
    json += "]"
    json += ",\"damage\":"
    json += encodeDamage(damage)
    if !accessibilityTree.isEmpty {
      json += ",\"accessibilityTree\":["
      json += accessibilityTree.joined(separator: ",")
      json += "]"
    }
    if !accessibilityAnnouncements.isEmpty {
      json += ",\"accessibilityAnnouncements\":["
      json += accessibilityAnnouncements.joined(separator: ",")
      json += "]"
    }
    if !scrollRegions.isEmpty {
      json += ",\"scrollRegions\":["
      json += scrollRegions.joined(separator: ",")
      json += "]"
    }
    json += encodeAdditiveFields(for: model)
    json += "}\n"
    state = candidate
    return json
  }

  /// The F19 additive fields, shared by the full and delta record shapes. All
  /// of them are optional object keys so deployed decoders ignore rather than
  /// reject them, and none of them move the `version` literal — see the
  /// `HostWireSchema` wire-evolution policy.
  private static func encodeAdditiveFields(
    for model: HostWireFrameModel
  ) -> String {
    var json = ""
    if let links = encodeLinks(for: model) {
      json += ",\"links\":[\(links.rows)]"
      json += ",\"linkTargets\":[\(links.targets)]"
    }
    if let presentation = model.focusPresentation,
      presentation.focusedIdentity != nil
    {
      json += ",\"focusPresentation\":\(encodeFocusPresentation(presentation))"
    }
    if let preferredLayoutSize = model.preferredLayoutSize {
      json += ",\"preferredGridWidth\":\(preferredLayoutSize.width)"
      json += ",\"preferredGridHeight\":\(preferredLayoutSize.height)"
    }
    if let terminalStyle = model.terminalStyle {
      json += ",\"terminalStyle\":\(encodeTerminalStyle(terminalStyle))"
    }
    return json
  }

  /// The resolved terminal appearance, emitted only on streams whose host
  /// consumes a runtime-owned style (the converged Android path); browser
  /// hosts own their appearance and never receive the key, so browser-path
  /// bytes are unchanged. Additive-optional per the wire-evolution policy.
  private static func encodeTerminalStyle(
    _ style: TerminalRenderStyle
  ) -> String {
    let appearance = style.appearance
    return "{"
      + "\"foregroundColor\":{\"hex\":\(jsonString(appearance.foregroundColor.hexString(format: .rrggbbaa)))},"
      + "\"backgroundColor\":{\"hex\":\(jsonString(appearance.backgroundColor.hexString(format: .rrggbbaa)))},"
      + "\"tintColor\":{\"hex\":\(jsonString(appearance.tintColor.hexString(format: .rrggbbaa)))}"
      + "}"
  }

  /// Per-row hyperlink runs plus a deduplicated URL table. The run and
  /// target derivation lives in `HostWireFrameModel`; this formats the
  /// frozen `[y,[[start,span,target]…]]` tuple shape.
  private static func encodeLinks(
    for model: HostWireFrameModel
  ) -> (rows: String, targets: String)? {
    let table = model.linkTable()
    guard !table.rows.isEmpty else {
      return nil
    }
    let rows = table.rows.map { row in
      let runs = row.runs.map { run in
        "[\(run.start),\(run.span),\(run.target)]"
      }.joined(separator: ",")
      return "[\(row.y),[\(runs)]]"
    }
    return (
      rows.joined(separator: ","),
      table.targets.map(jsonString).joined(separator: ",")
    )
  }

  private static func encodeFocusPresentation(
    _ presentation: FocusPresentation
  ) -> String {
    var fields: [String] = []
    if let focusedIdentity = presentation.focusedIdentity {
      fields.append("\"focusedIdentity\":\(jsonString(focusedIdentity.path))")
    }
    fields.append(
      "\"semantics\":\(jsonString(HostWireSchema.focusSemanticsToken(presentation.semantics)))")
    fields.append("\"prefersTextInput\":\(presentation.prefersTextInput ? "true" : "false")")
    fields.append("\"hasFocusedRegion\":\(presentation.hasFocusedRegion ? "true" : "false")")
    return "{" + fields.joined(separator: ",") + "}"
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

  /// One wire row: continuation cells are skipped (their lead cell's span
  /// covers them) and each emitted cell's style is interned through the
  /// shared `HostWireStyleTable` — the full path interns into the frame
  /// table, the delta path into the persistent cross-frame epoch.
  private static func encodeRow(
    _ row: [RasterCell],
    interningInto styles: inout HostWireStyleTable
  ) -> String? {
    var encodedCells: [String] = []
    encodedCells.reserveCapacity(row.count)

    for (x, cell) in row.enumerated() {
      guard !cell.isContinuation else {
        continue
      }
      guard let styleIndex = styles.index(for: cell.style) else {
        return nil
      }
      encodedCells.append(
        "[\(x),\(jsonString(String(cell.character))),\(max(1, cell.spanWidth)),\(styleIndex)]"
      )
    }

    return "[" + encodedCells.joined(separator: ",") + "]"
  }

  private static func encodeAccessibilityTree(
    _ nodes: [HostWireFrameModel.WireAccessibilityNode]
  ) -> [String] {
    nodes.map { node in
      var fields = [
        "\"id\":\(jsonString(node.idPath))",
        "\"rect\":\(encodeRect(node.rect))",
        "\"role\":\(jsonString(node.roleToken))",
        "\"isFocused\":\(node.isFocused ? "true" : "false")",
      ]
      if let parentIDPath = node.parentIDPath {
        fields.append("\"parentId\":\(jsonString(parentIDPath))")
      }
      if let label = node.label {
        fields.append("\"label\":\(jsonString(label))")
      }
      if let hint = node.hint {
        fields.append("\"hint\":\(jsonString(hint))")
      }
      if node.hidden {
        fields.append("\"hidden\":true")
      }
      if let liveRegionToken = node.liveRegionToken {
        fields.append("\"liveRegion\":\(jsonString(liveRegionToken))")
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
    _ regions: [HostWireFrameModel.WireScrollRegion]
  ) -> [String] {
    regions.map { region in
      "{"
        + "\"id\":\(jsonString(region.idPath)),"
        + "\"rect\":\(encodeRect(region.viewportRect)),"
        + "\"offset\":\(encodePoint(region.contentOffset)),"
        + "\"content\":[\(region.contentSize.width),\(region.contentSize.height)]"
        + "}"
    }
  }

  private static func encodeAccessibilityAnnouncements(
    _ announcements: [HostWireFrameModel.WireAnnouncement]
  ) -> [String] {
    announcements.map { announcement in
      "{"
        + "\"message\":\(jsonString(announcement.message)),"
        + "\"politeness\":\(jsonString(announcement.politenessToken))"
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

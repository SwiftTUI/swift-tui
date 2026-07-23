import SwiftTUICore

/// The shared cross-host wire model: every semantic value the host encoders
/// emit, derived **once** per presented frame from the
/// ``HostFrameProjection`` seam.
///
/// `WebSurfaceFrameEncoder` — the converged wire every host emits since the
/// legacy Android keyed-JSON format retired — is a *format adapter* over
/// this model: it owns the RS-framed byte shape while reading every emitted
/// value from here — row/cell traversal and span math, style-table
/// interning, hyperlink run derivation, accessibility/scroll/focus
/// projections, and the image pre-blend gate. The transport fixtures
/// byte-freeze the format; this model changes where values come from,
/// never what bytes leave the process.
package struct HostWireFrameModel {
  // MARK: - Frame-level values

  package let sequence: UInt64?
  package let gridSize: CellSize
  package let preferredLayoutSize: CellSize?
  package let focusedIdentity: Identity?
  package let damage: PresentationDamage?
  /// The derived focus presentation (`nil` when the frame carried no
  /// semantic snapshot). Emission gates stay adapter-owned: web emits only
  /// when a focused identity exists; Android always emits.
  package let focusPresentation: FocusPresentation?
  /// The resolved terminal appearance for hosts that consume a
  /// runtime-owned style (the converged Android stream). Host config, not
  /// frame content — `nil` everywhere the host owns its appearance, and the
  /// encoder omits the additive key entirely.
  package let terminalStyle: TerminalRenderStyle?

  // MARK: - Cell surface

  /// The raster the cell-surface derivations traverse. The raw cell walk
  /// stays adapter-side (measured: materializing an intermediate cell
  /// representation regressed encode cost beyond noise); the *derivations*
  /// a walk feeds — style-table interning, hyperlink runs, plain-text rows —
  /// live here so they cannot drift between hosts.
  package let surface: RasterSurface

    // MARK: - Hyperlink runs

  package struct LinkRun {
    package let start: Int
    package let span: Int
    package let target: Int
  }

  package struct LinkRow {
    package let y: Int
    package let runs: [LinkRun]
  }


  // MARK: - Semantic projections

  package struct WireAccessibilityNode {
    package let idPath: String
    package let parentIDPath: String?
    package let rect: CellRect
    package let roleToken: String
    package let label: String?
    package let hint: String?
    package let hidden: Bool
    package let liveRegionToken: String?
    package let cursorAnchor: CellPoint?
    package let isFocused: Bool

    package init(
      _ node: AccessibilityNode,
      focusedIdentity: Identity?
    ) {
      idPath = node.identity.path
      parentIDPath = node.parentIdentity?.path
      rect = node.rect
      roleToken = node.role.description
      label = node.label
      hint = node.hint
      hidden = node.hidden
      liveRegionToken = node.liveRegion?.description
      cursorAnchor = node.cursorAnchor
      isFocused = node.identity == focusedIdentity
    }
  }

  package struct WireAnnouncement {
    package let message: String
    package let politenessToken: String

    package init(
      _ announcement: AccessibilityAnnouncement
    ) {
      message = announcement.message
      politenessToken = announcement.politeness.description
    }
  }

  package struct WireScrollRegion {
    package let idPath: String
    package let viewportRect: CellRect
    package let contentOffset: CellPoint
    package let contentSize: CellSize

    package init(
      _ route: ScrollRoute
    ) {
      idPath = route.identity.path
      viewportRect = route.viewportRect
      contentOffset = route.contentOffset
      contentSize = route.contentBounds.size
    }
  }

  package let accessibilityNodes: [WireAccessibilityNode]
  package let accessibilityAnnouncements: [WireAnnouncement]
  package let scrollRegions: [WireScrollRegion]

  // MARK: - Images

  /// Attachments pass through untransformed; payload resolution is
  /// per-adapter (web reads file sources, Android forwards identifiers) but
  /// the pre-blend gate is shared — see ``blendedImagePayload(for:compositor:fallbackBackground:)``.
  package let imageAttachments: [RasterImageAttachment]

  // MARK: - Construction

  package init(
    _ projection: HostFrameProjection,
    terminalStyle: TerminalRenderStyle? = nil
  ) {
    self.init(
      surface: projection.raster,
      sequence: projection.sequence,
      semanticSnapshot: projection.semantics,
      focusedIdentity: projection.focusedIdentity,
      damage: projection.rasterDamage,
      preferredLayoutSize: projection.preferredLayoutSize,
      terminalStyle: terminalStyle
    )
  }

  package init(
    surface: RasterSurface,
    sequence: UInt64?,
    semanticSnapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    damage: PresentationDamage?,
    preferredLayoutSize: CellSize?,
    terminalStyle: TerminalRenderStyle? = nil
  ) {
    self.sequence = sequence
    self.surface = surface
    gridSize = surface.size
    self.preferredLayoutSize = preferredLayoutSize
    self.focusedIdentity = focusedIdentity
    self.damage = damage
    focusPresentation = semanticSnapshot?.focusPresentation(for: focusedIdentity)
    self.terminalStyle = terminalStyle
    accessibilityNodes = (semanticSnapshot?.accessibilityNodes ?? []).map { node in
      WireAccessibilityNode(node, focusedIdentity: focusedIdentity)
    }
    accessibilityAnnouncements = (semanticSnapshot?.accessibilityAnnouncements ?? [])
      .map(WireAnnouncement.init)
    scrollRegions = (semanticSnapshot?.scrollRoutes ?? []).map(WireScrollRegion.init)
    imageAttachments = surface.imageAttachments
  }

  // MARK: - Cell-surface derivations

  /// Each row's characters joined, continuations included — the Android
  /// wire's parallel plain-text `rows` array.
  package func plainTextRows() -> [String] {
    surface.cells.map { row in
      String(row.map(\.character))
    }
  }

    /// Derives the hyperlink run table: deduplicated targets plus per-row runs
  /// of consecutive same-target cells (rows with no links are omitted).
  /// Continuation cells neither extend nor close a run — their lead cell's
  /// span already covers them.
  package func linkTable() -> (rows: [LinkRow], targets: [String]) {
    var linkTargets: [String] = []
    var linkRows: [LinkRow] = []
    for (y, row) in surface.cells.enumerated() {
      var runs: [LinkRun] = []
      var runStart = 0
      var runSpan = 0
      var runTarget = -1
      func closeRun() {
        guard runSpan > 0 else {
          return
        }
        runs.append(LinkRun(start: runStart, span: runSpan, target: runTarget))
        runSpan = 0
      }
      for (x, cell) in row.enumerated() {
        guard !cell.isContinuation else {
          continue
        }
        guard let hyperlink = cell.hyperlink else {
          closeRun()
          continue
        }
        let target: Int
        if let existing = linkTargets.firstIndex(of: hyperlink) {
          target = existing
        } else {
          linkTargets.append(hyperlink)
          target = linkTargets.count - 1
        }
        let span = max(1, cell.spanWidth)
        if runSpan > 0, runTarget == target, runStart + runSpan == x {
          runSpan += span
        } else {
          closeRun()
          runStart = x
          runSpan = span
          runTarget = target
        }
      }
      closeRun()
      if !runs.isEmpty {
        linkRows.append(LinkRow(y: y, runs: runs))
      }
    }
    return (linkRows, linkTargets)
  }

  // MARK: - Shared derivation helpers

  /// Interns `style` into a first-appearance style table (slot 0 = nil).
  /// Shared by the frame table above and the web delta path's persistent
  /// cross-frame table.
  package static func styleIndex(
    of style: ResolvedTextStyle?,
    in styles: inout [ResolvedTextStyle?]
  ) -> Int {
    if let existing = styles.firstIndex(where: { $0 == style }) {
      return existing
    }
    styles.append(style)
    return styles.count - 1
  }

  /// The damaged row indexes a delta record re-transmits: unique, sorted,
  /// bounded to the grid.
  package var deltaRowIndexes: [Int] {
    guard let damage else {
      return []
    }
    return Array(Set(damage.textRows.map(\.row)))
      .filter { $0 >= 0 && $0 < gridSize.height }
      .sorted()
  }

  /// The single image pre-blend gate both hosts share: a compositing-tagged
  /// attachment resolves to its deterministic pre-blended PNG payload (or
  /// `nil` for the raw-source path). Each adapter keeps its own compositor
  /// instance so per-host cache behavior is unchanged.
  package static func blendedImagePayload(
    for attachment: RasterImageAttachment,
    compositor: ImageBlendCompositor,
    fallbackBackground: Color
  ) -> BlendedImageEncodedPayload? {
    compositor.encodedPNGPayload(
      for: attachment,
      fallbackBackground: fallbackBackground
    )
  }
}

/// Cross-frame encoding state for a delta-capable host wire: the persistent
/// style table, the transmitted-image dedup set, and the delta baseline.
/// Host-neutral so a second wire (Android delta is the planned consumer) can
/// instantiate the same machinery instead of re-implementing it;
/// `WebSurfaceFrameEncodingState` is the web instantiation.
package struct HostWireEncodingState: Sendable {
  package var deltaEnabled: Bool
  package var knownImageIDs: Set<String>
  package var persistentStyles: [ResolvedTextStyle?]
  package var hasBaseline: Bool
  package var baselineSize: CellSize?

  package init(
    deltaEnabled: Bool,
    knownImageIDs: Set<String> = [],
    persistentStyles: [ResolvedTextStyle?] = [nil],
    hasBaseline: Bool = false,
    baselineSize: CellSize? = nil
  ) {
    self.deltaEnabled = deltaEnabled
    self.knownImageIDs = knownImageIDs
    self.persistentStyles = persistentStyles.isEmpty ? [nil] : persistentStyles
    self.hasBaseline = hasBaseline
    self.baselineSize = baselineSize
  }
}

extension HostWireFrameModel {
  /// Whether this frame may ship as a delta against `state`'s baseline.
  /// Callers gate on `state.deltaEnabled` first; this decides the
  /// frame-shape half: a usable baseline of the same grid size and damage
  /// that does not demand a full repaint.
  package enum DeltaDecision {
    case full
    case delta(PresentationDamage)
  }

  package func deltaDecision(
    for state: HostWireEncodingState
  ) -> DeltaDecision {
    guard let damage,
      state.hasBaseline,
      let baselineSize = state.baselineSize,
      baselineSize == gridSize,
      !damage.requiresFullTextRepaint,
      !damage.requiresFullGraphicsReplay
    else {
      return .full
    }
    return .delta(damage)
  }

}

extension HostWireEncodingState {
  /// Re-anchors the delta baseline after a full-frame emission: the
  /// persistent style table restarts from the emitted frame's table.
  package mutating func rebaseline(
    onFrameStyles styles: [ResolvedTextStyle?],
    gridSize: CellSize
  ) {
    persistentStyles = styles
    hasBaseline = true
    baselineSize = gridSize
  }

  /// Records that a delta frame was emitted, keeping the persistent style
  /// table accumulated by the delta rows.
  package mutating func recordDeltaBaseline(
    gridSize: CellSize
  ) {
    hasBaseline = true
    baselineSize = gridSize
  }
}

import Foundation
// `ImageBlendCompositor` is host-integration infrastructure exposed via the
// `Runners` SPI (shared with the SwiftUI/WASI hosts).
@_spi(Runners) public import SwiftTUIRuntime

public struct AndroidHostColorSnapshot: Codable, Equatable, Sendable {
  public var hex: String

  public init(
    _ color: Color
  ) {
    hex = color.hexString(format: .rrggbbaa)
  }
}

public struct AndroidHostTerminalStyleSnapshot: Codable, Equatable, Sendable {
  public var foregroundColor: AndroidHostColorSnapshot
  public var backgroundColor: AndroidHostColorSnapshot
  public var tintColor: AndroidHostColorSnapshot

  public init(
    renderStyle: TerminalRenderStyle
  ) {
    foregroundColor = AndroidHostColorSnapshot(renderStyle.appearance.foregroundColor)
    backgroundColor = AndroidHostColorSnapshot(renderStyle.appearance.backgroundColor)
    tintColor = AndroidHostColorSnapshot(renderStyle.appearance.tintColor)
  }
}

public struct AndroidHostTextLineStyleSnapshot: Codable, Equatable, Sendable {
  public var pattern: String
  public var color: AndroidHostColorSnapshot?

  public init(
    _ style: TextLineStyle
  ) {
    pattern = style.pattern.rawValue
    color = style.color.map(AndroidHostColorSnapshot.init)
  }
}

/// A single text-emphasis name in the Android frame snapshot.
///
/// Encodes as a bare JSON string (for example `"bold"`), so the wire format
/// matches the Kotlin frame parser's expectations.
public struct AndroidHostEmphasisToken: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public var rawValue: String

  public init(
    rawValue: String
  ) {
    self.rawValue = rawValue
  }

  public init(
    stringLiteral value: String
  ) {
    self.init(rawValue: value)
  }

  public init(
    from decoder: any Decoder
  ) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }

  public func encode(
    to encoder: any Encoder
  ) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct AndroidHostTextStyleSnapshot: Codable, Equatable, Sendable {
  public var foregroundColor: AndroidHostColorSnapshot?
  public var backgroundColor: AndroidHostColorSnapshot?
  public var emphasis: [AndroidHostEmphasisToken]
  public var underlineStyle: AndroidHostTextLineStyleSnapshot?
  public var strikethroughStyle: AndroidHostTextLineStyleSnapshot?
  public var opacity: Double

  public init(
    _ style: ResolvedTextStyle
  ) {
    foregroundColor = style.foregroundColor.map(AndroidHostColorSnapshot.init)
    backgroundColor = style.backgroundColor.map(AndroidHostColorSnapshot.init)
    emphasis = style.emphasis.debugNames.map(AndroidHostEmphasisToken.init(rawValue:))
    underlineStyle = style.underlineStyle.map(AndroidHostTextLineStyleSnapshot.init)
    strikethroughStyle = style.strikethroughStyle.map(AndroidHostTextLineStyleSnapshot.init)
    opacity = style.opacity
  }
}

public struct AndroidHostCellSnapshot: Codable, Equatable, Sendable {
  public var x: Int
  public var y: Int
  public var character: String
  public var spanWidth: Int
  public var continuationLeadX: Int?
  public var style: AndroidHostTextStyleSnapshot?
  public var hyperlink: String?

  public init(
    x: Int,
    y: Int,
    cell: RasterCell
  ) {
    self.x = x
    self.y = y
    character = String(cell.character)
    spanWidth = cell.spanWidth
    continuationLeadX = cell.continuationLeadX
    style = cell.style.map(AndroidHostTextStyleSnapshot.init)
    hyperlink = cell.hyperlink
  }

}

public struct AndroidHostCellRectSnapshot: Codable, Equatable, Sendable {
  public var x: Int
  public var y: Int
  public var width: Int
  public var height: Int

  public init(
    _ rect: CellRect
  ) {
    x = rect.origin.x
    y = rect.origin.y
    width = rect.size.width
    height = rect.size.height
  }
}

public struct AndroidHostCellPointSnapshot: Codable, Equatable, Sendable {
  public var x: Int
  public var y: Int

  public init(
    _ point: CellPoint
  ) {
    x = point.x
    y = point.y
  }
}

public struct AndroidHostPixelSizeSnapshot: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int

  public init(
    _ size: PixelSize
  ) {
    width = size.width
    height = size.height
  }
}

public struct AndroidHostCellSizeSnapshot: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int

  public init(
    _ size: CellSize
  ) {
    width = size.width
    height = size.height
  }
}

/// A scrollable region's extent for the Android host: the viewport rect, the
/// current clamped scroll offset, and the total content size, all in cells.
///
/// Mirrors the web host's `scrollRegions` wire shape so both surfaces forward
/// the same scroll-existence metadata. The host can derive per-direction
/// headroom (`min(max(0, offset), max(0, content - viewport))`) to route a pan
/// to the inner region or chain it to an outer native scroll view.
public struct AndroidHostScrollRegionSnapshot: Codable, Equatable, Sendable {
  public var id: String
  public var rect: AndroidHostCellRectSnapshot
  public var offset: AndroidHostCellPointSnapshot
  public var content: AndroidHostCellSizeSnapshot

  public init(
    _ route: ScrollRoute
  ) {
    self.init(HostWireFrameModel.WireScrollRegion(route))
  }

  init(
    _ region: HostWireFrameModel.WireScrollRegion
  ) {
    id = region.idPath
    rect = AndroidHostCellRectSnapshot(region.viewportRect)
    offset = AndroidHostCellPointSnapshot(region.contentOffset)
    content = AndroidHostCellSizeSnapshot(region.contentSize)
  }
}

public struct AndroidHostImageAttachmentSnapshot: Codable, Equatable, Sendable {
  public var id: String
  public var bounds: AndroidHostCellRectSnapshot
  public var visibleBounds: AndroidHostCellRectSnapshot
  public var sourceKind: String
  public var sourceIdentifier: String?
  public var payloadBase64: String?
  public var payloadByteCount: Int?
  public var pixelSize: AndroidHostPixelSizeSnapshot?
  public var cellPixelSize: AndroidHostPixelSizeSnapshot?
  public var isResizable: Bool
  public var scalingMode: String

  fileprivate init(
    attachment: RasterImageAttachment,
    payload: AndroidHostImagePayload?
  ) {
    id = payload?.id ?? attachment.identity.path
    bounds = AndroidHostCellRectSnapshot(attachment.bounds)
    visibleBounds = AndroidHostCellRectSnapshot(attachment.visibleBounds)
    sourceKind = payload?.sourceKind ?? Self.sourceKind(for: attachment.source)
    sourceIdentifier = payload?.sourceIdentifier ?? Self.sourceIdentifier(for: attachment.source)
    payloadBase64 = payload?.bytes.map { Data($0).base64EncodedString() }
    payloadByteCount = payload?.bytes?.count
    pixelSize = (payload?.pixelSize ?? attachment.pixelSize).map(AndroidHostPixelSizeSnapshot.init)
    cellPixelSize = attachment.cellPixelSize.map(AndroidHostPixelSizeSnapshot.init)
    isResizable = attachment.isResizable
    scalingMode = attachment.scalingMode.rawValue
  }

  private static func sourceKind(
    for source: ImageSource
  ) -> String {
    switch source {
    case .data:
      "data"
    case .path:
      "path"
    case .fileURL:
      "fileURL"
    }
  }

  private static func sourceIdentifier(
    for source: ImageSource
  ) -> String? {
    switch source {
    case .data:
      nil
    case .path(let path), .fileURL(let path):
      path
    }
  }
}

public struct AndroidHostRangeSnapshot: Codable, Equatable, Sendable {
  public var lowerBound: Int
  public var upperBound: Int

  public init(
    _ range: Range<Int>
  ) {
    lowerBound = range.lowerBound
    upperBound = range.upperBound
  }
}

public struct AndroidHostTextDamageRowSnapshot: Codable, Equatable, Sendable {
  public var row: Int
  public var columnRanges: [AndroidHostRangeSnapshot]

  public init(
    _ row: PresentationDamage.TextRow
  ) {
    self.row = row.row
    columnRanges = row.columnRanges.map(AndroidHostRangeSnapshot.init)
  }
}

public struct AndroidHostAccessibilityNodeSnapshot: Codable, Equatable, Sendable {
  public var id: String
  public var parentID: String?
  public var rect: AndroidHostCellRectSnapshot
  public var role: String
  public var label: String?
  public var hint: String?
  public var hidden: Bool
  public var liveRegion: String?
  public var cursorAnchor: AndroidHostCellPointSnapshot?
  public var isFocused: Bool

  public init(
    _ node: AccessibilityNode,
    focusedIdentity: Identity?
  ) {
    self.init(HostWireFrameModel.WireAccessibilityNode(node, focusedIdentity: focusedIdentity))
  }

  init(
    _ node: HostWireFrameModel.WireAccessibilityNode
  ) {
    id = node.idPath
    parentID = node.parentIDPath
    rect = AndroidHostCellRectSnapshot(node.rect)
    role = node.roleToken
    label = node.label
    hint = node.hint
    hidden = node.hidden
    liveRegion = node.liveRegionToken
    cursorAnchor = node.cursorAnchor.map(AndroidHostCellPointSnapshot.init)
    isFocused = node.isFocused
  }
}

public struct AndroidHostAccessibilityAnnouncementSnapshot: Codable, Equatable, Sendable {
  public var message: String
  public var politeness: String

  public init(
    _ announcement: AccessibilityAnnouncement
  ) {
    self.init(HostWireFrameModel.WireAnnouncement(announcement))
  }

  init(
    _ announcement: HostWireFrameModel.WireAnnouncement
  ) {
    message = announcement.message
    politeness = announcement.politenessToken
  }
}

public struct AndroidHostFocusPresentationSnapshot: Codable, Equatable, Sendable {
  public var focusedIdentity: String?
  public var semantics: String
  public var prefersTextInput: Bool
  public var hasFocusedRegion: Bool

  public init(
    _ presentation: FocusPresentation
  ) {
    focusedIdentity = presentation.focusedIdentity?.path
    // The shared wire token map — the web wire consumes the same function,
    // so the two hosts' focus-semantics tokens cannot drift.
    semantics = HostWireSchema.focusSemanticsToken(presentation.semantics)
    prefersTextInput = presentation.prefersTextInput
    hasFocusedRegion = presentation.hasFocusedRegion
  }
}

public struct AndroidHostFrameSnapshot: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var sequence: UInt64
  public var gridWidth: Int
  public var gridHeight: Int
  public var preferredGridWidth: Int?
  public var preferredGridHeight: Int?
  public var terminalStyle: AndroidHostTerminalStyleSnapshot
  public var rows: [String]
  public var cells: [AndroidHostCellSnapshot]
  public var imageAttachments: [AndroidHostImageAttachmentSnapshot]
  public var focusedIdentity: String?
  public var focusPresentation: AndroidHostFocusPresentationSnapshot
  public var accessibilityNodes: [AndroidHostAccessibilityNodeSnapshot]
  public var accessibilityAnnouncements: [AndroidHostAccessibilityAnnouncementSnapshot]
  /// Scroll-existence metadata for each scrollable region on screen. Omitted
  /// (nil) when the frame has no scrollable regions, so frames without scroll
  /// content keep their existing wire shape.
  public var scrollRegions: [AndroidHostScrollRegionSnapshot]?
  public var dirtyRows: [Int]
  public var textDamageRows: [AndroidHostTextDamageRowSnapshot]
  public var requiresFullTextRepaint: Bool
  public var requiresFullGraphicsReplay: Bool

  public init(
    schemaVersion: Int = 2,
    sequence: UInt64,
    gridWidth: Int,
    gridHeight: Int,
    preferredGridWidth: Int?,
    preferredGridHeight: Int?,
    terminalStyle: AndroidHostTerminalStyleSnapshot,
    rows: [String],
    cells: [AndroidHostCellSnapshot],
    imageAttachments: [AndroidHostImageAttachmentSnapshot],
    focusedIdentity: String?,
    focusPresentation: AndroidHostFocusPresentationSnapshot,
    accessibilityNodes: [AndroidHostAccessibilityNodeSnapshot],
    accessibilityAnnouncements: [AndroidHostAccessibilityAnnouncementSnapshot],
    scrollRegions: [AndroidHostScrollRegionSnapshot]? = nil,
    dirtyRows: [Int],
    textDamageRows: [AndroidHostTextDamageRowSnapshot],
    requiresFullTextRepaint: Bool,
    requiresFullGraphicsReplay: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.sequence = sequence
    self.gridWidth = gridWidth
    self.gridHeight = gridHeight
    self.preferredGridWidth = preferredGridWidth
    self.preferredGridHeight = preferredGridHeight
    self.terminalStyle = terminalStyle
    self.rows = rows
    self.cells = cells
    self.imageAttachments = imageAttachments
    self.focusedIdentity = focusedIdentity
    self.focusPresentation = focusPresentation
    self.accessibilityNodes = accessibilityNodes
    self.accessibilityAnnouncements = accessibilityAnnouncements
    self.scrollRegions = scrollRegions
    self.dirtyRows = dirtyRows
    self.textDamageRows = textDamageRows
    self.requiresFullTextRepaint = requiresFullTextRepaint
    self.requiresFullGraphicsReplay = requiresFullGraphicsReplay
  }
}

public enum AndroidHostFrameEncoder {
  private static let imageBlendCompositor = ImageBlendCompositor()

  public static func snapshot(
    for frame: SemanticHostFrame,
    style: AndroidHostStyle = .default
  ) -> AndroidHostFrameSnapshot {
    // Every frame/semantic value is read through the shared wire model
    // (built from the host-content projection); `style` stays separate
    // (terminal appearance is host config, not frame content). Sourcing from
    // the model — rather than reaching into `frame`/`frame.semantics`
    // directly — is what keeps the host-serialized derivations shared with
    // the web wire.
    let model = HostWireFrameModel(frame.hostProjection)
    let damage = model.damage
    return AndroidHostFrameSnapshot(
      sequence: frame.sequence,
      gridWidth: model.gridSize.width,
      gridHeight: model.gridSize.height,
      preferredGridWidth: model.preferredLayoutSize?.width,
      preferredGridHeight: model.preferredLayoutSize?.height,
      terminalStyle: AndroidHostTerminalStyleSnapshot(renderStyle: style.renderStyle),
      rows: model.plainTextRows(),
      cells: model.surface.cells.enumerated().flatMap { y, row in
        row.enumerated().map { x, cell in
          AndroidHostCellSnapshot(x: x, y: y, cell: cell)
        }
      },
      imageAttachments: imageAttachments(
        from: model.imageAttachments,
        fallbackBackground: style.renderStyle.appearance.backgroundColor
      ),
      focusedIdentity: model.focusedIdentity?.path,
      focusPresentation: AndroidHostFocusPresentationSnapshot(
        model.focusPresentation ?? FocusPresentation.none
      ),
      accessibilityNodes: model.accessibilityNodes.map(
        AndroidHostAccessibilityNodeSnapshot.init
      ),
      accessibilityAnnouncements: model.accessibilityAnnouncements.map(
        AndroidHostAccessibilityAnnouncementSnapshot.init
      ),
      scrollRegions: model.scrollRegions.isEmpty
        ? nil
        : model.scrollRegions.map(AndroidHostScrollRegionSnapshot.init),
      dirtyRows: damage?.dirtyRows.sorted() ?? [],
      textDamageRows: damage?.textRows.map(AndroidHostTextDamageRowSnapshot.init) ?? [],
      requiresFullTextRepaint: damage?.requiresFullTextRepaint ?? true,
      requiresFullGraphicsReplay: damage?.requiresFullGraphicsReplay ?? true
    )
  }

  public static func encode(
    _ frame: SemanticHostFrame,
    style: AndroidHostStyle = .default
  ) throws -> [UInt8] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Array(try encoder.encode(snapshot(for: frame, style: style)))
  }

  private static func imageAttachments(
    from attachments: [RasterImageAttachment],
    fallbackBackground: Color
  ) -> [AndroidHostImageAttachmentSnapshot] {
    attachments.map { attachment in
      AndroidHostImageAttachmentSnapshot(
        attachment: attachment,
        payload: imagePayload(for: attachment, fallbackBackground: fallbackBackground)
      )
    }
  }

  private static func imagePayload(
    for attachment: RasterImageAttachment,
    fallbackBackground: Color
  ) -> AndroidHostImagePayload? {
    if let payload = HostWireFrameModel.blendedImagePayload(
      for: attachment,
      compositor: imageBlendCompositor,
      fallbackBackground: fallbackBackground
    ) {
      return AndroidHostImagePayload(
        id: payload.id,
        sourceKind: "precomposedPNG",
        sourceIdentifier: payload.id,
        bytes: payload.bytes,
        pixelSize: payload.pixelSize
      )
    }

    switch attachment.resolvedReference {
    case .embeddedImage(let bytes):
      return AndroidHostImagePayload(
        id: attachment.identity.path,
        sourceKind: "embeddedImage",
        sourceIdentifier: attachment.identity.path,
        bytes: bytes,
        pixelSize: attachment.pixelSize
      )
    case .namedResource(let name):
      return AndroidHostImagePayload(
        id: attachment.identity.path,
        sourceKind: "namedResource",
        sourceIdentifier: name,
        bytes: nil,
        pixelSize: attachment.pixelSize
      )
    case .filePath(let path):
      return AndroidHostImagePayload(
        id: attachment.identity.path,
        sourceKind: "filePath",
        sourceIdentifier: path,
        bytes: nil,
        pixelSize: attachment.pixelSize
      )
    case nil:
      break
    }

    if case .data(let bytes) = attachment.source {
      return AndroidHostImagePayload(
        id: attachment.identity.path,
        sourceKind: "data",
        sourceIdentifier: attachment.identity.path,
        bytes: bytes,
        pixelSize: attachment.pixelSize
      )
    }

    return nil
  }
}

private struct AndroidHostImagePayload {
  var id: String
  var sourceKind: String
  var sourceIdentifier: String?
  var bytes: [UInt8]?
  var pixelSize: PixelSize?
}


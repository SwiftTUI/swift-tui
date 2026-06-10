import Foundation
public import SwiftTUIRuntime

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

public struct AndroidHostTextStyleSnapshot: Codable, Equatable, Sendable {
  public var foregroundColor: AndroidHostColorSnapshot?
  public var backgroundColor: AndroidHostColorSnapshot?
  public var emphasis: [String]
  public var underlineStyle: AndroidHostTextLineStyleSnapshot?
  public var strikethroughStyle: AndroidHostTextLineStyleSnapshot?
  public var opacity: Double

  public init(
    _ style: ResolvedTextStyle
  ) {
    foregroundColor = style.foregroundColor.map(AndroidHostColorSnapshot.init)
    backgroundColor = style.backgroundColor.map(AndroidHostColorSnapshot.init)
    emphasis = style.emphasis.debugNames
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
    id = node.identity.path
    parentID = node.parentIdentity?.path
    rect = AndroidHostCellRectSnapshot(node.rect)
    role = node.role.description
    label = node.label
    hint = node.hint
    hidden = node.hidden
    liveRegion = node.liveRegion?.description
    cursorAnchor = node.cursorAnchor.map(AndroidHostCellPointSnapshot.init)
    isFocused = node.identity == focusedIdentity
  }
}

public struct AndroidHostAccessibilityAnnouncementSnapshot: Codable, Equatable, Sendable {
  public var message: String
  public var politeness: String

  public init(
    _ announcement: AccessibilityAnnouncement
  ) {
    message = announcement.message
    politeness = announcement.politeness.description
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
    semantics = presentation.semantics.androidHostDescription
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
    let damage = frame.rasterDamage
    let focusPresentation = frame.semantics.focusPresentation(for: frame.focusedIdentity)
    return AndroidHostFrameSnapshot(
      sequence: frame.sequence,
      gridWidth: frame.raster.size.width,
      gridHeight: frame.raster.size.height,
      preferredGridWidth: frame.preferredLayoutSize?.width,
      preferredGridHeight: frame.preferredLayoutSize?.height,
      terminalStyle: AndroidHostTerminalStyleSnapshot(renderStyle: style.renderStyle),
      rows: rows(from: frame.raster),
      cells: cells(from: frame.raster),
      imageAttachments: imageAttachments(
        from: frame.raster.imageAttachments,
        fallbackBackground: style.renderStyle.appearance.backgroundColor
      ),
      focusedIdentity: frame.focusedIdentity?.path,
      focusPresentation: AndroidHostFocusPresentationSnapshot(focusPresentation),
      accessibilityNodes: frame.semantics.accessibilityNodes.map {
        AndroidHostAccessibilityNodeSnapshot($0, focusedIdentity: frame.focusedIdentity)
      },
      accessibilityAnnouncements: frame.semantics.accessibilityAnnouncements.map(
        AndroidHostAccessibilityAnnouncementSnapshot.init
      ),
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

  private static func rows(
    from surface: RasterSurface
  ) -> [String] {
    surface.cells.map { row in
      String(row.map(\.character))
    }
  }

  private static func cells(
    from surface: RasterSurface
  ) -> [AndroidHostCellSnapshot] {
    surface.cells.enumerated().flatMap { y, row in
      row.enumerated().map { x, cell in
        AndroidHostCellSnapshot(x: x, y: y, cell: cell)
      }
    }
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
    if let payload = imageBlendCompositor.encodedPNGPayload(
      for: attachment,
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

extension FocusPresentation.Semantics {
  fileprivate var androidHostDescription: String {
    switch self {
    case .none:
      "none"
    case .automatic:
      "automatic"
    case .activate:
      "activate"
    case .edit:
      "edit"
    }
  }
}

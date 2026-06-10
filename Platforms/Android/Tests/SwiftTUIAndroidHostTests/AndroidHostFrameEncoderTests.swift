import Foundation
import SwiftTUIAndroidHost
import SwiftTUIRuntime
import Testing

@Test
func android_host_frame_encoder_writes_versioned_host_frame_snapshot() throws {
  let imageIdentity = Identity(components: ["root", "image"])
  let focusedIdentity = Identity(components: ["root", "field"])
  let textStyle = ResolvedTextStyle(
    foregroundColor: try! .hex("#FF0000"),
    backgroundColor: try! .hex("#0000FF"),
    emphasis: [.bold, .italic],
    underlineStyle: TextLineStyle(color: try! .hex("#00FF00")),
    strikethroughStyle: TextLineStyle(pattern: .dash),
    opacity: 0.75
  )
  let frame = SemanticHostFrame(
    sequence: 42,
    raster: RasterSurface(
      size: CellSize(width: 4, height: 2),
      lines: [
        "Hi",
        "TUI",
      ],
      styleRuns: [
        RasterStyleRun(x: 0, y: 0, length: 2, style: textStyle)
      ],
      imageAttachments: [
        RasterImageAttachment(
          identity: imageIdentity,
          bounds: CellRect(origin: CellPoint(x: 1, y: 1), size: CellSize(width: 2, height: 1)),
          source: .data([1, 2, 3]),
          resolvedReference: .embeddedImage([1, 2, 3]),
          pixelSize: PixelSize(width: 3, height: 1),
          cellPixelSize: PixelSize(width: 9, height: 18),
          isResizable: true,
          scalingMode: .fit
        )
      ]
    ),
    semantics: SemanticSnapshot(
      focusRegions: [
        FocusRegion(
          identity: focusedIdentity,
          rect: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 4, height: 1)),
          focusInteractions: .edit
        )
      ],
      accessibilityNodes: [
        AccessibilityNode(
          identity: focusedIdentity,
          parentIdentity: Identity(components: ["root"]),
          rect: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 4, height: 1)),
          role: .textField,
          label: "Field",
          hint: "Type here",
          liveRegion: .polite,
          cursorAnchor: CellPoint(x: 1, y: 0)
        )
      ],
      accessibilityAnnouncements: [
        AccessibilityAnnouncement(message: "Ready", politeness: .assertive)
      ]
    ),
    focusedIdentity: focusedIdentity,
    rasterDamage: PresentationDamage(
      textRows: [PresentationDamage.TextRow(row: 1, columnRanges: [0..<3])]
    ),
    preferredLayoutSize: CellSize(width: 3, height: 2)
  )

  let bytes = try AndroidHostFrameEncoder.encode(frame)
  let snapshot = try JSONDecoder().decode(AndroidHostFrameSnapshot.self, from: Data(bytes))

  #expect(snapshot.schemaVersion == 2)
  #expect(snapshot.sequence == 42)
  #expect(snapshot.gridWidth == 4)
  #expect(snapshot.gridHeight == 2)
  #expect(snapshot.preferredGridWidth == 3)
  #expect(snapshot.preferredGridHeight == 2)
  #expect(snapshot.terminalStyle.foregroundColor.hex == "#ECEFF4FF")
  #expect(snapshot.terminalStyle.backgroundColor.hex == "#1E222AFF")
  #expect(snapshot.rows == ["Hi  ", "TUI "])
  #expect(snapshot.focusedIdentity == "root/field")
  #expect(snapshot.focusPresentation.focusedIdentity == "root/field")
  #expect(snapshot.focusPresentation.semantics == "edit")
  #expect(snapshot.focusPresentation.prefersTextInput)
  #expect(snapshot.cells.count == 8)
  #expect(snapshot.cells[0].character == "H")
  #expect(snapshot.cells[0].style?.foregroundColor?.hex == "#FF0000FF")
  #expect(snapshot.cells[0].style?.backgroundColor?.hex == "#0000FFFF")
  #expect(snapshot.cells[0].style?.emphasis == ["bold", "italic"])
  #expect(snapshot.cells[0].style?.underlineStyle?.color?.hex == "#00FF00FF")
  #expect(snapshot.cells[0].style?.strikethroughStyle?.pattern == "dash")
  #expect(snapshot.cells[0].style?.opacity == 0.75)
  #expect(snapshot.imageAttachments.count == 1)
  #expect(snapshot.imageAttachments[0].id == "root/image")
  #expect(snapshot.imageAttachments[0].payloadBase64 == "AQID")
  #expect(snapshot.imageAttachments[0].pixelSize == AndroidHostPixelSizeSnapshot(PixelSize(width: 3, height: 1)))
  #expect(snapshot.imageAttachments[0].scalingMode == "fit")
  #expect(snapshot.accessibilityNodes.count == 1)
  #expect(snapshot.accessibilityNodes[0].id == "root/field")
  #expect(snapshot.accessibilityNodes[0].parentID == "root")
  #expect(snapshot.accessibilityNodes[0].role == "textField")
  #expect(snapshot.accessibilityNodes[0].label == "Field")
  #expect(snapshot.accessibilityNodes[0].hint == "Type here")
  #expect(snapshot.accessibilityNodes[0].liveRegion == "polite")
  #expect(snapshot.accessibilityNodes[0].cursorAnchor == AndroidHostCellPointSnapshot(CellPoint(x: 1, y: 0)))
  #expect(snapshot.accessibilityNodes[0].isFocused)
  #expect(snapshot.accessibilityAnnouncements == [
    AndroidHostAccessibilityAnnouncementSnapshot(
      AccessibilityAnnouncement(message: "Ready", politeness: .assertive)
    )
  ])
  #expect(snapshot.dirtyRows == [1])
  #expect(snapshot.textDamageRows == [
    AndroidHostTextDamageRowSnapshot(
      PresentationDamage.TextRow(row: 1, columnRanges: [0..<3])
    )
  ])
  #expect(snapshot.requiresFullTextRepaint == false)
}

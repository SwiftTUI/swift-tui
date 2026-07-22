import Foundation
import SwiftTUIAndroidHost
import SwiftTUIRuntime
import Testing

/// Pins the Android frame snapshot wire against ``HostWireSchema`` in both
/// directions: a fully-populated frame must emit exactly the manifest's key
/// sets, so an encoder-dropped field and a manifest-only field both fail. The
/// focus-semantics tokens are additionally asserted against the shared map so
/// the two host wires cannot drift apart.
@Test
func android_host_frame_snapshot_emits_exactly_the_manifest_key_sets() throws {
  let record = try decodedFrameSnapshot(wireTotalityFrame())

  #expect(
    Set(record.keys)
      == HostWireSchema.AndroidWire.frameKeys
      .union(HostWireSchema.AndroidWire.frameOptionalKeys)
  )

  let cells = try #require(record["cells"] as? [[String: Any]])
  let cellKeys = cells.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
  #expect(cellKeys == HostWireSchema.AndroidWire.cellKeys)

  let styles = cells.compactMap { $0["style"] as? [String: Any] }
  #expect(!styles.isEmpty)
  let styleKeys = styles.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
  #expect(styleKeys == HostWireSchema.AndroidWire.styleKeys)
  let underline = try #require(
    styles.compactMap { $0["underlineStyle"] as? [String: Any] }.first
  )
  #expect(Set(underline.keys) == HostWireSchema.AndroidWire.lineStyleKeys)

  let terminalStyle = try #require(record["terminalStyle"] as? [String: Any])
  #expect(Set(terminalStyle.keys) == HostWireSchema.AndroidWire.terminalStyleKeys)
  let terminalForeground = try #require(terminalStyle["foregroundColor"] as? [String: Any])
  #expect(Set(terminalForeground.keys) == HostWireSchema.AndroidWire.colorKeys)

  let images = try #require(record["imageAttachments"] as? [[String: Any]])
  let imageKeys = images.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
  #expect(imageKeys == HostWireSchema.AndroidWire.imageAttachmentKeys)
  let imageBounds = try #require(images.first?["bounds"] as? [String: Any])
  #expect(Set(imageBounds.keys) == HostWireSchema.AndroidWire.rectKeys)
  let imagePixelSize = try #require(images.first?["pixelSize"] as? [String: Any])
  #expect(Set(imagePixelSize.keys) == HostWireSchema.AndroidWire.sizeKeys)

  let focusPresentation = try #require(record["focusPresentation"] as? [String: Any])
  #expect(Set(focusPresentation.keys) == HostWireSchema.AndroidWire.focusPresentationKeys)

  let nodes = try #require(record["accessibilityNodes"] as? [[String: Any]])
  #expect(
    Set(try #require(nodes.first).keys) == HostWireSchema.AndroidWire.accessibilityNodeKeys
  )
  let cursorAnchor = try #require(nodes.first?["cursorAnchor"] as? [String: Any])
  #expect(Set(cursorAnchor.keys) == HostWireSchema.AndroidWire.pointKeys)

  let announcements = try #require(record["accessibilityAnnouncements"] as? [[String: Any]])
  #expect(
    Set(try #require(announcements.first).keys)
      == HostWireSchema.AndroidWire.accessibilityAnnouncementKeys
  )

  let scrollRegions = try #require(record["scrollRegions"] as? [[String: Any]])
  #expect(
    Set(try #require(scrollRegions.first).keys)
      == HostWireSchema.AndroidWire.scrollRegionKeys
  )

  let textDamageRows = try #require(record["textDamageRows"] as? [[String: Any]])
  #expect(
    Set(try #require(textDamageRows.first).keys)
      == HostWireSchema.AndroidWire.textDamageRowKeys
  )
  let ranges = try #require(textDamageRows.first?["columnRanges"] as? [[String: Any]])
  #expect(Set(try #require(ranges.first).keys) == HostWireSchema.AndroidWire.rangeKeys)
}

@Test
func android_host_focus_semantics_tokens_match_the_shared_wire_map() throws {
  let record = try decodedFrameSnapshot(wireTotalityFrame())
  let focusPresentation = try #require(record["focusPresentation"] as? [String: Any])

  #expect(
    focusPresentation["semantics"] as? String == HostWireSchema.focusSemanticsToken(.edit)
  )
  #expect(focusPresentation["prefersTextInput"] as? Bool == true)
  #expect(focusPresentation["hasFocusedRegion"] as? Bool == true)
}

@Test
func android_host_totality_fixture_matches_encoder_output() throws {
  // `Fixtures/Transport/android-frame-totality.json` is the cross-repo
  // canonical fixture: swift-tui-android's SwiftTUIFrameTest parses a
  // byte-identical copy from its test resources, and the coordination root's
  // transport_fixture_sync gate keeps the copies in lockstep. Regenerate with
  // STUI_REGENERATE_TRANSPORT_FIXTURES=1 (see docs/DEVELOPMENT.md).
  let encoded = String(decoding: try AndroidHostFrameEncoder.encode(wireTotalityFrame()), as: UTF8.self)
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")
    .appendingPathComponent("Transport")
    .appendingPathComponent("android-frame-totality.json")

  if ProcessInfo.processInfo.environment["STUI_REGENERATE_TRANSPORT_FIXTURES"] == "1" {
    try (encoded + "\n").write(to: url, atomically: true, encoding: .utf8)
  }

  let fixture = try String(contentsOf: url, encoding: .utf8)
  #expect(encoded == fixture.trimmingCharacters(in: .newlines))
}

@Test
func android_host_composited_image_fixture_matches_encoder_output() throws {
  // `Fixtures/Transport/android-frame-composited-image.json` byte-pins the
  // image pre-blend contract: a compositing-tagged attachment is replaced on
  // the wire by the deterministic blended PNG payload, tagged
  // `sourceKind:"precomposedPNG"` — the Android encoder pre-blends exactly
  // like web (the manifest's old "unblended" divergence text was wrong).
  // swift-tui-android's SwiftTUIFrameTest parses a byte-identical copy and
  // the coordination root's transport_fixture_sync gate keeps the copies in
  // lockstep. Regenerate with STUI_REGENERATE_TRANSPORT_FIXTURES=1.
  let frame = compositedImageFrame()

  // Red-proof that the pre-blend path engaged: the payload must be the
  // blended PNG under its stable content-hash ID, not the raw source bytes.
  let record = try decodedFrameSnapshot(frame)
  let images = try #require(record["imageAttachments"] as? [[String: Any]])
  #expect(images.first?["sourceKind"] as? String == "precomposedPNG")
  let imageID = try #require(images.first?["id"] as? String)
  #expect(imageID.hasPrefix("blend:png:"))
  #expect(images.first?["payloadBase64"] != nil)

  let encoded = String(decoding: try AndroidHostFrameEncoder.encode(frame), as: UTF8.self)
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")
    .appendingPathComponent("Transport")
    .appendingPathComponent("android-frame-composited-image.json")

  if ProcessInfo.processInfo.environment["STUI_REGENERATE_TRANSPORT_FIXTURES"] == "1" {
    try (encoded + "\n").write(to: url, atomically: true, encoding: .utf8)
  }

  let fixture = try String(contentsOf: url, encoding: .utf8)
  #expect(encoded == fixture.trimmingCharacters(in: .newlines))
}

/// One compositing-tagged attachment over a captured blue backdrop. The
/// blend inputs are exact-arithmetic by construction (opaque red source,
/// `.normal` blend) so the blended PNG bytes are platform-stable and safe to
/// byte-freeze.
private func compositedImageFrame() -> SemanticHostFrame {
  let pngBytes: [UInt8] = Array(
    Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAEElEQVR4AQEFAPr/AP8AAP8FAAH/+lyI0QAAAABJRU5ErkJggg=="
    )!
  )
  let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
  return SemanticHostFrame(
    sequence: 41,
    raster: RasterSurface(
      size: CellSize(width: 2, height: 1),
      cells: [[RasterCell(character: "i"), RasterCell(character: " ")]],
      imageAttachments: [
        RasterImageAttachment(
          identity: Identity(components: ["root", "blend"]),
          bounds: bounds,
          source: .data(pngBytes),
          resolvedReference: .embeddedImage(pngBytes),
          pixelSize: PixelSize(width: 2, height: 2),
          cellPixelSize: PixelSize(width: 2, height: 2),
          scalingMode: .fit,
          compositing: RasterImageCompositing(
            blendMode: .normal,
            destinationBackdrop: RasterImageBackdrop(
              bounds: bounds,
              cells: [RasterImageBackdropCell(backgroundColor: .blue)]
            ),
            cellPixelSize: PixelSize(width: 2, height: 2),
            backdropSignature: 0xF18
          )
        )
      ]
    ),
    semantics: SemanticSnapshot(),
    focusedIdentity: nil
  )
}

/// Every host-serialized field populated to a distinctive non-default value.
/// Two cells cover the union of cell keys (a styled hyperlink lead and a
/// continuation); two image attachments cover the union of image keys (an
/// embedded-payload one and a path-sourced one).
private func wireTotalityFrame() -> SemanticHostFrame {
  let focused = Identity(components: ["root", "field"])
  let styled = ResolvedTextStyle(
    foregroundColor: try! .hex("#FF0000"),
    backgroundColor: try! .hex("#0000FF"),
    emphasis: [.bold, .italic],
    underlineStyle: TextLineStyle(pattern: .double, color: try! .hex("#00FF00")),
    strikethroughStyle: TextLineStyle(pattern: .dot, color: try! .hex("#FF00FF")),
    opacity: 0.75
  )
  let pngBytes: [UInt8] = Array(
    Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAEElEQVR4AQEFAPr/AP8AAP8FAAH/+lyI0QAAAABJRU5ErkJggg=="
    )!
  )
  return SemanticHostFrame(
    sequence: 99,
    raster: RasterSurface(
      size: CellSize(width: 4, height: 1),
      cells: [
        [
          RasterCell(
            character: "宽", spanWidth: 2, style: styled, hyperlink: "https://a.example/docs"),
          RasterCell(
            character: " ", spanWidth: 0, continuationLeadX: 0,
            hyperlink: "https://a.example/docs"),
          RasterCell(character: "c"),
          RasterCell(character: " "),
        ]
      ],
      imageAttachments: [
        RasterImageAttachment(
          identity: Identity(components: ["root", "image"]),
          bounds: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
          source: .data(pngBytes),
          resolvedReference: .embeddedImage(pngBytes),
          pixelSize: PixelSize(width: 1, height: 1),
          cellPixelSize: PixelSize(width: 3, height: 6),
          isResizable: true,
          scalingMode: .fit
        ),
        RasterImageAttachment(
          identity: Identity(components: ["root", "pathImage"]),
          bounds: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
          source: .path("assets/red.png")
        ),
      ]
    ),
    semantics: SemanticSnapshot(
      focusRegions: [
        FocusRegion(
          identity: focused,
          rect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
          focusInteractions: .edit
        )
      ],
      scrollRoutes: [
        ScrollRoute(
          identity: Identity(components: ["root", "list"]),
          viewportRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
          contentBounds: CellRect(origin: .zero, size: CellSize(width: 4, height: 9)),
          contentOffset: CellPoint(x: 0, y: 2)
        )
      ],
      accessibilityNodes: [
        AccessibilityNode(
          identity: focused,
          parentIdentity: Identity(components: ["root"]),
          rect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
          role: .textField,
          label: "Field",
          hint: "Type here",
          hidden: true,
          liveRegion: .polite,
          cursorAnchor: CellPoint(x: 1, y: 0)
        )
      ],
      accessibilityAnnouncements: [
        AccessibilityAnnouncement(message: "Ready", politeness: .assertive)
      ]
    ),
    focusedIdentity: focused,
    rasterDamage: PresentationDamage(
      textRows: [PresentationDamage.TextRow(row: 0, columnRanges: [0..<2])]
    ),
    preferredLayoutSize: CellSize(width: 9, height: 8)
  )
}

private func decodedFrameSnapshot(
  _ frame: SemanticHostFrame
) throws -> [String: Any] {
  let bytes = try AndroidHostFrameEncoder.encode(frame)
  let decoded = try JSONSerialization.jsonObject(with: Data(bytes))
  return try #require(decoded as? [String: Any])
}

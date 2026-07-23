import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

/// Pins the web `surface` wire against ``HostWireSchema`` in both directions:
/// a fully-populated frame must emit exactly the manifest's key sets, so a
/// field the encoder drops (the F19 class: `hyperlink`, accessibility
/// `hidden`, `focusPresentation`, preferred grid size all shipped silently
/// missing on web) and a manifest entry the encoder never learned both fail.
@Suite
struct WebSurfaceWireTotalityTests {
  @Test("a fully-populated full frame emits exactly the manifest key sets")
  func fullFrameEmitsExactlyTheManifestSurface() throws {
    var knownImageIDs: Set<String> = []
    let record = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        HostWireFrameModel(
          Self.fullyPopulatedFrame().hostProjection,
          terminalStyle: Self.totalityTerminalStyle
        ),
        fallbackBackground: TerminalAppearance.fallback.backgroundColor,
        knownImageIDs: &knownImageIDs
      )
    )

    #expect(
      Set(record.keys)
        == HostWireSchema.WebWire.fullFrameKeys
        .union(HostWireSchema.WebWire.fullFrameOptionalKeys)
    )
    #expect(record["version"] as? Int == 2)

    let styles = try #require(record["styles"] as? [Any])
    let styleObjects = styles.compactMap { $0 as? [String: Any] }
    #expect(!styleObjects.isEmpty)
    let styleKeys = styleObjects.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
    #expect(styleKeys == HostWireSchema.WebWire.styleKeys)
    let underline = try #require(
      styleObjects.compactMap { $0["underline"] as? [String: Any] }.first
    )
    #expect(Set(underline.keys) == HostWireSchema.WebWire.lineStyleKeys)

    for row in try #require(record["rows"] as? [[Any]]) {
      for cell in row {
        let tuple = try #require(cell as? [Any])
        #expect(tuple.count == HostWireSchema.WebWire.cellTupleArity)
      }
    }

    let images = try #require(record["images"] as? [[String: Any]])
    #expect(Set(try #require(images.first).keys) == HostWireSchema.WebWire.imageKeys)

    let damage = try #require(record["damage"] as? [String: Any])
    #expect(Set(damage.keys) == HostWireSchema.WebWire.damageKeys)

    let nodes = try #require(record["accessibilityTree"] as? [[String: Any]])
    #expect(
      Set(try #require(nodes.first).keys) == HostWireSchema.WebWire.accessibilityNodeKeys
    )

    let announcements = try #require(record["accessibilityAnnouncements"] as? [[String: Any]])
    #expect(
      Set(try #require(announcements.first).keys)
        == HostWireSchema.WebWire.accessibilityAnnouncementKeys
    )

    let scrollRegions = try #require(record["scrollRegions"] as? [[String: Any]])
    #expect(
      Set(try #require(scrollRegions.first).keys) == HostWireSchema.WebWire.scrollRegionKeys
    )

    let focusPresentation = try #require(record["focusPresentation"] as? [String: Any])
    #expect(Set(focusPresentation.keys) == HostWireSchema.WebWire.focusPresentationKeys)
    #expect(
      focusPresentation["semantics"] as? String == HostWireSchema.focusSemanticsToken(.edit)
    )
    #expect(focusPresentation["prefersTextInput"] as? Bool == true)
    #expect(focusPresentation["hasFocusedRegion"] as? Bool == true)
    #expect(focusPresentation["focusedIdentity"] as? String == "root/field")

    #expect(record["preferredGridWidth"] as? Int == 9)
    #expect(record["preferredGridHeight"] as? Int == 8)

    let terminalStyle = try #require(record["terminalStyle"] as? [String: Any])
    #expect(Set(terminalStyle.keys) == HostWireSchema.WebWire.terminalStyleKeys)
    let tintColor = try #require(terminalStyle["tintColor"] as? [String: Any])
    #expect(Set(tintColor.keys) == HostWireSchema.WebWire.colorKeys)
    #expect(tintColor["hex"] as? String == "#708090FF")
  }

  @Test("hyperlink cells emit deduplicated link targets and per-row runs")
  func hyperlinkCellsEmitLinkRunsAndTargets() throws {
    let record = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(Self.fullyPopulatedFrame())
    )

    let targets = try #require(record["linkTargets"] as? [String])
    #expect(targets == ["https://a.example/docs", "https://b.example"])

    let links = try #require(record["links"] as? [[Any]])
    #expect(links.count == 2)
    for linkRow in links {
      #expect(linkRow.count == HostWireSchema.WebWire.linkRowTupleArity)
      for run in try #require(linkRow[1] as? [[Any]]) {
        #expect(run.count == HostWireSchema.WebWire.linkRunTupleArity)
      }
    }
    // Row 0: an "ab" run on target 0, then "c" on target 1. Row 1: the wide
    // lead cell's span covers its continuation — one two-column run.
    let rowZeroRuns = try #require(links[0][1] as? [[Int]])
    #expect(links[0][0] as? Int == 0)
    #expect(rowZeroRuns == [[0, 2, 0], [2, 1, 1]])
    let rowOneRuns = try #require(links[1][1] as? [[Int]])
    #expect(links[1][0] as? Int == 1)
    #expect(rowOneRuns == [[0, 2, 0]])
  }

  @Test("a fully-populated delta frame emits exactly the manifest key sets")
  func deltaFrameEmitsExactlyTheManifestSurface() throws {
    var state = WebSurfaceFrameEncodingState(deltaEnabled: true)
    _ = WebSurfaceFrameEncoder.encode(
      HostWireFrameModel(
        Self.fullyPopulatedFrame().hostProjection,
        terminalStyle: Self.totalityTerminalStyle
      ),
      fallbackBackground: TerminalAppearance.fallback.backgroundColor,
      state: &state
    )

    let record = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        HostWireFrameModel(
          Self.fullyPopulatedFrame(
            sequence: 100,
            damage: PresentationDamage(
              textRows: [PresentationDamage.TextRow(row: 0, columnRanges: [0..<2])]
            )
          ).hostProjection,
          terminalStyle: Self.totalityTerminalStyle
        ),
        fallbackBackground: TerminalAppearance.fallback.backgroundColor,
        state: &state
      )
    )

    #expect(record["version"] as? Int == 3)
    #expect(record["encoding"] as? String == "delta")
    #expect(
      Set(record.keys)
        == HostWireSchema.WebWire.deltaFrameKeys
        .union(HostWireSchema.WebWire.deltaFrameOptionalKeys)
    )
    for deltaRow in try #require(record["deltaRows"] as? [[Any]]) {
      for cell in try #require(deltaRow[1] as? [[Any]]) {
        #expect(cell.count == HostWireSchema.WebWire.cellTupleArity)
      }
    }
  }

  @Test("additive fields ride version-1 raster frames without a version bump")
  func additiveFieldsDoNotBumpTheVersionLiteral() throws {
    let record = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(Self.linkedRasterSurface())
    )

    // Deployed decoders hard-match version literals; additive fields must not
    // move them (see the HostWireSchema wire-evolution policy).
    #expect(record["version"] as? Int == 1)
    #expect(record["links"] != nil)
    #expect(record["linkTargets"] != nil)
    #expect(
      Set(record.keys)
        == HostWireSchema.WebWire.fullFrameKeys.union(["links", "linkTargets"])
    )
  }

  @Test("default frames omit every optional field")
  func defaultFramesOmitOptionalFields() throws {
    let record = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        RasterSurface(size: CellSize(width: 2, height: 1), lines: ["ok"])
      )
    )

    #expect(Set(record.keys) == HostWireSchema.WebWire.fullFrameKeys)
    #expect(record["version"] as? Int == 1)
  }

  @Test("hidden is emitted only for hidden accessibility nodes")
  func hiddenEmitsOnlyWhenTrue() throws {
    let identity = Identity(components: ["root", "row"])
    let record = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        SemanticHostFrame(
          sequence: 7,
          raster: RasterSurface(size: CellSize(width: 2, height: 1), lines: ["ok"]),
          semantics: SemanticSnapshot(
            accessibilityNodes: [
              AccessibilityNode(
                identity: identity,
                rect: CellRect(origin: .zero, size: CellSize(width: 2, height: 1)),
                role: .group,
                hidden: true
              ),
              AccessibilityNode(
                identity: identity.child("visible"),
                rect: CellRect(origin: .zero, size: CellSize(width: 2, height: 1)),
                role: .group
              ),
            ]
          ),
          focusedIdentity: nil
        )
      )
    )

    let nodes = try #require(record["accessibilityTree"] as? [[String: Any]])
    #expect(nodes.count == 2)
    #expect(nodes[0]["hidden"] as? Bool == true)
    #expect(nodes[1]["hidden"] == nil)
  }

  @Test("the canonical shared totality fixture matches the encoder output")
  func canonicalFixtureMatchesEncoderOutput() throws {
    // `Fixtures/Transport/web-surface-totality.txt` is the cross-repo
    // canonical fixture: swift-tui-web's decoder tests parse a byte-identical
    // copy, and the coordination root's transport_fixture_sync gate keeps the
    // copies in lockstep — so this pin is what makes an encoder change
    // propagate loudly to the sibling repo instead of silently drifting.
    // Regenerate with STUI_REGENERATE_TRANSPORT_FIXTURES=1, then re-run the
    // sync flow described in docs/DEVELOPMENT.md.
    var knownImageIDs: Set<String> = []
    let encoded = WebSurfaceFrameEncoder.encode(
      HostWireFrameModel(
        Self.fullyPopulatedFrame().hostProjection,
        terminalStyle: Self.totalityTerminalStyle
      ),
      fallbackBackground: TerminalAppearance.fallback.backgroundColor,
      knownImageIDs: &knownImageIDs
    )
    let url = Self.fixtureURL("web-surface-totality.txt")

    if ProcessInfo.processInfo.environment["STUI_REGENERATE_TRANSPORT_FIXTURES"] == "1" {
      try encoded
        .replacingOccurrences(of: "\u{001E}", with: "\\u001E")
        .write(to: url, atomically: true, encoding: .utf8)
    }

    let fixture = try String(contentsOf: url, encoding: .utf8)
      .replacingOccurrences(of: "\\u001E", with: "\u{001E}")
    #expect(encoded == fixture)
  }

  @Test("the canonical composited-image fixture matches the encoder output")
  func compositedImageFixtureMatchesEncoderOutput() throws {
    // `Fixtures/Transport/web-surface-composited-image.txt` byte-pins the
    // image pre-blend contract: an attachment carrying `compositing` metadata
    // is replaced on the wire by the deterministic blended PNG payload
    // (stable `blend:png:` content-hash ID, blended bytes, visible bounds).
    // swift-tui-web parses a byte-identical copy and the coordination root's
    // transport_fixture_sync gate keeps the copies in lockstep. Regenerate
    // with STUI_REGENERATE_TRANSPORT_FIXTURES=1.
    let encoded = WebSurfaceFrameEncoder.encode(Self.compositedImageFrame())

    // Red-proof that the pre-blend path engaged: a compositing-tagged
    // attachment must emit the blended payload, not its raw source bytes.
    let record = try Self.decodedSurfaceFrame(encoded)
    let images = try #require(record["images"] as? [[String: Any]])
    let imageID = try #require(images.first?["id"] as? String)
    #expect(imageID.hasPrefix("blend:png:"))
    #expect(images.first?["format"] as? String == "png")
    #expect(images.first?["dataBase64"] != nil)

    let url = Self.fixtureURL("web-surface-composited-image.txt")
    if ProcessInfo.processInfo.environment["STUI_REGENERATE_TRANSPORT_FIXTURES"] == "1" {
      try encoded
        .replacingOccurrences(of: "\u{001E}", with: "\\u001E")
        .write(to: url, atomically: true, encoding: .utf8)
    }

    let fixture = try String(contentsOf: url, encoding: .utf8)
      .replacingOccurrences(of: "\\u001E", with: "\u{001E}")
    #expect(encoded == fixture)
  }

  // MARK: - Fixtures

  private static func fixtureURL(
    _ filename: String
  ) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("Transport")
      .appendingPathComponent(filename)
  }

  /// A distinctive resolved appearance for the terminalStyle additive key —
  /// emitted only on streams whose host consumes a runtime-owned style (the
  /// converged Android path); the browser-path tests above never pass one.
  private static let totalityTerminalStyle = TerminalRenderStyle(
    appearance: TerminalAppearance(
      foregroundColor: try! .hex("#102030"),
      backgroundColor: try! .hex("#405060"),
      tintColor: try! .hex("#708090"),
      source: .override
    )
  )

  /// Every host-serialized field populated to a distinctive non-default value,
  /// including the fields the web wire historically dropped: hyperlinks, a
  /// hidden accessibility node, an `.edit` focus region, and a preferred
  /// layout size.
  private static func fullyPopulatedFrame(
    sequence: UInt64 = 99,
    damage: PresentationDamage? = PresentationDamage(
      textRows: [PresentationDamage.TextRow(row: 1, columnRanges: [0..<2])]
    )
  ) -> SemanticHostFrame {
    let focused = Identity(components: ["root", "field"])
    return SemanticHostFrame(
      sequence: sequence,
      raster: Self.linkedRasterSurface(),
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
            viewportRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 2)),
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
      rasterDamage: damage,
      preferredLayoutSize: CellSize(width: 9, height: 8)
    )
  }

  /// Four columns, two rows: an "ab" link run and a "c" link on row 0, a wide
  /// lead + continuation pair sharing a link on row 1, plus a fully-populated
  /// text style and a decodable PNG image attachment.
  private static func linkedRasterSurface() -> RasterSurface {
    let styled = ResolvedTextStyle(
      foregroundColor: .red,
      backgroundColor: .black,
      emphasis: [.bold, .italic],
      underlineStyle: TextLineStyle(pattern: .double, color: .yellow),
      strikethroughStyle: TextLineStyle(pattern: .dot, color: .red),
      opacity: 0.75
    )
    return RasterSurface(
      size: CellSize(width: 4, height: 2),
      cells: [
        [
          RasterCell(character: "a", style: styled, hyperlink: "https://a.example/docs"),
          RasterCell(character: "b", hyperlink: "https://a.example/docs"),
          RasterCell(character: "c", hyperlink: "https://b.example"),
          RasterCell(character: "d"),
        ],
        [
          RasterCell(character: "宽", spanWidth: 2, hyperlink: "https://a.example/docs"),
          RasterCell(
            character: " ", spanWidth: 0, continuationLeadX: 0,
            hyperlink: "https://a.example/docs"),
          RasterCell(character: "e"),
          RasterCell(character: " "),
        ],
      ],
      imageAttachments: [
        RasterImageAttachment(
          identity: Identity(components: ["root", "image"]),
          bounds: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
          source: .data(Self.redPixelPNGBytes()),
          resolvedReference: .embeddedImage(Self.redPixelPNGBytes()),
          pixelSize: PixelSize(width: 1, height: 1)
        )
      ]
    )
  }

  /// One compositing-tagged attachment over a captured blue backdrop. The
  /// blend inputs are exact-arithmetic by construction (opaque red source,
  /// `.normal` blend) so the blended PNG bytes are platform-stable and safe
  /// to byte-freeze.
  private static func compositedImageFrame() -> SemanticHostFrame {
    let pngBytes = Self.redPixelPNGBytes()
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

  private static func redPixelPNGBytes() -> [UInt8] {
    Array(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAEElEQVR4AQEFAPr/AP8AAP8FAAH/+lyI0QAAAABJRU5ErkJggg=="
      )!
    )
  }

  private static func decodedSurfaceFrame(
    _ output: String
  ) throws -> [String: Any] {
    let prefix = "\u{001E}surface:"
    let line = output.trimmingCharacters(in: .newlines)
    #expect(line.hasPrefix(prefix))
    let json = String(line.dropFirst(prefix.count))
    let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try #require(decoded as? [String: Any])
  }
}

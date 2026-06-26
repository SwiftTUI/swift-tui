import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// Locks ``HostFrameProjection`` as the **faithful single seam** through which
/// the WASI and Android encoders read a ``SemanticHostFrame``.
///
/// The cross-host serialization bug class is "add a host-serialized field, wire
/// it into one of the two ~570-line encoders, forget the other → silent data
/// drop on that host." The projection collapses the two read sites into one. The
/// guard below feeds a frame with a distinctive, **non-default** value in every
/// host-serialized field and asserts the projection surfaces each unchanged — so
/// a regression that drops a field in the projection builder (the now-single
/// place encoders read) fails here, before it can reach a host. Adding a new
/// host-serialized field means surfacing it on the projection and extending this
/// fixture.
@Suite
struct HostFrameProjectionContractTests {
  /// A frame with every host-serialized field populated to a distinctive,
  /// non-empty value.
  private func fullyPopulatedFrame() -> SemanticHostFrame {
    let focused = Identity(components: ["root", "field"])
    let scrollIdentity = Identity(components: ["root", "list"])
    return SemanticHostFrame(
      sequence: 99,
      raster: RasterSurface(
        size: CellSize(width: 3, height: 2),
        lines: ["ab", "cd"],
        styleRuns: [],
        imageAttachments: [
          RasterImageAttachment(
            identity: Identity(components: ["root", "image"]),
            bounds: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 1, height: 1)),
            source: .data([9, 9, 9]),
            resolvedReference: .embeddedImage([9, 9, 9]),
            pixelSize: PixelSize(width: 1, height: 1),
            cellPixelSize: PixelSize(width: 3, height: 6),
            isResizable: false,
            scalingMode: .fit
          )
        ]
      ),
      semantics: SemanticSnapshot(
        focusRegions: [
          FocusRegion(
            identity: focused,
            rect: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 3, height: 1)),
            focusInteractions: .edit
          )
        ],
        scrollRoutes: [
          ScrollRoute(
            identity: scrollIdentity,
            viewportRect: CellRect(
              origin: CellPoint(x: 0, y: 0), size: CellSize(width: 3, height: 2)),
            contentBounds: CellRect(
              origin: CellPoint(x: 0, y: 0), size: CellSize(width: 3, height: 9)),
            contentOffset: CellPoint(x: 0, y: 2)
          )
        ],
        accessibilityNodes: [
          AccessibilityNode(
            identity: focused,
            parentIdentity: Identity(components: ["root"]),
            rect: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 3, height: 1)),
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
      focusedIdentity: focused,
      rasterDamage: PresentationDamage(
        textRows: [PresentationDamage.TextRow(row: 1, columnRanges: [0..<2])]
      ),
      preferredLayoutSize: CellSize(width: 9, height: 8)
    )
  }

  @Test("the projection surfaces every host-serialized frame field faithfully")
  func projectionSurfacesEveryHostFieldFaithfully() {
    let frame = fullyPopulatedFrame()
    let projection = frame.hostProjection

    // Directly-carried fields round-trip unchanged.
    #expect(projection.sequence == frame.sequence)
    #expect(projection.raster == frame.raster)
    #expect(projection.preferredLayoutSize == frame.preferredLayoutSize)
    #expect(projection.focusedIdentity == frame.focusedIdentity)
    #expect(projection.rasterDamage == frame.rasterDamage)
    #expect(projection.semantics == frame.semantics)

    // The host-serialized semantic subset accessors are faithful to the snapshot.
    #expect(projection.accessibilityNodes == frame.semantics.accessibilityNodes)
    #expect(projection.accessibilityAnnouncements == frame.semantics.accessibilityAnnouncements)
    #expect(projection.scrollRoutes == frame.semantics.scrollRoutes)

    // The focus presentation is the same single derivation both hosts consume.
    #expect(
      projection.focusPresentation
        == frame.semantics.focusPresentation(for: frame.focusedIdentity)
    )
  }

  @Test("no host-serialized field collapses to a default through the projection")
  func noHostFieldCollapsesToADefault() {
    let projection = fullyPopulatedFrame().hostProjection

    // Every host-serialized field is non-empty in the fixture; a builder
    // regression that drops one to its default would surface as an empty/nil
    // value here even if the round-trip equality above were also changed.
    #expect(projection.sequence == 99)
    #expect(projection.raster.size == CellSize(width: 3, height: 2))
    #expect(!projection.raster.imageAttachments.isEmpty)
    #expect(projection.preferredLayoutSize != nil)
    #expect(projection.focusedIdentity != nil)
    #expect(projection.rasterDamage != nil)
    #expect(!projection.accessibilityNodes.isEmpty)
    #expect(!projection.accessibilityAnnouncements.isEmpty)
    #expect(!projection.scrollRoutes.isEmpty)
    #expect(projection.focusPresentation.prefersTextInput)
  }
}

import Testing

@testable import SwiftTUIGraph

/// Direct units for the anchor/placed-frame math (F110): 338 lines of pure
/// deterministic geometry whose failures previously masqueraded as layout
/// bugs — `PlacedFrameTable` appeared in exactly three `LayoutEngineTests`
/// assertions and the fragment/translation math, payload lookup preference,
/// and miss/duplicate diagnostics had no direct tests at all.
@Suite("Anchor types and placed-frame table")
struct AnchorTypesTests {
  private func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CellRect {
    CellRect(origin: .init(x: x, y: y), size: .init(width: w, height: h))
  }

  private func entry(
    _ name: String,
    bounds: CellRect,
    nodeID: ViewNodeID? = nil,
    space: String? = nil
  ) -> PlacedFrameTableEntry {
    PlacedFrameTableEntry(
      viewNodeID: nodeID,
      identity: testIdentity("Root", name),
      bounds: bounds,
      namedCoordinateSpaceName: space
    )
  }

  @Test(
    "fragment translation composes: two steps equal their sum",
    arguments: [
      (CellPoint(x: 3, y: 5), CellPoint(x: -1, y: 2)),
      (CellPoint(x: 0, y: 0), CellPoint(x: 7, y: -4)),
      (CellPoint(x: -6, y: -6), CellPoint(x: 6, y: 6)),
    ]
  )
  func fragmentTranslationComposes(_ deltas: (CellPoint, CellPoint)) {
    let entries = [entry("Leaf", bounds: rect(10, 20, 4, 2))]
    let (d1, d2) = deltas

    var stepwise = PlacedFrameTable()
    stepwise.record(
      PlacedFrameTableFragment(entries: entries[...]).translated(by: d1).translated(by: d2))

    var summed = PlacedFrameTable()
    summed.record(
      PlacedFrameTableFragment(
        entries: entries[...],
        translation: CellPoint(x: d1.x + d2.x, y: d1.y + d2.y)
      )
    )

    #expect(stepwise == summed)
    #expect(
      stepwise.frame(for: testIdentity("Root", "Leaf"))
        == rect(10 + d1.x + d2.x, 20 + d1.y + d2.y, 4, 2)
    )
  }

  @Test("a zero-translation fragment records entries verbatim and reports the count")
  func zeroTranslationFragmentIsIdentity() {
    let entries = [
      entry("A", bounds: rect(1, 2, 3, 4)),
      entry("B", bounds: rect(5, 6, 7, 8)),
    ]
    var table = PlacedFrameTable()
    let recorded = table.record(PlacedFrameTableFragment(entries: entries[...]))

    #expect(recorded == 2)
    #expect(table.frame(for: testIdentity("Root", "A")) == rect(1, 2, 3, 4))
    #expect(table.frame(for: testIdentity("Root", "B")) == rect(5, 6, 7, 8))
  }

  @Test("payload lookup prefers the node ID and falls back to identity")
  func payloadLookupPrefersNodeID() {
    let nodeID = ViewNodeID(rawValue: 7)
    var table = PlacedFrameTable()
    table.record(
      viewNodeID: nodeID,
      identity: testIdentity("Root", "Owner"),
      bounds: rect(0, 0, 10, 1),
      namedCoordinateSpaceName: nil
    )
    // A later same-identity record WITHOUT the node ID: identity map moves,
    // node-ID map keeps the original — the payload with the node ID must
    // still resolve through it.
    table.record(
      viewNodeID: nil,
      identity: testIdentity("Root", "Owner"),
      bounds: rect(2, 2, 10, 1),
      namedCoordinateSpaceName: nil
    )

    let byNode = table.frame(
      for: AnchorPayload(viewNodeID: nodeID, identity: testIdentity("Root", "Owner"), kind: .bounds)
    )
    #expect(byNode == rect(0, 0, 10, 1))

    let byIdentity = table.frame(
      for: AnchorPayload(
        viewNodeID: ViewNodeID(rawValue: 999), identity: testIdentity("Root", "Owner"),
        kind: .bounds
      )
    )
    #expect(byIdentity == rect(2, 2, 10, 1), "an unknown node ID falls back to the identity map")
  }

  @Test("anchor-resolution misses count once each and pin the first identity")
  func anchorResolutionMissDiagnostics() {
    let recorder = GeometryResolutionDiagnosticsRecorder()
    let table = PlacedFrameTable(diagnosticsRecorder: recorder)

    #expect(table.frame(for: testIdentity("Root", "First")) == nil)
    #expect(table.frame(for: testIdentity("Root", "Second")) == nil)

    let diagnostics = table.geometryResolutionDiagnostics
    #expect(diagnostics.anchorResolutionMissCount == 2)
    #expect(diagnostics.firstAnchorResolutionMissIdentity == testIdentity("Root", "First"))
  }

  @Test("a named space re-claimed by a different identity counts as a duplicate")
  func duplicateNamedCoordinateSpaceDiagnostics() {
    let recorder = GeometryResolutionDiagnosticsRecorder()
    var table = PlacedFrameTable(diagnosticsRecorder: recorder)

    table.record(
      identity: testIdentity("Root", "A"), bounds: rect(0, 0, 1, 1),
      namedCoordinateSpaceName: "space"
    )
    // Same identity re-recording the space (a later frame) is NOT a duplicate.
    table.record(
      identity: testIdentity("Root", "A"), bounds: rect(1, 1, 1, 1),
      namedCoordinateSpaceName: "space"
    )
    #expect(table.geometryResolutionDiagnostics.duplicateNamedCoordinateSpaceCount == 0)

    table.record(
      identity: testIdentity("Root", "B"), bounds: rect(2, 2, 1, 1),
      namedCoordinateSpaceName: "space"
    )
    let diagnostics = table.geometryResolutionDiagnostics
    #expect(diagnostics.duplicateNamedCoordinateSpaceCount == 1)
    #expect(diagnostics.firstDuplicateNamedCoordinateSpaceName == "space")
  }

  @Test("diagnostics merge adds counts and keeps first-observed details")
  func diagnosticsMergeKeepsFirsts() {
    var first = GeometryResolutionDiagnostics(
      anchorResolutionMissCount: 1,
      firstAnchorResolutionMissIdentity: testIdentity("Root", "Kept"),
      missingNamedCoordinateSpaceCount: 2,
      firstMissingNamedCoordinateSpaceName: "kept-space"
    )
    first.merge(
      GeometryResolutionDiagnostics(
        anchorResolutionMissCount: 3,
        firstAnchorResolutionMissIdentity: testIdentity("Root", "Later"),
        missingNamedCoordinateSpaceCount: 4,
        firstMissingNamedCoordinateSpaceName: "later-space",
        duplicateNamedCoordinateSpaceCount: 5,
        firstDuplicateNamedCoordinateSpaceName: "dup-space"
      )
    )

    #expect(first.anchorResolutionMissCount == 4)
    #expect(first.firstAnchorResolutionMissIdentity == testIdentity("Root", "Kept"))
    #expect(first.missingNamedCoordinateSpaceCount == 6)
    #expect(first.firstMissingNamedCoordinateSpaceName == "kept-space")
    #expect(first.duplicateNamedCoordinateSpaceCount == 5)
    #expect(first.firstDuplicateNamedCoordinateSpaceName == "dup-space")
  }

  @Test("table equality is content-based; a recorder does not defeat it")
  func tableEqualityIgnoresRecorder() {
    var plain = PlacedFrameTable()
    var recorded = PlacedFrameTable(diagnosticsRecorder: .init())
    plain.record(
      identity: testIdentity("Root", "A"), bounds: rect(0, 0, 1, 1),
      namedCoordinateSpaceName: nil
    )
    recorded.record(
      identity: testIdentity("Root", "A"), bounds: rect(0, 0, 1, 1),
      namedCoordinateSpaceName: nil
    )
    #expect(plain == recorded)
  }
}

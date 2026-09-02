import SwiftTUICore
import Testing

@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A selective (dirty-frontier) frame serves the ancestors of the nodes it
/// re-evaluates from committed snapshots, and a served ancestor's snapshot is
/// rebuilt from its child ViewNodes' own committed values. Two things that
/// rebuild dropped until the next root frame (org task T173):
///
/// - the decorations a presentation overlay stack authors onto ITS copy of
///   the hosted base — the modal-overlay interaction gate and the absorbed
///   focus-scope boundary — so a click behind an open sheet reached the base
///   action, the focus tracker recorded no modal restoration, and an
///   action-bearing popover tip left the base focusable;
/// - the scoped runtime-registration publication's reset selected identity
///   prefixes by the frontier root's structural identity while the paired
///   restore walked the root's ViewNode subtree, so beneath an exact-`.id`
///   host (whose descendants key their registrations under the RESOLVED
///   identity) the restore republished still-live entries on top of
///   themselves.
///
/// Every scenario here runs on the run loop's selective default and compares
/// against what a root evaluation produces.
@MainActor
@Suite(.serialized)
struct SelectiveServedHostParityTests {
  @Test("a sheet gates the base on the frame that opens it")
  func sheetGatesTheBaseOnItsOwnSelectiveFrame() throws {
    let rootIdentity = testIdentity("ServedHostSheetRoot")
    let harness = try StressRuntimeHarness(
      rootIdentity: rootIdentity,
      size: .init(width: 60, height: 14),
      selectiveEvaluation: true
    ) {
      ServedHostSheetFixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Increment Root")
    #expect(frame.contains("Root count 1"), "the root write did not render:\n\(frame)")
    let rootButtonPoint = try #require(harness.point(forText: "Increment Root"))
    #expect(harness.focusModalRestorationStackCount == 0)

    frame = try harness.clickText("Open Sheet")
    #expect(frame.contains("Sheet body"), "the sheet did not open:\n\(frame)")
    #expect(
      baseFocusRegionPaths(harness, rootIdentity: rootIdentity).isEmpty,
      "base focus regions survived beneath the modal sheet: \(baseFocusRegionPaths(harness, rootIdentity: rootIdentity))"
    )
    #expect(
      baseInteractionRegionPaths(harness, rootIdentity: rootIdentity).isEmpty,
      "base pointer regions survived beneath the modal sheet: \(baseInteractionRegionPaths(harness, rootIdentity: rootIdentity))"
    )
    #expect(
      harness.focusModalRestorationStackCount == 1,
      "the focus tracker recorded no modal restoration for the open sheet"
    )

    frame = try harness.click(rootButtonPoint)
    #expect(frame.contains("Sheet body"))
    #expect(frame.contains("Root count 1"))
    #expect(
      !frame.contains("Root count 2"), "a click behind the sheet reached the base action:\n\(frame)"
    )

    frame = try harness.clickText("Close Sheet", chooseLast: true)
    #expect(!frame.contains("Sheet body"), "the sheet did not close:\n\(frame)")
    #expect(harness.focusModalRestorationStackCount == 0)
    #expect(!baseFocusRegionPaths(harness, rootIdentity: rootIdentity).isEmpty)

    frame = try harness.clickText("Increment Root")
    #expect(
      frame.contains("Root count 2"), "the base did not come back after the sheet closed:\n\(frame)"
    )
  }

  @Test("a served overlay stack keeps its base's absorbed focus scope across a selective frame")
  func servedOverlayStackKeepsParityWithRootEvaluation() throws {
    let rootIdentity = testIdentity("ServedHostToastRoot")
    func makeHarness(selective: Bool) throws -> StressRuntimeHarness<ServedHostToastFixture> {
      try StressRuntimeHarness(
        rootIdentity: rootIdentity,
        size: .init(width: 60, height: 12),
        selectiveEvaluation: selective
      ) {
        ServedHostToastFixture()
      }
    }
    let control = try makeHarness(selective: false)
    defer { control.shutdown() }
    let selective = try makeHarness(selective: true)
    defer { selective.shutdown() }

    for harness in [control, selective] {
      let shown = try harness.clickText("Show Toast")
      #expect(shown.contains("Toast body"), "the toast did not appear:\n\(shown)")
      // A frame beneath the served stack while the (non-modal) toast stays up.
      let incremented = try harness.clickText("Increment")
      #expect(incremented.contains("count 1"), "the base write did not render:\n\(incremented)")
      #expect(incremented.contains("Toast body"), "the toast vanished:\n\(incremented)")
    }

    #expect(
      focusRegionShapes(selective) == focusRegionShapes(control),
      """
      selective focus regions diverged from the root evaluation:
      selective: \(focusRegionShapes(selective))
      control:   \(focusRegionShapes(control))
      """
    )
    #expect(
      selective.runLoop.latestSemanticSnapshot.interactionRegions.map(\.identity.path)
        == control.runLoop.latestSemanticSnapshot.interactionRegions.map(\.identity.path)
    )
  }

  @Test("a default-focus candidate under a replaced .id owner is published once per frame")
  func defaultFocusCandidateUnderReplacedIDOwnerPublishesOnce() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ServedHostDefaultFocusRoot"),
      size: .init(width: 60, height: 10),
      selectiveEvaluation: true
    ) {
      ServedHostDefaultFocusFixture()
    }
    defer { harness.shutdown() }

    for generation in 1...4 {
      let frame = try harness.clickText("Rebuild Owner")
      #expect(frame.contains("generation \(generation)"), "the owner did not rebuild:\n\(frame)")
      let snapshot = harness.runLoop.localDefaultFocusRegistry.snapshot()
      #expect(
        snapshot.scopes.count == 1,
        "generation \(generation): \(snapshot.scopes.count) default-focus scopes published"
      )
      #expect(
        snapshot.candidates.count == 1,
        "generation \(generation): \(snapshot.candidates.count) default-focus candidates published"
      )
    }
  }
}

// MARK: - Support

@MainActor
private func baseFocusRegionPaths<V: View>(
  _ harness: StressRuntimeHarness<V>,
  rootIdentity: Identity
) -> [String] {
  harness.runLoop.focusTracker.focusRegions
    .map(\.identity.path)
    .filter { $0.hasPrefix(rootIdentity.path) }
}

@MainActor
private func baseInteractionRegionPaths<V: View>(
  _ harness: StressRuntimeHarness<V>,
  rootIdentity: Identity
) -> [String] {
  harness.runLoop.latestSemanticSnapshot.interactionRegions
    .map(\.identity.path)
    .filter { $0.hasPrefix(rootIdentity.path) }
}

private struct FocusRegionShape: Equatable, CustomStringConvertible {
  var identity: String
  var scopePath: [String]
  var modalFocusScopePath: [String]?

  var description: String {
    "\(identity) scope=\(scopePath) modal=\(modalFocusScopePath ?? [])"
  }
}

@MainActor
private func focusRegionShapes<V: View>(_ harness: StressRuntimeHarness<V>) -> [FocusRegionShape] {
  harness.runLoop.focusTracker.focusRegions.map { region in
    FocusRegionShape(
      identity: region.identity.path,
      scopePath: region.scopePath.map(\.path),
      modalFocusScopePath: region.modalFocusScopePath?.map(\.path)
    )
  }
}

private struct ServedHostSheetFixture: View {
  @State private var rootCount = 0
  @State private var sheetPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Root count \(rootCount)")
      Button("Increment Root") { rootCount += 1 }
      Button("Open Sheet") { sheetPresented = true }
    }
    .sheet("Served Host Sheet", isPresented: $sheetPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body")
        Button("Close Sheet") { sheetPresented = false }
      }
    }
    .frame(width: 60, height: 14, alignment: .topLeading)
  }
}

private struct ServedHostToastFixture: View {
  @State private var toastPresented = false

  var body: some View {
    // The panel is a focus-scope boundary at the overlay stack's base: the
    // stack absorbs it (`focusScopeIdentity`) and clears the base's own
    // boundary so the scope path does not repeat the panel.
    Panel(id: testIdentity("ServedHostToast", "panel")) {
      VStack(alignment: .leading, spacing: 0) {
        ServedHostToastCounter()
        Button("Show Toast") { toastPresented = true }
      }
      .toast("Toast body", isPresented: $toastPresented, duration: nil)
    }
  }
}

/// Owns the counter so its write invalidates only this node: the frame it
/// schedules serves the overlay stack above from its committed snapshot.
private struct ServedHostToastCounter: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("count \(count)")
      Button("Increment") { count += 1 }
    }
  }
}

private enum ServedHostFocusField: Hashable {
  case target
}

private struct ServedHostDefaultFocusFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Owner") { generation += 1 }
      Text("generation \(generation)")
      ServedHostDefaultFocusOwner(generation: generation)
        .id(testIdentity("ServedHostDefaultFocus", "owner", "\(generation)"))
    }
    .frame(width: 60, height: 10, alignment: .topLeading)
  }
}

private struct ServedHostDefaultFocusOwner: View {
  let generation: Int
  @Namespace private var namespace
  @FocusState private var focusedField: ServedHostFocusField?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Default focus target \(generation)")
        .id(testIdentity("ServedHostDefaultFocus", "target"))
        .focusable()
        .focused($focusedField, equals: .target)
        .prefersDefaultFocus(in: namespace)
    }
    .focusScope(namespace)
  }
}

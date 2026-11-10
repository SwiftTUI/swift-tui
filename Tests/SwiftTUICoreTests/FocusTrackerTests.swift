import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct FocusTrackerTests {
  @Test("initial automatic adoption reports the same change as explicit focus")
  func initialAdoptionReportsChange() {
    let tracker = FocusTracker()
    let region = FocusRegion(
      identity: testIdentity("InitialFocus"),
      rect: .init(origin: .zero, size: .init(width: 1, height: 1)))
    #expect(tracker.updateRegions([region]))
    #expect(tracker.currentFocusIdentity == region.identity)
    #expect(!tracker.updateRegions([region]))
  }

  @Test("initial focus tracker has no focused identity")
  func initialStateHasNoFocus() {
    let tracker = FocusTracker()
    #expect(tracker.currentFocusIdentity == nil)
  }

  @Test("focusNext with regions sets focus to first region")
  func focusNextSelectsFirstRegion() {
    let tracker = FocusTracker()
    let regions = [
      FocusRegion(
        identity: testIdentity("button1"),
        rect: CellRect(origin: .zero, size: CellSize(width: 10, height: 1)),
        focusInteractions: .automatic
      ),
      FocusRegion(
        identity: testIdentity("button2"),
        rect: CellRect(origin: CellPoint(x: 0, y: 1), size: CellSize(width: 10, height: 1)),
        focusInteractions: .automatic
      ),
    ]
    _ = tracker.updateRegions(regions)
    _ = tracker.focusNext()

    // Initial adoption chose button1; advancing selects button2.
    #expect(tracker.currentFocusIdentity == testIdentity("button2"))
  }

  @Test("focusNext cycles through regions")
  func focusNextCycles() {
    let tracker = FocusTracker()
    let regions = [
      FocusRegion(
        identity: testIdentity("a"),
        rect: CellRect(origin: .zero, size: CellSize(width: 10, height: 1)),
        focusInteractions: .automatic
      ),
      FocusRegion(
        identity: testIdentity("b"),
        rect: CellRect(origin: CellPoint(x: 0, y: 1), size: CellSize(width: 10, height: 1)),
        focusInteractions: .automatic
      ),
    ]
    _ = tracker.updateRegions(regions)
    _ = tracker.focusNext()
    _ = tracker.focusNext()

    // Two advances wrap back to the initially adopted region.
    #expect(tracker.currentFocusIdentity == testIdentity("a"))
  }

  @MainActor
  @Test("default focus registry resolves preferred candidates and reset fallbacks by namespace")
  func defaultFocusRegistryResolvesNamespaceRequests() {
    let registry = LocalDefaultFocusRegistry()
    let firstNamespace = MatchedGeometryNamespace(1)
    let secondNamespace = MatchedGeometryNamespace(2)
    let firstScope = testIdentity("Root", "FirstScope")
    let secondScope = testIdentity("Root", "SecondScope")
    let first = testIdentity("First")
    let second = testIdentity("Second")
    let fallback = testIdentity("Fallback")

    registry.registerScope(
      namespace: firstNamespace,
      identity: firstScope
    )
    registry.registerScope(
      namespace: secondNamespace,
      identity: secondScope
    )
    registry.registerCandidate(
      namespace: firstNamespace,
      identity: second
    )

    let focusRegions = [
      focusRegion(first, y: 0, scopePath: [firstScope]),
      focusRegion(second, y: 1, scopePath: [firstScope]),
      focusRegion(fallback, y: 2, scopePath: [secondScope]),
    ]

    #expect(
      registry.desiredFocusRequest(
        focusRegions: focusRegions,
        shouldApplyInitialDefault: true
      ) == .focus(second))

    registry.requestReset(in: secondNamespace)
    #expect(
      registry.desiredFocusRequest(
        focusRegions: focusRegions,
        shouldApplyInitialDefault: false
      ) == .focus(fallback))
  }

  @Test(
    "authored sections visit every member in both directions",
    arguments: [false, true])
  func sectionsTraverseEveryMember(singleSection: Bool) {
    let regions = sectionedRegions([
      ("A", singleSection ? "section" : nil),
      ("B", "section"),
      ("C", "section"),
      ("D", singleSection ? "section" : "second"),
      ("E", singleSection ? "section" : nil),
    ])
    let tracker = FocusTracker(focusRegions: regions)
    for (index, region) in regions.enumerated() {
      _ = tracker.setFocus(to: region.identity)
      #expect(tracker.focusNext() == regions[(index + 1) % regions.count].identity)
      #expect(tracker.focusPrevious() == region.identity)
      #expect(
        tracker.focusPrevious() == regions[(index + regions.count - 1) % regions.count].identity)
      #expect(tracker.focusNext() == region.identity)
    }
    _ = tracker.clearFocus()
    #expect(tracker.focusNext() == regions.first?.identity)
    _ = tracker.clearFocus()
    #expect(tracker.focusPrevious() == regions.last?.identity)
  }

  @Test("counter section traversal reverses the actual preceding stop")
  func counterSectionTraversal() {
    let tracker = FocusTracker(
      focusRegions: sectionedRegions([
        ("minus", "math"), ("plus", "math"), ("step", "settings"), ("reset", "settings"),
      ]))
    #expect(tracker.currentFocusIdentity == testIdentity("minus"))
    #expect(tracker.focusNext() == testIdentity("plus"))
    #expect(tracker.focusPrevious() == testIdentity("minus"))
    #expect(tracker.focusNext() == testIdentity("plus"))
    #expect(tracker.focusNext() == testIdentity("step"))
    #expect(tracker.focusNext() == testIdentity("reset"))
  }

  @Test("empty and one-member sections have bounded traversal")
  func degenerateSections() {
    let tracker = FocusTracker()
    #expect(tracker.focusNext() == nil)
    #expect(tracker.focusPrevious() == nil)
    tracker.updateRegions(sectionedRegions([("only", "section")]))
    #expect(tracker.focusNext() == testIdentity("only"))
    #expect(tracker.focusPrevious() == testIdentity("only"))
  }

  @Test("composite rows escape their owner without skipping an enclosing section")
  func compositeOwnersAreIndependentOfSections() {
    var regions = sectionedRegions([
      ("before", "outer"), ("a0", "outer"), ("a1", "outer"),
      ("peer", "outer"), ("b0", "outer"), ("b1", "outer"), ("after", "outer"),
    ])
    for (indices, nodeID) in [(1...2, UInt64(1)), (4...5, UInt64(2))] {
      for index in indices {
        // The owner node, not an authored section or even owner identity alone,
        // distinguishes two live instances. Synthetic rows have no item target.
        regions[index].compositeTraversalOwner = .init(
          nodeID: .init(rawValue: nodeID), identity: testIdentity("List"))
      }
    }
    let tracker = FocusTracker(focusRegions: regions)
    #expect(tracker.focusNext() == testIdentity("a0"))
    #expect(tracker.focusNext() == testIdentity("peer"))
    #expect(tracker.focusNext() == testIdentity("b0"))
    #expect(tracker.focusNext() == testIdentity("after"))
    #expect(tracker.focusPrevious() == testIdentity("b1"))
    #expect(tracker.focusPrevious() == testIdentity("peer"))
    #expect(tracker.focusPrevious() == testIdentity("a1"))
    #expect(tracker.focusPrevious() == testIdentity("before"))

    let onlyRows = FocusTracker(focusRegions: Array(regions[1...2]))
    #expect(onlyRows.focusNext() == testIdentity("a0"))
    #expect(onlyRows.focusPrevious() == testIdentity("a0"))
    var changed = regions[1]
    changed.compositeTraversalOwner = regions[4].compositeTraversalOwner
    #expect(changed != regions[1], "semantic equality must include composite ownership")
  }

  // MARK: - Helpers

  private func focusRegion(
    _ identity: Identity,
    y: Int,
    scopePath: [Identity] = []
  ) -> FocusRegion {
    FocusRegion(
      identity: identity,
      rect: CellRect(
        origin: CellPoint(x: 0, y: y),
        size: CellSize(width: 10, height: 1)
      ),
      focusInteractions: .automatic,
      scopePath: scopePath
    )
  }

  private func sectionedRegions(
    _ entries: [(String, String?)]
  ) -> [FocusRegion] {
    entries.enumerated().map { index, entry in
      let (name, section) = entry
      return FocusRegion(
        identity: testIdentity(name),
        rect: CellRect(
          origin: CellPoint(x: 0, y: index),
          size: CellSize(width: 10, height: 1)
        ),
        focusInteractions: .automatic,
        scopePath: [],
        sectionIdentity: section.map { testIdentity($0) }
      )
    }
  }
}

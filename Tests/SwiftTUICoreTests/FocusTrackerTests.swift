import Testing

@testable import SwiftTUICore

@Suite
struct FocusTrackerTests {
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

    // FocusTracker focuses the last region first (bottom-up order)
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

    // After two focusNext calls from the last region, wraps to first
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

  // MARK: - Section-skipping Tab traversal

  @Test("focusNext skips past every region sharing the current section")
  func focusNextSkipsPastCurrentSection() {
    // A = standalone, B/C/D = calculator section, E = standalone.
    let regions = sectionedRegions([
      ("A", nil),
      ("B", "calc"),
      ("C", "calc"),
      ("D", "calc"),
      ("E", nil),
    ])
    let tracker = FocusTracker()
    _ = tracker.updateRegions(regions)

    _ = tracker.setFocus(to: testIdentity("C"))
    _ = tracker.focusNext()

    // From a calc-section region, Tab must land on the first region
    // outside the section — skipping D.
    #expect(tracker.currentFocusIdentity == testIdentity("E"))
  }

  @Test("focusPrevious skips past every region sharing the current section")
  func focusPreviousSkipsPastCurrentSection() {
    let regions = sectionedRegions([
      ("A", nil),
      ("B", "calc"),
      ("C", "calc"),
      ("D", "calc"),
      ("E", nil),
    ])
    let tracker = FocusTracker()
    _ = tracker.updateRegions(regions)

    _ = tracker.setFocus(to: testIdentity("C"))
    _ = tracker.focusPrevious()

    // Shift-Tab from inside the section skips B and lands on A.
    #expect(tracker.currentFocusIdentity == testIdentity("A"))
  }

  @Test("focusNext skipping the trailing section wraps to the beginning")
  func focusNextWrapsAroundTrailingSection() {
    let regions = sectionedRegions([
      ("A", nil),
      ("B", nil),
      ("C", "calc"),
      ("D", "calc"),
    ])
    let tracker = FocusTracker()
    _ = tracker.updateRegions(regions)

    _ = tracker.setFocus(to: testIdentity("D"))
    _ = tracker.focusNext()

    // Only "calc" regions follow D — wrap past them and land on A.
    #expect(tracker.currentFocusIdentity == testIdentity("A"))
  }

  @Test("focusPrevious skipping the leading section wraps to the end")
  func focusPreviousWrapsAroundLeadingSection() {
    let regions = sectionedRegions([
      ("A", "calc"),
      ("B", "calc"),
      ("C", nil),
      ("D", nil),
    ])
    let tracker = FocusTracker()
    _ = tracker.updateRegions(regions)

    _ = tracker.setFocus(to: testIdentity("A"))
    _ = tracker.focusPrevious()

    // Shift-Tab from the first calc button skips back past B and
    // wraps around to the last non-section region.
    #expect(tracker.currentFocusIdentity == testIdentity("D"))
  }

  @Test("focusNext from a region with no section advances one step")
  func focusNextFromUnsectionedRegionAdvancesOneStep() {
    let regions = sectionedRegions([
      ("A", nil),
      ("B", "calc"),
      ("C", "calc"),
    ])
    let tracker = FocusTracker()
    _ = tracker.updateRegions(regions)

    _ = tracker.setFocus(to: testIdentity("A"))
    _ = tracker.focusNext()

    // A has no section, so Tab advances into the section normally.
    #expect(tracker.currentFocusIdentity == testIdentity("B"))
  }

  @Test("focusNext with every region in one section falls back to linear cycling")
  func focusNextEveryRegionInOneSectionCycles() {
    let regions = sectionedRegions([
      ("A", "calc"),
      ("B", "calc"),
      ("C", "calc"),
    ])
    let tracker = FocusTracker()
    _ = tracker.updateRegions(regions)

    _ = tracker.setFocus(to: testIdentity("B"))
    _ = tracker.focusNext()

    // There's nothing outside the section — fall back to plain
    // linear step so Tab still cycles within it.
    #expect(tracker.currentFocusIdentity == testIdentity("C"))
  }

  @Test("focusNext skips a section even when not starting at its first member")
  func focusNextSkipsSectionMidway() {
    let regions = sectionedRegions([
      ("A", nil),
      ("B", "calc"),
      ("C", "calc"),
      ("D", "calc"),
      ("E", nil),
    ])
    let tracker = FocusTracker()
    _ = tracker.updateRegions(regions)

    _ = tracker.setFocus(to: testIdentity("B"))
    _ = tracker.focusNext()

    #expect(tracker.currentFocusIdentity == testIdentity("E"))
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

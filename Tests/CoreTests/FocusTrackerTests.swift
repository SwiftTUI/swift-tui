import Testing

@testable import Core

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
        rect: Rect(origin: .zero, size: Size(width: 10, height: 1)),
        focusInteractions: .automatic
      ),
      FocusRegion(
        identity: testIdentity("button2"),
        rect: Rect(origin: Point(x: 0, y: 1), size: Size(width: 10, height: 1)),
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
        rect: Rect(origin: .zero, size: Size(width: 10, height: 1)),
        focusInteractions: .automatic
      ),
      FocusRegion(
        identity: testIdentity("b"),
        rect: Rect(origin: Point(x: 0, y: 1), size: Size(width: 10, height: 1)),
        focusInteractions: .automatic
      ),
    ]
    _ = tracker.updateRegions(regions)
    _ = tracker.focusNext()
    _ = tracker.focusNext()

    // After two focusNext calls from the last region, wraps to first
    #expect(tracker.currentFocusIdentity == testIdentity("a"))
  }
}

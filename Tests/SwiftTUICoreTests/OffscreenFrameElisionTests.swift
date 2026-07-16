import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("OffscreenFrameElision")
struct OffscreenFrameElisionTests {
  // MARK: - Elides

  @Test("Elides a deadline-only frame whose redraw is fully off-screen")
  func elidesDeadlineOnlyFrameWithDisjointRedraw() {
    let result = OffscreenFrameElision.shouldElide(
      causes: [.deadline],
      hasExplicitAnimationTransactions: false,
      redrawIdentities: [testIdentity("1"), testIdentity("2")],
      drawnIdentities: [testIdentity("3"), testIdentity("4")]
    )
    #expect(result == true)
  }

  @Test("Elides the empty-redraw drain case")
  func elidesEmptyRedrawDrainCase() {
    let result = OffscreenFrameElision.shouldElide(
      causes: [.deadline],
      hasExplicitAnimationTransactions: false,
      redrawIdentities: [],
      drawnIdentities: [testIdentity("3")]
    )
    #expect(result == true)
  }

  @Test("Elides when nothing has ever been drawn (virgin surface)")
  func elidesWhenDrawnIdentitiesIsEmpty() {
    let result = OffscreenFrameElision.shouldElide(
      causes: [.deadline],
      hasExplicitAnimationTransactions: false,
      redrawIdentities: [testIdentity("1")],
      drawnIdentities: []
    )
    #expect(result == true)
  }

  // MARK: - Does not elide

  @Test("Does not elide when redraw overlaps drawn")
  func doesNotElideWhenRedrawOverlapsDrawn() {
    let result = OffscreenFrameElision.shouldElide(
      causes: [.deadline],
      hasExplicitAnimationTransactions: false,
      redrawIdentities: [testIdentity("1"), testIdentity("3")],
      drawnIdentities: [testIdentity("3"), testIdentity("4")]
    )
    #expect(result == false)
  }

  @Test(
    "Does not elide when any non-deadline cause is present",
    arguments: [WakeCause.input, .invalidation, .signal, .external]
  )
  func doesNotElideWhenNonDeadlineCausePresent(extra: WakeCause) {
    let result = OffscreenFrameElision.shouldElide(
      causes: [.deadline, extra],
      hasExplicitAnimationTransactions: false,
      redrawIdentities: [testIdentity("1")],
      drawnIdentities: [testIdentity("3")]
    )
    #expect(result == false)
  }

  @Test("Does not elide when an explicit animation transaction is present")
  func doesNotElideWhenExplicitAnimationTransaction() {
    let result = OffscreenFrameElision.shouldElide(
      causes: [.deadline],
      hasExplicitAnimationTransactions: true,
      redrawIdentities: [testIdentity("1")],
      drawnIdentities: [testIdentity("3")]
    )
    #expect(result == false)
  }

  @Test("Does not elide when animation is explicitly disabled")
  func doesNotElideWhenAnimationDisabled() {
    let result = OffscreenFrameElision.shouldElide(
      causes: [.deadline],
      hasExplicitAnimationTransactions: true,
      redrawIdentities: [testIdentity("1")],
      drawnIdentities: [testIdentity("3")]
    )
    #expect(result == false)
  }
}

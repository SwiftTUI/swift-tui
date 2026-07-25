import SwiftTUICore
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// `FrameHeadDraft.resolved` projects onto the tail input rather than
/// duplicating it.
///
/// The two were separate stored properties holding the same value: seeded from
/// one source at construction, then hand-synced. Animation injection wrote the
/// pair three times in one function and a worker snapshot rewrote both again,
/// with nothing checking they agreed — while consumers read whichever was
/// nearer, the tail coordinator passing `draft.resolved` and
/// `draft.frameTailInput` as adjacent arguments of one call.
///
/// Divergence would have been invisible: each value is individually
/// well-formed, so the tail would simply lay out one tree and diagnose another.
@MainActor
@Suite
struct FrameHeadDraftProjectionTests {
  private func makeDraft(_ renderer: DefaultRenderer) -> FrameHeadDraft {
    renderer.prepareFrameHeadForCancellationTesting(
      Text("draft"),
      context: .init(identity: testIdentity("FrameHeadProjection")),
      proposal: .init(width: 8, height: 1)
    )
  }

  @Test("a fresh draft agrees with its tail input")
  func freshDraftAgrees() {
    let renderer = DefaultRenderer()
    let draft = makeDraft(renderer)

    #expect(draft.resolved.identity == draft.frameTailInput.resolved.identity)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  @Test("writing the draft's resolved tree is visible through the tail input")
  func writingResolvedUpdatesTheTailInput() {
    let renderer = DefaultRenderer()
    var draft = makeDraft(renderer)
    let replacement = ResolvedNode(
      identity: testIdentity("FrameHeadProjection", "Replacement"),
      kind: .view("Text"),
      children: []
    )

    draft.resolved = replacement

    #expect(draft.frameTailInput.resolved.identity == replacement.identity)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  @Test("writing the tail input's resolved tree is visible through the draft")
  func writingTheTailInputUpdatesResolved() {
    // The other direction matters too: the tail coordinator rebuilds inputs,
    // and a projection that only worked one way would reintroduce the split.
    let renderer = DefaultRenderer()
    var draft = makeDraft(renderer)
    let replacement = ResolvedNode(
      identity: testIdentity("FrameHeadProjection", "TailWrite"),
      kind: .view("Text"),
      children: []
    )

    draft.frameTailInput.resolved = replacement

    #expect(draft.resolved.identity == replacement.identity)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }
}

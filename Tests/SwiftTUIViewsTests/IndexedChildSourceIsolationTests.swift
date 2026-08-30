import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

// An indexed child source's three FRAME-CONSTANT accessors must be readable
// from a non-main executor.
//
// The frame tail's layout worker legitimately holds the PREVIOUS frame's
// retained index, whose resolved nodes still reference live, main-actor
// sources, and `RetainedInvalidationSummary.init` reads `identityRoot` off
// every one of them to decide which indexed subtrees an invalidation touches.
// That read is race-free — the storage is `let`, fixed on the main actor
// during `init`, and the dispatch handoff to the worker is the happens-before
// edge — but between 2026-06-27 (`247e4dc3`, which routed the class's bare
// `assumeIsolated` bridges through the release-checked
// `withCheckedMainActorAccess`) and 2026-08-30 it went through a
// `MainActor.preconditionIsolated` and hard-trapped on the worker queue.
// `bun run perf:bench` died on SIGTRAP with no output for those two months.
//
// The mutable surface — anything touching `cache`, `elementsCache`, `content`,
// or the captured mint host — keeps its guard, and must: realizing an element
// off the main actor is the real hazard the guard exists for.
@MainActor
@Suite("Indexed child source isolation")
struct IndexedChildSourceIsolationTests {
  private struct Row: Hashable {
    var id: Int
    var title: String
  }

  private func makeSource(
    rows: [Row],
    context: ResolveContext
  ) -> ForEachIndexedChildSource<[Row], Int, Text> {
    ForEachIndexedChildSource(
      data: rows,
      id: \.id,
      content: { Text($0.title) },
      childContext: context
    )
  }

  @Test("the frame-constant accessors read off a non-main executor")
  func frameConstantAccessorsAreReadableOffMain() async {
    let identity = testIdentity("Root", "LazyVStack[0]")
    let context = ResolveContext(identity: identity)
    let rows = (0..<6).map { Row(id: $0, title: "row \($0)") }
    let source: any IndexedChildSource = makeSource(rows: rows, context: context)
    let onMain = source.measurementSignature

    // A detached task runs on the global cooperative executor, never the main
    // actor — the same isolation the frame-tail layout worker has. Under the
    // blanket guard this line did not fail the test, it killed the process.
    let offMain = await Task.detached {
      (
        count: source.count,
        identityRoot: source.identityRoot,
        signature: source.measurementSignature
      )
    }.value

    #expect(offMain.count == rows.count)
    #expect(offMain.identityRoot == identity)
    #expect(offMain.signature == onMain)
  }

  @Test("a hosted collection forwards the same three accessors off-main")
  func hostedCollectionForwardsOffMain() async {
    let identity = testIdentity("Root", "List[0]")
    let context = ResolveContext(identity: identity)
    let rows = (0..<3).map { Row(id: $0, title: "row \($0)") }
    let base = makeSource(rows: rows, context: context)
    let hosted: any IndexedChildSource = HostedCollectionIndexedChildSource(
      base: base,
      transform: { node, _ in node }
    )

    let offMain = await Task.detached {
      (count: hosted.count, identityRoot: hosted.identityRoot)
    }.value

    #expect(offMain.count == rows.count)
    #expect(offMain.identityRoot == identity)
  }
}

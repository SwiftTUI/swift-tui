import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("Tab selection state ownership")
struct TabSelectionStateTests {
  @Test("focus follows its tag across reorder and checkpoint restores overflow with it")
  func checkpointAndReorder() {
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = graph.beginEvaluation(identity: testIdentity("TabOwner"), invalidator: nil)
    let tags = [SelectionTag(value: "A"), SelectionTag(value: "B")]
    TabSelectionState.setStoredFocusedTabIndex(1, tags: tags, in: owner)
    TabSelectionState.setStoredTabOverflowMenuExpanded(true, in: owner)
    let checkpoint = graph.makeCheckpoint()

    #expect(TabSelectionState.storedFocusedTabIndex(in: owner, tags: Array(tags.reversed())) == 0)
    TabSelectionState.setStoredFocusedTabIndex(0, tags: tags, in: owner)
    TabSelectionState.resetOverflow(in: owner)
    #expect(!TabSelectionState.storedTabOverflowMenuExpanded(in: owner))

    _ = graph.restoreCheckpoint(checkpoint)
    #expect(TabSelectionState.storedFocusedTabIndex(in: owner, tags: tags) == 1)
    #expect(TabSelectionState.storedTabOverflowMenuExpanded(in: owner))
  }
}

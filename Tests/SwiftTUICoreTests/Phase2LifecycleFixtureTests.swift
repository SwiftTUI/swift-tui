import Testing

@testable import SwiftTUICore

@MainActor
@Suite
struct Phase2LifecycleFixtureTests {
  @Test("branch swaps emit disappearance before insertion")
  func branchSwapEmitsDisappearanceBeforeInsertion() {
    let fixture = LifecycleDiffFixture(
      previous: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Branch", "A"),
            appearHandlerIDs: ["appear-A"],
            disappearHandlerIDs: ["disappear-A"],
            task: .init(id: "task-A", priority: .medium)
          )
        ]
      ),
      next: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Branch", "B"),
            appearHandlerIDs: ["appear-B"],
            disappearHandlerIDs: ["disappear-B"],
            task: .init(id: "task-B", priority: .medium)
          )
        ]
      )
    )

    let plan = fixture.commitPlan()

    #expect(
      plan.lifecycle.map(\.identity) == [
        testIdentity("Branch", "A"),
        testIdentity("Branch", "A"),
        testIdentity("Branch", "B"),
        testIdentity("Branch", "B"),
      ])
    #expect(
      plan.lifecycle.map(\.operation) == [
        .taskCancel(.init(id: "task-A", priority: .medium)),
        .disappear(handlerIDs: ["disappear-A"]),
        .appear(handlerIDs: ["appear-B"]),
        .taskStart(.init(id: "task-B", priority: .medium)),
      ])
    #expect(plan.lifecycle.map { $0.viewNodeID != nil } == [true, false, false, true])
  }

  @Test("nested child lifecycle metadata is diffed independently of stable parents")
  func nestedChildLifecycleMetadataIsDiffedIndependentlyOfStableParents() {
    let fixture = LifecycleDiffFixture(
      previous: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Container"),
            children: []
          )
        ]
      ),
      next: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Container"),
            children: [
              lifecycleNode(
                testIdentity("Container", "Leaf"),
                appearHandlerIDs: ["appear-leaf"],
                disappearHandlerIDs: ["disappear-leaf"],
                task: .init(id: "task-leaf", priority: .high)
              )
            ]
          )
        ]
      )
    )

    let plan = fixture.commitPlan()

    #expect(
      plan.lifecycle.map(\.identity) == [
        testIdentity("Container", "Leaf"),
        testIdentity("Container", "Leaf"),
      ])
    #expect(
      plan.lifecycle.map(\.operation) == [
        .appear(handlerIDs: ["appear-leaf"]),
        .taskStart(.init(id: "task-leaf", priority: .high)),
      ])
    #expect(plan.lifecycle.map { $0.viewNodeID != nil } == [false, true])
  }
}

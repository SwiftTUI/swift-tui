import Testing

@testable import Core

@Suite
struct Phase2LifecycleFixtureTests {
  @Test("branch swaps emit disappearance before insertion")
  func branchSwapEmitsDisappearanceBeforeInsertion() {
    let fixture = LifecycleDiffFixture(
      previous: parallelLifecycleTree(
        children: [
          parallelLifecycleNode(
            testIdentity("Branch", "A"),
            appearHandlerIDs: ["appear-A"],
            disappearHandlerIDs: ["disappear-A"],
            task: .init(id: "task-A", priority: .medium)
          )
        ]
      ),
      next: parallelLifecycleTree(
        children: [
          parallelLifecycleNode(
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
      plan.lifecycle == [
        .init(
          identity: testIdentity("Branch", "A"),
          operation: .taskCancel(.init(id: "task-A", priority: .medium))
        ),
        .init(
          identity: testIdentity("Branch", "A"),
          operation: .disappear(handlerIDs: ["disappear-A"])
        ),
        .init(
          identity: testIdentity("Branch", "B"),
          operation: .appear(handlerIDs: ["appear-B"])
        ),
        .init(
          identity: testIdentity("Branch", "B"),
          operation: .taskStart(.init(id: "task-B", priority: .medium))
        ),
      ])
  }

  @Test("nested child lifecycle metadata is diffed independently of stable parents")
  func nestedChildLifecycleMetadataIsDiffedIndependentlyOfStableParents() {
    let fixture = LifecycleDiffFixture(
      previous: parallelLifecycleTree(
        children: [
          parallelLifecycleNode(
            testIdentity("Container"),
            children: []
          )
        ]
      ),
      next: parallelLifecycleTree(
        children: [
          parallelLifecycleNode(
            testIdentity("Container"),
            children: [
              parallelLifecycleNode(
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
      plan.lifecycle == [
        .init(
          identity: testIdentity("Container", "Leaf"),
          operation: .appear(handlerIDs: ["appear-leaf"])
        ),
        .init(
          identity: testIdentity("Container", "Leaf"),
          operation: .taskStart(.init(id: "task-leaf", priority: .high))
        ),
      ])
  }
}

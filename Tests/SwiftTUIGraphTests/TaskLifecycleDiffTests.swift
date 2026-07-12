import Testing

@testable import SwiftTUIGraph

@Suite("TaskLifecycleDiff policy")
struct TaskLifecycleDiffTests {
  private func task(_ id: String, priority: TaskPriority = .medium) -> TaskDescriptor {
    TaskDescriptor(id: id, priority: priority)
  }

  @Test("stable identity diffs by set difference in array order")
  func stableIdentityDiffsBySetDifference() {
    let diff = TaskLifecycleDiff.between(
      previous: [task("a"), task("b"), task("c")],
      current: [task("b"), task("d"), task("e")],
      identityChanged: false
    )
    #expect(diff.cancels == [task("a"), task("c")])
    #expect(diff.starts == [task("d"), task("e")])
    #expect(!diff.cancelsKeyToCurrentIdentity)
  }

  @Test("unchanged tasks emit nothing")
  func unchangedTasksEmitNothing() {
    let tasks = [task("a"), task("b")]
    let diff = TaskLifecycleDiff.between(
      previous: tasks,
      current: tasks,
      identityChanged: false
    )
    #expect(diff.cancels.isEmpty)
    #expect(diff.starts.isEmpty)
    #expect(!diff.cancelsKeyToCurrentIdentity)
  }

  @Test("identity churn with persisting tasks suppresses cancel and restart")
  func identityChurnWithPersistingTasksSuppressesBoth() {
    let diff = TaskLifecycleDiff.between(
      previous: [task("a"), task("b")],
      current: [task("c")],
      identityChanged: true
    )
    #expect(diff.cancels.isEmpty)
    #expect(diff.starts.isEmpty)
    #expect(!diff.cancelsKeyToCurrentIdentity)
  }

  @Test("identity churn with no previous tasks still starts a genuine first appearance")
  func identityChurnWithEmptyPreviousStartsFreshTask() {
    // A node that held no tasks while its resolved identity churned (the
    // reduce-motion → restore transition of PhaseAnimator: the loop task is
    // absent while reduced, then reappears under a churned conditional-branch
    // identity when motion returns) must still start a task that appears this
    // frame. Nothing persisted across the relabel, so the restart suppression
    // that protects long-lived relabeled tasks does not apply.
    let diff = TaskLifecycleDiff.between(
      previous: [],
      current: [task("a")],
      identityChanged: true
    )
    #expect(diff.cancels.isEmpty)
    #expect(diff.starts == [task("a")])
    #expect(!diff.cancelsKeyToCurrentIdentity)
  }

  @Test("identity churn removing every task cancels keyed to the current identity")
  func identityChurnRemovingEveryTaskCancelsToCurrentIdentity() {
    let diff = TaskLifecycleDiff.between(
      previous: [task("a"), task("b")],
      current: [],
      identityChanged: true
    )
    #expect(diff.cancels == [task("a"), task("b")])
    #expect(diff.starts.isEmpty)
    #expect(diff.cancelsKeyToCurrentIdentity)
  }

  @Test("a descriptor differing only by priority cancels and restarts")
  func priorityChangeCancelsAndRestarts() {
    let diff = TaskLifecycleDiff.between(
      previous: [task("a", priority: .medium)],
      current: [task("a", priority: .high)],
      identityChanged: false
    )
    #expect(diff.cancels == [task("a", priority: .medium)])
    #expect(diff.starts == [task("a", priority: .high)])
  }

  @Test("empty previous starts everything; empty current cancels everything")
  func emptyEdges() {
    let firstMount = TaskLifecycleDiff.between(
      previous: [],
      current: [task("a")],
      identityChanged: false
    )
    #expect(firstMount.cancels.isEmpty)
    #expect(firstMount.starts == [task("a")])

    let removal = TaskLifecycleDiff.between(
      previous: [task("a")],
      current: [],
      identityChanged: false
    )
    #expect(removal.cancels == [task("a")])
    #expect(removal.starts.isEmpty)
    #expect(!removal.cancelsKeyToCurrentIdentity)
  }
}

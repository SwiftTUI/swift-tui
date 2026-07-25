import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Agreement between the two declared-child traversals a lazy container pairs.
///
/// `DeclaredChildrenView` exposes four parallel traversals, and its
/// documentation asks implementations to "use the same `indexedChild` identity
/// scheme and increment `nextIndex` the same way" as each other. That was prose
/// across five conformers, enforced by nothing — while `TabView` pairs two of
/// those traversals *by position*, so a conformer that descends differently in
/// one of them hands a tab some other tab's body.
///
/// The failure is invisible downstream: both halves are individually
/// well-formed, and the old pairing absorbed a short payload list into a `nil`.
/// These tests walk every structural shape a `@ViewBuilder` can produce and
/// require the traversals to agree, and to agree on the right number.
@MainActor
struct DeclaredChildTraversalParityTests {
  @Test("a bare leaf child")
  func leafAgrees() {
    expectTraversalAgreement(Text("a"), shape: "leaf", expectedChildren: 1)
  }

  @Test("an empty view is a child, not an absence")
  func emptyViewAgrees() {
    // EmptyView is not a DeclaredChildrenView, so both traversals treat it as
    // one opaque leaf. Omission happens later, at consumption.
    expectTraversalAgreement(EmptyView(), shape: "empty", expectedChildren: 1)
  }

  @Test("builder tuples of several children")
  func tuplesAgree() {
    expectTraversalAgreement(twoChildren(), shape: "tuple2", expectedChildren: 2)
    expectTraversalAgreement(threeChildren(), shape: "tuple3", expectedChildren: 3)
  }

  @Test("a group flattens into its enclosing sequence")
  func groupAgrees() {
    expectTraversalAgreement(groupedChildren(), shape: "group", expectedChildren: 2)
  }

  @Test("nested groups flatten at every level")
  func nestedGroupAgrees() {
    expectTraversalAgreement(nestedGroupChildren(), shape: "nestedGroup", expectedChildren: 3)
  }

  @Test("a ForEach contributes one child per element")
  func forEachAgrees() {
    expectTraversalAgreement(forEachChildren(count: 3), shape: "forEach3", expectedChildren: 3)
  }

  @Test("an empty ForEach contributes nothing")
  func emptyForEachAgrees() {
    expectTraversalAgreement(forEachChildren(count: 0), shape: "forEach0", expectedChildren: 0)
  }

  @Test("conditional branches")
  func conditionalsAgree() {
    expectTraversalAgreement(conditional(taken: true), shape: "ifTrue", expectedChildren: 1)
    expectTraversalAgreement(conditionalElse(taken: true), shape: "ifElseTrue", expectedChildren: 1)
    expectTraversalAgreement(
      conditionalElse(taken: false), shape: "ifElseFalse", expectedChildren: 1)
  }

  @Test("an untaken if with no else collapses in both traversals")
  func collapsedImplicitEmptyBranchAgrees() {
    // The `collapsesImplicitEmptyFalseBranch` leg: the slot index is consumed
    // but no child is produced. Both traversals must return early together —
    // this is the one shape where a conformer deliberately produces fewer
    // children than slots, so it is the likeliest place to drift.
    expectTraversalAgreement(conditional(taken: false), shape: "ifFalse", expectedChildren: 0)
  }

  @Test("a mixed nest of every structural shape")
  func mixedNestAgrees() {
    expectTraversalAgreement(mixedNest(), shape: "mixed", expectedChildren: 6)
  }
}

// MARK: - Divergence reporting

@MainActor
struct DeclaredChildDivergenceReportingTests {
  @Test("a divergence names both counts and what it costs")
  func divergenceDescribesTheMispairing() {
    let divergence = DeclaredChildTraversalDivergence(
      enumeratedCount: 3,
      payloadCount: 2
    )
    let issue = divergence.runtimeIssue(
      container: "TabView",
      identity: testIdentity("DeclaredChildParity", "Reporting")
    )

    #expect(issue.severity == .warning)
    #expect(issue.code == "structure.declaredChildTraversalMismatch")
    #expect(issue.message.contains("3"))
    #expect(issue.message.contains("2"))
  }

  @Test("agreeing traversals report nothing")
  func agreementProducesNoDivergence() {
    let context = ResolveContext(
      identity: testIdentity("DeclaredChildParity", "NoDivergence")
    )
    let paired = pairedLazyDeclaredChildren(
      from: threeChildren(),
      in: context,
      kindName: "Tab",
      debugName: "Body"
    )
    #expect(paired.divergence == nil)
    #expect(paired.children.allSatisfy { $0.payload != nil })
  }
}

// MARK: - Shapes

@MainActor @ViewBuilder
private func twoChildren() -> some View {
  Text("a")
  Text("b")
}

@MainActor @ViewBuilder
private func threeChildren() -> some View {
  Text("a")
  Text("b")
  Text("c")
}

@MainActor @ViewBuilder
private func groupedChildren() -> some View {
  Group {
    Text("a")
    Text("b")
  }
}

@MainActor @ViewBuilder
private func nestedGroupChildren() -> some View {
  Group {
    Group {
      Text("a")
      Text("b")
    }
    Text("c")
  }
}

@MainActor @ViewBuilder
private func forEachChildren(count: Int) -> some View {
  ForEach(0..<count, id: \.self) { index in
    Text("row-\(index)")
  }
}

@MainActor @ViewBuilder
private func conditional(taken: Bool) -> some View {
  if taken {
    Text("a")
  }
}

@MainActor @ViewBuilder
private func conditionalElse(taken: Bool) -> some View {
  if taken {
    Text("a")
  } else {
    Text("b")
  }
}

@MainActor @ViewBuilder
private func mixedNest() -> some View {
  Text("leading")
  ForEach(0..<2, id: \.self) { index in
    Text("row-\(index)")
  }
  Group {
    Text("grouped")
    if true {
      Text("conditional")
    }
  }
  if false {
    Text("never")
  }
  Text("trailing")
}

// MARK: - Assertion

@MainActor
private func expectTraversalAgreement<V: View>(
  _ view: V,
  shape: String,
  expectedChildren: Int
) {
  let context = ResolveContext(
    identity: testIdentity("DeclaredChildParity", shape)
  )
  let paired = pairedLazyDeclaredChildren(
    from: view,
    in: context,
    kindName: "Tab",
    debugName: "Body"
  )

  #expect(
    paired.divergence == nil,
    """
    \(shape): the enumeration and payload traversals disagreed \
    (\(String(describing: paired.divergence))). A container pairing them by \
    position would give a child the wrong content.
    """
  )
  #expect(
    paired.children.count == expectedChildren,
    "\(shape): expected \(expectedChildren) declared children, saw \(paired.children.count)"
  )
  #expect(
    paired.children.allSatisfy { $0.payload != nil },
    "\(shape): a declared child came back without a payload"
  )
}

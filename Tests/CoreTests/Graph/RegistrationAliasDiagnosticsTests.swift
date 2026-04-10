import Testing

@testable import Core

@Suite
struct RegistrationAliasDiagnosticsTests {
  @Test("empty diagnostics have zero count and no divergences")
  func emptyState() {
    let diagnostics = RegistrationAliasDiagnostics()

    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
    #expect(diagnostics.topDivergences().isEmpty)
  }

  @Test("recording a trivial alias is a no-op")
  func trivialIsNoOp() {
    var diagnostics = RegistrationAliasDiagnostics()
    let identity = testIdentity("Root", "Child")

    diagnostics.record(
      from: identity,
      to: identity,
      resolvedKind: .view("Text")
    )

    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  @Test("a single non-trivial alias is recorded once")
  func singleRecord() {
    var diagnostics = RegistrationAliasDiagnostics()

    diagnostics.record(
      from: testIdentity("Root", "Group[0]"),
      to: testIdentity("Root", "Group[0]", "ID[42]"),
      resolvedKind: .view("Text")
    )

    #expect(diagnostics.nonTrivialCallCount == 1)
    #expect(diagnostics.uniqueDivergenceCount == 1)

    let top = diagnostics.topDivergences()
    #expect(top.count == 1)
    #expect(top[0].key.fromIdentity == testIdentity("Root", "Group[0]"))
    #expect(top[0].key.toIdentity == testIdentity("Root", "Group[0]", "ID[42]"))
    #expect(top[0].key.kindDescription == "view(Text)")
    #expect(top[0].count == 1)
  }

  @Test("identical tuples are merged and counted")
  func duplicateTuplesMerge() {
    var diagnostics = RegistrationAliasDiagnostics()
    let from = testIdentity("Root", "A")
    let to = testIdentity("Root", "A", "ID[1]")

    for _ in 0..<5 {
      diagnostics.record(
        from: from,
        to: to,
        resolvedKind: .view("Row")
      )
    }

    #expect(diagnostics.nonTrivialCallCount == 5)
    #expect(diagnostics.uniqueDivergenceCount == 1)

    let top = diagnostics.topDivergences()
    #expect(top.count == 1)
    #expect(top[0].count == 5)
  }

  @Test("different kinds with same identities are tracked separately")
  func kindIsPartOfTheKey() {
    var diagnostics = RegistrationAliasDiagnostics()
    let from = testIdentity("Root", "A")
    let to = testIdentity("Root", "A", "ID[1]")

    diagnostics.record(from: from, to: to, resolvedKind: .view("Text"))
    diagnostics.record(from: from, to: to, resolvedKind: .view("Button"))

    #expect(diagnostics.nonTrivialCallCount == 2)
    #expect(diagnostics.uniqueDivergenceCount == 2)
  }

  @Test("topDivergences sorts by count descending")
  func topDivergencesSortedByCount() {
    var diagnostics = RegistrationAliasDiagnostics()

    // High-frequency divergence observed once
    diagnostics.record(
      from: testIdentity("Root", "A"),
      to: testIdentity("Root", "A", "ID[1]"),
      resolvedKind: .view("Rare")
    )
    // Low-frequency divergence observed three times
    for _ in 0..<3 {
      diagnostics.record(
        from: testIdentity("Root", "B"),
        to: testIdentity("Root", "B", "ID[2]"),
        resolvedKind: .view("Common")
      )
    }

    let top = diagnostics.topDivergences()
    #expect(top.count == 2)
    #expect(top[0].key.kindDescription == "view(Common)")
    #expect(top[0].count == 3)
    #expect(top[1].key.kindDescription == "view(Rare)")
    #expect(top[1].count == 1)
  }

  @Test("topDivergences honours the limit argument")
  func topDivergencesLimit() {
    var diagnostics = RegistrationAliasDiagnostics()

    for index in 0..<10 {
      diagnostics.record(
        from: testIdentity("Root", "\(index)"),
        to: testIdentity("Root", "\(index)", "ID[0]"),
        resolvedKind: .view("View\(index)")
      )
    }

    #expect(diagnostics.topDivergences(limit: 3).count == 3)
    #expect(diagnostics.topDivergences(limit: 100).count == 10)
  }

  @Test("divergence cap drops new tuples but keeps counting calls")
  func divergenceCapDropsNewUniques() {
    var diagnostics = RegistrationAliasDiagnostics(divergenceCap: 4)

    for index in 0..<6 {
      diagnostics.record(
        from: testIdentity("Root", "A\(index)"),
        to: testIdentity("Root", "A\(index)", "ID[0]"),
        resolvedKind: .view("Text")
      )
    }

    // All six were non-trivial calls, but only the first four unique
    // keys are retained.
    #expect(diagnostics.nonTrivialCallCount == 6)
    #expect(diagnostics.uniqueDivergenceCount == 4)
  }

  @Test("divergence cap still merges duplicates after filling")
  func divergenceCapDoesNotBlockDuplicates() {
    var diagnostics = RegistrationAliasDiagnostics(divergenceCap: 2)

    // Fill the cap.
    diagnostics.record(
      from: testIdentity("Root", "A"),
      to: testIdentity("Root", "A", "ID[0]"),
      resolvedKind: .view("Text")
    )
    diagnostics.record(
      from: testIdentity("Root", "B"),
      to: testIdentity("Root", "B", "ID[0]"),
      resolvedKind: .view("Text")
    )
    #expect(diagnostics.uniqueDivergenceCount == 2)

    // Re-record the first tuple — should bump its count even though
    // the cap is full.
    diagnostics.record(
      from: testIdentity("Root", "A"),
      to: testIdentity("Root", "A", "ID[0]"),
      resolvedKind: .view("Text")
    )

    #expect(diagnostics.nonTrivialCallCount == 3)
    #expect(diagnostics.uniqueDivergenceCount == 2)
    let top = diagnostics.topDivergences()
    #expect(top[0].key.fromIdentity == testIdentity("Root", "A"))
    #expect(top[0].count == 2)
  }

  @Test("reset clears state")
  func resetClearsState() {
    var diagnostics = RegistrationAliasDiagnostics()

    diagnostics.record(
      from: testIdentity("Root", "A"),
      to: testIdentity("Root", "A", "ID[0]"),
      resolvedKind: .view("Text")
    )
    #expect(diagnostics.nonTrivialCallCount == 1)

    diagnostics.reset()

    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  @Test("divergence key description is human readable")
  func divergenceKeyDescription() {
    let key = RegistrationAliasDiagnostics.DivergenceKey(
      fromIdentity: testIdentity("Root", "Group[0]"),
      toIdentity: testIdentity("Root", "Group[0]", "ID[hello]"),
      kindDescription: "view(Text)"
    )

    #expect(key.description.contains("Root/Group[0]"))
    #expect(key.description.contains("Root/Group[0]/ID[hello]"))
    #expect(key.description.contains("view(Text)"))
  }
}

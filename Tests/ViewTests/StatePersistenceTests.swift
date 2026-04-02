import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite(.serialized)
struct StatePersistenceTests {
  @Test("multiple state slots stay independent across rerenders")
  func multipleStateSlotsStayIndependent() throws {
    let renderer = DefaultRenderer()
    let firstRegistry = LocalActionRegistry()
    let secondRegistry = LocalActionRegistry()

    let initial = renderer.render(
      MultiStateCounterView(),
      context: ResolveContext(
        identity: testIdentity("StatePersistence"),
        localActionRegistry: firstRegistry,
        applyEnvironmentValues: true
      )
    )

    let actionIdentity = try #require(
      initial.semanticSnapshot.focusRegions.first?.identity
    )
    #expect(firstRegistry.dispatch(identity: actionIdentity))

    let updated = renderer.render(
      MultiStateCounterView(),
      context: ResolveContext(
        identity: testIdentity("StatePersistence"),
        localActionRegistry: secondRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(updated.rasterSurface.lines.contains("First 2"))
    #expect(updated.rasterSurface.lines.contains("Second 10"))
  }

  @Test("reordering state access remaps persisted values by ordinal")
  func accessReorderingRemapsValuesByOrdinal() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      MultiStateCounterView(),
      context: ResolveContext(
        identity: testIdentity("OrdinalSwap"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let actionIdentity = try #require(
      initial.semanticSnapshot.focusRegions.first?.identity
    )
    #expect(actionRegistry.dispatch(identity: actionIdentity))

    let swapped = renderer.render(
      AccessOrderSwappedMultiStateCounterView(),
      context: ResolveContext(
        identity: testIdentity("OrdinalSwap"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(swapped.rasterSurface.lines.contains("First 10"))
    #expect(swapped.rasterSurface.lines.contains("Second 2"))
  }
}

private struct MultiStateCounterView: View {
  @State private var first = 1
  @State private var second = 10

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("First \(first)")
      Text("Second \(second)")
      Button(
        "Increment First",
        action: {
          first += 1
        }
      )
    }
  }
}

private struct AccessOrderSwappedMultiStateCounterView: View {
  @State private var first = 1
  @State private var second = 10

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Second \(second)")
      Text("First \(first)")
    }
  }
}

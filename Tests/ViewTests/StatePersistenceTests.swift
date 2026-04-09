import Synchronization
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

  @Test("onChange on a stateful view reserves modifier storage after body state slots")
  func onChangeOnStatefulViewReservesModifierStorageAfterBodyStateSlots() async {
    let box = ChangeEventBox()
    let lifecycleRegistry = LocalLifecycleRegistry()

    let artifacts = DefaultRenderer().render(
      StatefulOnChangeFixture(box: box),
      context: ResolveContext(
        identity: testIdentity("StatefulOnChangeInitial"),
        localLifecycleRegistry: lifecycleRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      artifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("StatefulOnChangeInitial"),
          operation: .change(handlerIDs: ["StatefulOnChangeInitial#change[0]"])
        )
      ]
    )

    await MainActor.run {
      lifecycleRegistry.changeHandler(for: "StatefulOnChangeInitial#change[0]")?()
    }

    #expect(box.events == ["1->1"])
  }

  @Test("onChange on a stateful view preserves previous values across rerenders")
  func onChangeOnStatefulViewPreservesPreviousValuesAcrossRerenders() async throws {
    let renderer = DefaultRenderer()
    let box = ChangeEventBox()
    let lifecycleRegistry = LocalLifecycleRegistry()
    let initialActionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      StatefulOnChangeFixture(box: box),
      context: ResolveContext(
        identity: testIdentity("StatefulOnChangeRerender"),
        localActionRegistry: initialActionRegistry,
        localLifecycleRegistry: lifecycleRegistry,
        applyEnvironmentValues: true
      )
    )

    await MainActor.run {
      lifecycleRegistry.changeHandler(for: "StatefulOnChangeRerender#change[0]")?()
    }

    #expect(box.events == ["1->1"])

    let actionIdentity = try #require(
      initial.semanticSnapshot.focusRegions.first?.identity
    )
    #expect(initialActionRegistry.dispatch(identity: actionIdentity))

    let updated = renderer.render(
      StatefulOnChangeFixture(box: box),
      context: ResolveContext(
        identity: testIdentity("StatefulOnChangeRerender"),
        localActionRegistry: LocalActionRegistry(),
        localLifecycleRegistry: lifecycleRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      updated.commitPlan.lifecycle == [
        LifecycleCommitEntry(
          identity: testIdentity("StatefulOnChangeRerender"),
          operation: .change(handlerIDs: ["StatefulOnChangeRerender#change[0]"])
        )
      ]
    )

    await MainActor.run {
      lifecycleRegistry.changeHandler(for: "StatefulOnChangeRerender#change[0]")?()
    }

    #expect(box.events == ["1->1", "1->3"])
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

private final class ChangeEventBox: Sendable {
  private let storage = Mutex<[String]>([])

  var events: [String] {
    storage.withLock { $0 }
  }

  func record(oldValue: Int, newValue: Int) {
    storage.withLock { events in
      events.append("\(oldValue)->\(newValue)")
    }
  }
}

private struct StatefulOnChangeFixture: View {
  let box: ChangeEventBox

  @State private var color: Color = .red
  @State private var count: Int = 1
  @State private var step: Int = 2

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Color")
        .foregroundStyle(color)
      Text("Count \(count)")
      Text("Step \(step)")
      Button("Increment") {
        count += step
      }
    }
    .onChange(of: count, initial: true) { oldValue, newValue in
      box.record(oldValue: oldValue, newValue: newValue)
    }
  }
}

import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

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

  @Test("reordering body access preserves persisted values by declaration order")
  func accessReorderingPreservesValuesByDeclarationOrder() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      ReorderableMultiStateCounterView(showSecondFirst: false),
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
      ReorderableMultiStateCounterView(showSecondFirst: true),
      context: ResolveContext(
        identity: testIdentity("OrdinalSwap"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(swapped.rasterSurface.lines.contains("First 2"))
    #expect(swapped.rasterSurface.lines.contains("Second 10"))
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

    #expect(artifacts.commitPlan.lifecycle.map(\.identity) == [
      testIdentity("StatefulOnChangeInitial")
    ])
    #expect(artifacts.commitPlan.lifecycle.map(\.operation) == [
      .change(handlerIDs: ["StatefulOnChangeInitial#change[0]"])
    ])
    #expect(artifacts.commitPlan.lifecycle.map { $0.viewNodeID != nil } == [true])

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

    #expect(updated.commitPlan.lifecycle.map(\.identity) == [
      testIdentity("StatefulOnChangeRerender")
    ])
    #expect(updated.commitPlan.lifecycle.map(\.operation) == [
      .change(handlerIDs: ["StatefulOnChangeRerender#change[0]"])
    ])
    #expect(updated.commitPlan.lifecycle.map { $0.viewNodeID != nil } == [true])

    await MainActor.run {
      lifecycleRegistry.changeHandler(for: "StatefulOnChangeRerender#change[0]")?()
    }

    #expect(box.events == ["1->1", "1->3"])
  }

  @Test("action-only state access preserves declaration-order slots across rerenders")
  func actionOnlyStateAccessPreservesDeclarationOrderSlotsAcrossRerenders() {
    let renderer = DefaultRenderer()
    let firstRegistry = LocalActionRegistry()

    _ = renderer.render(
      DeferredStateActionOrderFixture(),
      context: ResolveContext(
        identity: testIdentity("DeferredActionState"),
        localActionRegistry: firstRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(firstRegistry.dispatch(identity: testIdentity("DigitAction")))

    let afterDigitRegistry = LocalActionRegistry()
    let afterDigit = renderer.render(
      DeferredStateActionOrderFixture(),
      context: ResolveContext(
        identity: testIdentity("DeferredActionState"),
        localActionRegistry: afterDigitRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(afterDigit.rasterSurface.lines.contains("9"))
    #expect(afterDigitRegistry.dispatch(identity: testIdentity("CaptureAction")))

    let afterCapture = renderer.render(
      DeferredStateActionOrderFixture(),
      context: ResolveContext(
        identity: testIdentity("DeferredActionState"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(afterCapture.rasterSurface.lines.contains("captured"))
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

private struct ReorderableMultiStateCounterView: View {
  let showSecondFirst: Bool

  @State private var first = 1
  @State private var second = 10

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      if showSecondFirst {
        Text("Second \(second)")
        Text("First \(first)")
      } else {
        Text("First \(first)")
        Text("Second \(second)")
      }
      Button(
        "Increment First",
        action: {
          first += 1
        }
      )
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

private struct DeferredStateActionOrderFixture: View {
  @State private var text = "0"
  @State private var deferredNumber: Double? = nil
  @State private var clearOnNextDigit = false
  @State private var isError = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(text)
      Button("Digit") {
        if isError || clearOnNextDigit || text == "0" {
          text = "9"
          clearOnNextDigit = false
          isError = false
          return
        }
        text += "9"
      }
      .id(testIdentity("DigitAction"))

      Button("Capture") {
        if deferredNumber == nil {
          deferredNumber = Double(text)
        }
        text = deferredNumber == nil ? "missing" : "captured"
      }
      .id(testIdentity("CaptureAction"))
    }
  }
}

import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI toast lifecycle stress behavior", .serialized)
struct FrameworkStressToastLifecycleTests {}

@MainActor
private func toastLifecycleEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> Int {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .filter { $0.kindName == "ToastPresentation" }
    .count
}

// MARK: - Attempt 001: active message refresh

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 001 active message follows source generations")
  func toastLifecycle001ActiveMessageFollowsSourceGenerations() throws {
    // Hypothesis: a stable toast item can retain the first declared Text payload while its source
    // keeps emitting fresh generations under the same portal entry identity.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle001"),
      size: .init(width: 58, height: 10)
    ) {
      ToastLifecycle001Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Advance Toast Message 001")
      #expect(frame.contains("toast message generation \(generation)"))
      #expect(!frame.contains("toast message generation \(generation - 1)"))
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle001Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Toast Message 001") { generation += 1 }
      Text("source generation \(generation)")
    }
    .toast(
      "toast message generation \(generation)",
      isPresented: $isPresented,
      duration: nil
    )
  }
}

// MARK: - Attempt 002: content cardinality replacement

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 002 active content replaces its child cardinality")
  func toastLifecycle002ActiveContentReplacesItsChildCardinality() throws {
    // Hypothesis: a retained ToastContent attachment can preserve the previous one-child or
    // two-child topology even after the source emits a freshly built payload group.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle002"),
      size: .init(width: 62, height: 12)
    ) {
      ToastLifecycle002Root()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Replace Toast Topology 002")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("compact toast generation \(generation)"))
        #expect(!frame.contains("detail toast generation \(generation)"))
      } else {
        #expect(frame.contains("primary toast generation \(generation)"))
        #expect(frame.contains("detail toast generation \(generation)"))
        #expect(!frame.contains("compact toast generation \(generation)"))
      }
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle002Root: View {
  @State private var generation = 0
  @State private var expanded = false
  @State private var isPresented = true

  var body: some View {
    Button("Replace Toast Topology 002") {
      generation += 1
      expanded.toggle()
    }
    .toast(isPresented: $isPresented, duration: nil) {
      if expanded {
        VStack(alignment: .leading, spacing: 0) {
          Text("primary toast generation \(generation)")
          Text("detail toast generation \(generation)")
        }
      } else {
        Text("compact toast generation \(generation)")
      }
    }
  }
}

// MARK: - Attempt 003: erased style family replacement

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 003 active toast adopts each replacement style family")
  func toastLifecycle003ActiveToastAdoptsEachReplacementStyleFamily() throws {
    // Hypothesis: AnyToastStyle can retain its first concrete box while the active item keeps the
    // same ID, leaving the toast icon and semantic chrome on the previous style family.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle003"),
      size: .init(width: 56, height: 10)
    ) {
      ToastLifecycle003Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Replace Toast Style 003")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("ℹ"))
        #expect(!frame.contains("✓"))
      } else {
        #expect(frame.contains("✓"))
        #expect(!frame.contains("ℹ"))
      }
      #expect(frame.contains("style family generation \(generation)"))
    }
  }
}

@MainActor
private struct ToastLifecycle003Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    Button("Replace Toast Style 003") { generation += 1 }
      .toast(
        "style family generation \(generation)",
        isPresented: $isPresented,
        style: generation.isMultiple(of: 2) ? .info : .success,
        duration: nil
      )
  }
}

// MARK: - Attempt 004: same-type style payload refresh

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 004 active toast refreshes same-type style payload")
  func toastLifecycle004ActiveToastRefreshesSameTypeStylePayload() throws {
    // Hypothesis: type-erased style storage can compare only its concrete type and leave an active
    // toast using the first same-type icon and geometry payload.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle004"),
      size: .init(width: 58, height: 10)
    ) {
      ToastLifecycle004Root()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Refresh Toast Chrome 004")
      let currentIcon = generation.isMultiple(of: 2) ? "E" : "O"
      let staleIcon = generation.isMultiple(of: 2) ? "O" : "E"
      #expect(frame.contains("\(currentIcon) chrome generation \(generation)"))
      #expect(!frame.contains("\(staleIcon) chrome generation \(generation)"))
    }
  }
}

private struct ToastLifecycle004Style: ToastStyle {
  let generation: Int

  var snapshotLabel: String { "ToastLifecycle004Style" }

  func resolvePresentation(for _: ToastStyleConfiguration) -> ToastStylePresentation {
    ToastStylePresentation(
      icon: generation.isMultiple(of: 2) ? "E" : "O",
      contentPadding: .init(all: 1),
      minWidth: 18,
      maxWidth: 48
    )
  }
}

@MainActor
private struct ToastLifecycle004Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    Button("Refresh Toast Chrome 004") { generation += 1 }
      .toast(
        "chrome generation \(generation)",
        isPresented: $isPresented,
        style: ToastLifecycle004Style(generation: generation),
        duration: nil
      )
  }
}

// MARK: - Attempt 005: active environment capture

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 005 active content reads the current source environment")
  func toastLifecycle005ActiveContentReadsTheCurrentSourceEnvironment() throws {
    // Hypothesis: portal payloads can retain the environment snapshot from activation and keep an
    // active toast reader isolated from later source-environment replacements.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle005"),
      size: .init(width: 60, height: 10)
    ) {
      ToastLifecycle005Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Advance Toast Environment 005")
      #expect(frame.contains("source environment value-\(generation)"))
      withKnownIssue("Toast content loses the source environment at the portal boundary") {
        #expect(frame.contains("toast environment value-\(generation)"))
      }
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

private enum ToastLifecycleEnvironmentKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var toastLifecycleValue: String {
    get { self[ToastLifecycleEnvironmentKey.self] }
    set { self[ToastLifecycleEnvironmentKey.self] = newValue }
  }
}

@MainActor
private struct ToastLifecycle005Reader: View {
  let prefix: String
  @Environment(\.toastLifecycleValue) private var value

  var body: some View {
    Text("\(prefix) environment \(value)")
  }
}

@MainActor
private struct ToastLifecycle005Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Toast Environment 005") { generation += 1 }
      ToastLifecycle005Reader(prefix: "source")
    }
    .toast(isPresented: $isPresented, duration: nil) {
      ToastLifecycle005Reader(prefix: "toast")
    }
    .environment(\.toastLifecycleValue, "value-\(generation)")
  }
}

// MARK: - Attempt 006: active timer binding retarget

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 006 active timer dismisses the current binding target")
  func toastLifecycle006ActiveTimerDismissesTheCurrentBindingTarget() async throws {
    // Hypothesis: the stable toast task can keep the Binding captured at activation even after the
    // live modifier retargets its dismissal write to a replacement owner.
    let bindingChanges = MainActorConditionSignal()
    let first = ToastLifecycleBox(true, signal: bindingChanges)
    let second = ToastLifecycleBox(true, signal: bindingChanges)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle006"),
      size: .init(width: 64, height: 10)
    ) {
      ToastLifecycle006Root(first: first, second: second)
    }
    defer { harness.shutdown() }

    let retargeted = try harness.clickText("Retarget Toast Binding 006")
    #expect(retargeted.contains("dismiss target second"))

    await bindingChanges.wait {
      !first.value || !second.value
    }
    _ = try harness.render()
    withKnownIssue("Active toast timer retains its activation binding after source retarget") {
      #expect(first.value && !second.value)
    }
  }
}

@MainActor
private final class ToastLifecycleBox<Value> {
  var value: Value {
    didSet { signal?.notify() }
  }
  private(set) var writes: [Value] = []
  private let signal: MainActorConditionSignal?

  init(_ value: Value, signal: MainActorConditionSignal? = nil) {
    self.value = value
    self.signal = signal
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes.append($0)
      }
    )
  }
}

@MainActor
private struct ToastLifecycle006Root: View {
  let first: ToastLifecycleBox<Bool>
  let second: ToastLifecycleBox<Bool>
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget Toast Binding 006") { usesSecond = true }
      Text("dismiss target \(usesSecond ? "second" : "first")")
      Text("first \(first.value) second \(second.value)")
    }
    .toast(
      "retargeted timer toast",
      isPresented: usesSecond ? second.binding() : first.binding(),
      duration: 0.08
    )
  }
}

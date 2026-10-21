import Observation
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

#if DEBUG
  @MainActor
  @Suite(.serialized)
  struct BodyChangeIntegrationTests {
    @Test("observation certificate fires before delivery retain owner-only evidence")
    func observation() {
      let probe = DiagnosticProbe()
      let model = DiagnosticModel()
      let renderer = DefaultRenderer()
      let root = testIdentity("DiagnosticObservation")
      let bridge = ObservationBridge()
      BodyChangeOutput.$sink.withValue(probe.sink) {
        for tick in 0..<3 {
          if tick == 2 { model.value += 1 }
          var context = ResolveContext(
            identity: root, invalidatedIdentities: tick == 0 ? [] : [root])
          context.observationBridge = bridge
          _ = renderer.render(
            DiagnosticObservedRoot(tick: tick).environment(model), context: context)
        }
      }
      let records = probe.records.filter { $0.typeName.hasSuffix("DiagnosticObserved") }
      #expect(records.count == 2)
      #expect(
        records.last?.causes.contains {
          $0.category == "observation" && $0.precision == "owner-only" && $0.property == nil
        } == true)
    }

    @Test("nested wrapper names and graph-backed binding readers follow actual reads")
    func nestedAndBinding() {
      let probe = DiagnosticProbe()
      let renderer = DefaultRenderer()
      let root = testIdentity("DiagnosticNested")
      BodyChangeOutput.$sink.withValue(probe.sink) {
        _ = renderer.render(DiagnosticNested(probe: probe), context: .init(identity: root))
        probe.binding?.wrappedValue = 42
        _ = renderer.render(
          DiagnosticNested(probe: probe),
          context: .init(identity: root, invalidatedIdentities: [root]))
      }
      #expect(
        probe.records.contains {
          $0.causes.contains {
            $0.category == "state" && $0.property == "_nested._value" && $0.precision == "exact"
          }
        })
      #expect(
        probe.records.contains {
          $0.typeName.hasSuffix("DiagnosticBindingReader")
            && $0.causes.contains {
              $0.category == "state" && $0.property == "_value" && $0.precision == "exact"
            }
        })
    }

    @Test("input equality evidence does not require extra comparisons or custom reflection")
    func inputAndReflection() {
      let probe = DiagnosticProbe()
      let plain = DiagnosticProbe()
      let renderer = DefaultRenderer()
      let oracle = DefaultRenderer()
      let root = testIdentity("DiagnosticInput")
      for tick in 0..<3 {
        let context = ResolveContext(identity: root, invalidatedIdentities: tick == 0 ? [] : [root])
        BodyChangeOutput.$sink.withValue(probe.sink) {
          _ = renderer.render(
            DiagnosticInputRoot(tick: tick, probe: probe, enabled: true), context: context)
        }
        _ = oracle.render(
          DiagnosticInputRoot(tick: tick, probe: plain, enabled: false), context: context)
      }
      #expect(probe.comparisons.withLock { $0 } == plain.comparisons.withLock { $0 })
      #expect(probe.reflections.withLock { $0 } == plain.reflections.withLock { $0 })
      #expect(
        probe.records.contains {
          $0.causes.contains { $0.property == "@self" && $0.precision == "exact" }
        })
    }

    @Test("typed environment changes report the subscribed body without reading extra values")
    func environment() {
      let probe = DiagnosticProbe()
      let renderer = DefaultRenderer()
      let root = testIdentity("DiagnosticEnvironment")
      BodyChangeOutput.$sink.withValue(probe.sink) {
        for tick in 0..<2 {
          _ = renderer.render(
            DiagnosticEnvironmentRoot(tick: tick).environment(\.diagnosticNumber, tick),
            context: .init(identity: root, invalidatedIdentities: tick == 0 ? [] : [root]))
        }
      }
      #expect(
        probe.records.contains {
          $0.typeName.hasSuffix("DiagnosticEnvironmentReader")
            && $0.causes.contains { $0.category == "environment" && $0.precision == "exact" }
        })
    }
  }

  @MainActor private final class DiagnosticProbe {
    var records: [BodyChangeRecord] = []
    var binding: Binding<Int>?
    let comparisons = Mutex<Int>(0)
    let reflections = Mutex<Int>(0)
    var sink: BodyChangeSink { .init { [self] record, _ in records.append(record) } }
  }
  @MainActor @Observable private final class DiagnosticModel { var value = 0 }
  private struct DiagnosticObservedRoot: View {
    let tick: Int
    var body: some View {
      VStack {
        Text("tick \(tick)")
        DiagnosticObserved()
      }
    }
  }
  private struct DiagnosticObserved: View, Equatable {
    @Environment(DiagnosticModel.self) private var model
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
    var body: some View {
      let _ = Self._printChanges()
      Text("model \(model.value)")
    }
  }
  @propertyWrapper private struct DiagnosticNestedState: DynamicProperty {
    @State private var value = 0
    var wrappedValue: Int { value }
    var projectedValue: Binding<Int> { $value }
    func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult { .unchanged }
  }
  private struct DiagnosticNested: View {
    let probe: DiagnosticProbe
    @DiagnosticNestedState private var nested
    var body: some View {
      Self._printChanges()
      probe.binding = $nested
      return VStack {
        Text("nested \(nested)")
        DiagnosticBindingReader(value: $nested)
      }
    }
  }
  private struct DiagnosticBindingReader: View {
    @Binding var value: Int
    var body: some View {
      let _ = Self._printChanges()
      Text("binding \(value)")
    }
  }
  private struct DiagnosticInputRoot: View {
    let tick: Int
    let probe: DiagnosticProbe
    let enabled: Bool
    var body: some View { VStack { DiagnosticInput(value: tick, probe: probe, enabled: enabled) } }
  }
  private struct DiagnosticInput: View, Equatable, CustomReflectable {
    let value: Int
    let probe: DiagnosticProbe
    let enabled: Bool
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.probe.comparisons.withLock { $0 += 1 }
      return lhs.value == rhs.value
    }
    nonisolated var customMirror: Mirror {
      probe.reflections.withLock { $0 += 1 }
      return Mirror(self, children: ["value": value])
    }
    var body: some View {
      let _ = enabled ? Self._printChanges() : ()
      Text("input \(value)")
    }
  }
  private enum DiagnosticNumberKey: EnvironmentKey { static let defaultValue = 0 }
  extension EnvironmentValues {
    fileprivate var diagnosticNumber: Int {
      get { self[DiagnosticNumberKey.self] }
      set { self[DiagnosticNumberKey.self] = newValue }
    }
  }
  private struct DiagnosticEnvironmentRoot: View {
    let tick: Int
    var body: some View {
      VStack {
        Text("tick \(tick)")
        DiagnosticEnvironmentReader()
      }
    }
  }
  private struct DiagnosticEnvironmentReader: View, Equatable {
    @Environment(\.diagnosticNumber) private var number
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
    var body: some View {
      let _ = Self._printChanges()
      Text("environment \(number)")
    }
  }
#endif

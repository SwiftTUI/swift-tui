import Observation
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private final class ObservationFlagOutputModel: Observable, Sendable {
  private let registrar = ObservationRegistrar()
  private let hotStorage = Mutex(0)

  var hot: Int {
    get {
      registrar.access(self, keyPath: \.hot)
      return hotStorage.withLock { $0 }
    }
    set {
      registrar.withMutation(of: self, keyPath: \.hot) {
        hotStorage.withLock { $0 = newValue }
      }
    }
  }
}

private struct ObservationFlagOutputProbe: View, Equatable {
  @Bindable var model: ObservationFlagOutputModel

  init(model: ObservationFlagOutputModel) {
    _model = Bindable(model)
  }

  nonisolated static func == (_: Self, _: Self) -> Bool {
    true
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("hot=\($model.hot.wrappedValue)")
      Text("stable")
    }
  }
}

/// Renders an `@Bindable` reader, mutates the observed property, and asserts the
/// committed output tracks the change. Locks the end-to-end correctness of the
/// (now unconditional) precise-firing + memo-reuse invalidation path: an
/// `Equatable` probe that reads a mutated observable property must still
/// re-render to the new value rather than being memo-reused stale.
@MainActor
struct ObservationFlagOutputStabilityTests {
  @Test("an observable mutation updates committed output")
  func observableMutationUpdatesOutput() {
    let renderer = DefaultRenderer()
    let model = ObservationFlagOutputModel()
    let rootIdentity = testIdentity("ObservationFlagOutputRoot")

    let initialLines = renderer.render(
      ObservationFlagOutputProbe(model: model),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 16, height: 2)
    ).rasterSurface.lines

    model.hot = 1
    let updatedLines = renderer.render(
      ObservationFlagOutputProbe(model: model),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 16, height: 2)
    ).rasterSurface.lines

    #expect(initialLines == ["hot=0", "stable"], "initial output drifted")
    #expect(updatedLines == ["hot=1", "stable"], "updated output drifted")
  }
}

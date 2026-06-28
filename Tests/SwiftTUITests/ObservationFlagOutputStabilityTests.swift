import Observation
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private struct ObservationOutputFlagCombination: Sendable, CustomStringConvertible {
  var precise: Bool
  var keyPath: Bool
  var readerAttribution: Bool
  var memoReuse: Bool

  var description: String {
    "precise=\(precise) keyPath=\(keyPath) reader=\(readerAttribution) memo=\(memoReuse)"
  }
}

private let allObservationOutputFlagCombinations: [ObservationOutputFlagCombination] = {
  var combinations: [ObservationOutputFlagCombination] = []
  for precise in [false, true] {
    for keyPath in [false, true] {
      for readerAttribution in [false, true] {
        for memoReuse in [false, true] {
          combinations.append(
            ObservationOutputFlagCombination(
              precise: precise,
              keyPath: keyPath,
              readerAttribution: readerAttribution,
              memoReuse: memoReuse
            )
          )
        }
      }
    }
  }
  return combinations
}()

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

@MainActor
@Suite(.serialized)
struct ObservationFlagOutputStabilityTests {
  private func withFlags<R>(
    _ combination: ObservationOutputFlagCombination,
    _ body: () throws -> R
  ) rethrows -> R {
    let previousPrecise = PreciseObservationFiringConfiguration.isEnabled
    let previousKeyPath = ObservableKeyPathInvalidationConfiguration.isEnabled
    let previousReader = ReaderAttributionConfiguration.isEnabled
    let previousMemo = MemoReuseConfiguration.isEnabled
    PreciseObservationFiringConfiguration.isEnabled = combination.precise
    ObservableKeyPathInvalidationConfiguration.isEnabled = combination.keyPath
    ReaderAttributionConfiguration.isEnabled = combination.readerAttribution
    MemoReuseConfiguration.isEnabled = combination.memoReuse
    defer {
      PreciseObservationFiringConfiguration.isEnabled = previousPrecise
      ObservableKeyPathInvalidationConfiguration.isEnabled = previousKeyPath
      ReaderAttributionConfiguration.isEnabled = previousReader
      MemoReuseConfiguration.isEnabled = previousMemo
    }
    return try body()
  }

  @Test(
    "observation flag combinations keep rendered output stable",
    arguments: allObservationOutputFlagCombinations
  )
  private func combinationsKeepRenderedOutputStable(
    _ combination: ObservationOutputFlagCombination
  ) {
    let renderer = DefaultRenderer()
    let model = ObservationFlagOutputModel()
    let rootIdentity = testIdentity("ObservationFlagOutputRoot")

    let initialLines = withFlags(combination) {
      renderer.render(
        ObservationFlagOutputProbe(model: model),
        context: .init(identity: rootIdentity),
        proposal: .init(width: 16, height: 2)
      ).rasterSurface.lines
    }

    model.hot = 1
    let updatedLines = withFlags(combination) {
      renderer.render(
        ObservationFlagOutputProbe(model: model),
        context: .init(identity: rootIdentity),
        proposal: .init(width: 16, height: 2)
      ).rasterSurface.lines
    }

    #expect(initialLines == ["hot=0", "stable"], "initial output drifted under \(combination)")
    #expect(updatedLines == ["hot=1", "stable"], "updated output drifted under \(combination)")
  }
}

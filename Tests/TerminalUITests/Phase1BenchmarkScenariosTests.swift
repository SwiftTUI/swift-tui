import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct Phase1BenchmarkScenariosTests {
  @Test("idle rerender reuses all layout work and writes nothing on the second frame")
  @MainActor
  func idleRerenderScenario() throws {
    let harness = BenchmarkHarness()

    let first = try harness.render(
      IdleBenchmarkView(),
      context: .init(identity: Phase1BenchmarkIdentity.root)
    )
    let second = try harness.render(
      IdleBenchmarkView(),
      context: .init(identity: Phase1BenchmarkIdentity.root)
    )

    #expect(first.presentation.strategy == .fullRepaint)
    #expect(second.presentation.strategy == .incremental)
    #expect(first.presentation.cellsChanged > 0)
    #expect(second.presentation.bytesWritten == 0)
    #expect(second.presentation.linesTouched == 0)
    #expect(second.presentation.cellsChanged == 0)
    #expect(second.diagnostics.measuredNodesComputed == 0)
    #expect(second.diagnostics.placedNodesComputed == 0)
    #expect(second.diagnostics.measuredNodesReused == second.diagnostics.measuredNodeCount)
    #expect(second.diagnostics.placedNodesReused == second.diagnostics.placedNodeCount)
  }

  @Test("focused button press only recomputes the changing counter row")
  @MainActor
  func focusedButtonPressScenario() throws {
    let harness = BenchmarkHarness()
    let counter = CounterBox()

    let first = try harness.render(
      FocusedButtonPressView(counter: counter),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.incrementButton
      )
    )

    counter.count = 1

    let second = try harness.render(
      FocusedButtonPressView(counter: counter),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.incrementButton
      )
    )

    #expect(first.presentation.strategy == .fullRepaint)
    #expect(second.presentation.strategy == .incremental)
    #expect(second.presentation.bytesWritten < first.presentation.bytesWritten)
    #expect(second.presentation.linesTouched < first.presentation.linesTouched)
    #expect(second.presentation.cellsChanged < first.presentation.cellsChanged)
    #expect(second.diagnostics.measuredNodesComputed < first.diagnostics.measuredNodesComputed)
    #expect(second.diagnostics.placedNodesComputed < first.diagnostics.placedNodesComputed)
    #expect(second.diagnostics.measuredNodesReused > 0)
    #expect(second.diagnostics.placedNodesReused > 0)
  }

  @Test("single-character text input produces a narrow incremental update")
  @MainActor
  func singleCharacterTextInputScenario() throws {
    let harness = BenchmarkHarness()
    let text = TextBox()

    let first = try harness.render(
      TextInputBenchmarkView(text: text),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.inputField
      )
    )

    text.value = "A"

    let second = try harness.render(
      TextInputBenchmarkView(text: text),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.inputField
      )
    )

    #expect(first.presentation.strategy == .fullRepaint)
    #expect(second.presentation.strategy == .incremental)
    #expect(second.presentation.bytesWritten < first.presentation.bytesWritten)
    #expect(second.presentation.linesTouched < first.presentation.linesTouched)
    #expect(second.presentation.cellsChanged < first.presentation.cellsChanged)
    #expect(second.diagnostics.measuredNodesComputed < first.diagnostics.measuredNodesComputed)
    #expect(second.diagnostics.placedNodesComputed < first.diagnostics.placedNodesComputed)
    #expect(second.diagnostics.measuredNodesReused > 0)
    #expect(second.diagnostics.placedNodesReused > 0)
  }

  @Test(
    "single-step scroll movement reuses measurement work even while placement remains conservative")
  @MainActor
  func singleStepScrollMovementScenario() throws {
    let harness = BenchmarkHarness()
    let position = ScrollBox()

    let first = try harness.render(
      ScrollBenchmarkView(position: position),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )

    position.position.scrollBy(y: 1)

    let second = try harness.render(
      ScrollBenchmarkView(position: position),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )

    #expect(first.presentation.strategy == .fullRepaint)
    #expect(second.presentation.strategy == .fullRepaint)
    #expect(second.presentation.bytesWritten > 0)
    #expect(second.diagnostics.measuredNodesComputed == 0)
    #expect(second.diagnostics.placedNodesComputed == first.diagnostics.placedNodesComputed)
    #expect(second.diagnostics.measuredNodesReused == second.diagnostics.measuredNodeCount)
    #expect(second.diagnostics.placedNodesReused == 0)
  }

  @Test("lazy scroll movement reduces placement work on viewport shifts")
  @MainActor
  func lazyScrollMovementScenario() throws {
    let eagerHarness = BenchmarkHarness()
    let lazyHarness = BenchmarkHarness()
    let eagerPosition = ScrollBox()
    let lazyPosition = ScrollBox()

    _ = try eagerHarness.render(
      ScrollBenchmarkView(position: eagerPosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )
    _ = try lazyHarness.render(
      LazyScrollBenchmarkView(position: lazyPosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )

    eagerPosition.position.scrollBy(y: 1)
    lazyPosition.position.scrollBy(y: 1)

    let eagerSecond = try eagerHarness.render(
      ScrollBenchmarkView(position: eagerPosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )
    let lazySecond = try lazyHarness.render(
      LazyScrollBenchmarkView(position: lazyPosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )

    #expect(eagerSecond.presentation.strategy == .fullRepaint)
    #expect(lazySecond.presentation.strategy == .incremental)
    #expect(lazySecond.diagnostics.measuredNodesComputed == 0)
    #expect(lazySecond.diagnostics.measuredNodesReused == lazySecond.diagnostics.measuredNodeCount)
    #expect(lazySecond.diagnostics.placedNodeCount < eagerSecond.diagnostics.placedNodeCount)
    #expect(lazySecond.presentation.bytesWritten < eagerSecond.presentation.bytesWritten)
  }

  @Test("lazy ForEach scroll movement reduces off-screen tree work on viewport shifts")
  @MainActor
  func lazyForEachScrollMovementScenario() throws {
    let stableHarness = BenchmarkHarness()
    let lazyHarness = BenchmarkHarness()
    let stablePosition = ScrollBox()
    let lazyPosition = ScrollBox()

    _ = try stableHarness.render(
      LazyScrollBenchmarkView(position: stablePosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )
    _ = try lazyHarness.render(
      LazyForEachScrollBenchmarkView(position: lazyPosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )

    stablePosition.position.scrollBy(y: 1)
    lazyPosition.position.scrollBy(y: 1)

    let stableSecond = try stableHarness.render(
      LazyScrollBenchmarkView(position: stablePosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )
    let lazySecond = try lazyHarness.render(
      LazyForEachScrollBenchmarkView(position: lazyPosition),
      context: benchmarkContext(
        focusedIdentity: Phase1BenchmarkIdentity.scrollRegion
      )
    )

    #expect(lazySecond.presentation.strategy == .incremental)
    #expect(lazySecond.diagnostics.resolvedNodeCount < stableSecond.diagnostics.resolvedNodeCount)
    #expect(lazySecond.diagnostics.measuredNodeCount < stableSecond.diagnostics.measuredNodeCount)
  }
}

private struct BenchmarkFrame {
  let diagnostics: FrameDiagnostics
  let presentation: TerminalPresentationMetrics
}

@MainActor
private final class BenchmarkHarness {
  private let renderer = DefaultRenderer(
    layoutEngine: .init(cache: MeasurementCache())
  )
  private let host = TerminalHost(
    inputFileDescriptor: 0,
    outputFileDescriptor: 1,
    fallbackSize: .init(width: 80, height: 24),
    controller: BenchmarkPresentationController(),
    capabilityProfile: .previewUnicode
  )

  func render<V: View>(
    _ view: V,
    context: ResolveContext
  ) throws -> BenchmarkFrame {
    let artifacts = renderer.render(view, context: context)
    let presentation = try host.present(artifacts.rasterSurface)
    return BenchmarkFrame(
      diagnostics: artifacts.diagnostics,
      presentation: presentation
    )
  }
}

private final class BenchmarkPresentationController: TerminalControlling, @unchecked Sendable {
  func isATTY(_: Int32) -> Bool {
    true
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_: String, to _: Int32) throws {}

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }
}

private final class CounterBox: @unchecked Sendable {
  var count = 0
}

private final class TextBox: @unchecked Sendable {
  var value = ""
}

private final class ScrollBox: @unchecked Sendable {
  var position = ScrollPosition.zero
}

private enum Phase1BenchmarkIdentity {
  static let root = testIdentity("Phase1Benchmark", "root")
  static let incrementButton = testIdentity("Phase1Benchmark", "button")
  static let inputField = testIdentity("Phase1Benchmark", "input")
  static let scrollRegion = testIdentity("Phase1Benchmark", "scroll")
}

private struct IdleBenchmarkView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Phase 1")
      Text("Idle rerender")
    }
  }
}

private struct FocusedButtonPressView: View {
  let counter: CounterBox

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Phase 1")
      Text("Count: \(counter.count)")
      Button("Increment") {
        counter.count += 1
      }
      .id(Phase1BenchmarkIdentity.incrementButton)
    }
  }
}

private struct TextInputBenchmarkView: View {
  let text: TextBox

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Phase 1")
      TextField(
        "Name",
        text: Binding(
          get: { text.value },
          set: { text.value = $0 }
        )
      )
      .id(Phase1BenchmarkIdentity.inputField)
      Text("Echo: \(text.value)")
    }
  }
}

private struct ScrollBenchmarkView: View {
  let position: ScrollBox

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: true,
      position: Binding(
        get: { position.position },
        set: { position.position = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Row 0")
        Text("Row 1")
        Text("Row 2")
        Text("Row 3")
        Text("Row 4")
        Text("Row 5")
        Text("Row 6")
        Text("Row 7")
      }
    }
    .id(Phase1BenchmarkIdentity.scrollRegion)
    .frame(width: 12, height: 3, alignment: .topLeading)
  }
}

private struct LazyScrollBenchmarkView: View {
  let position: ScrollBox

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: true,
      position: Binding(
        get: { position.position },
        set: { position.position = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        Text("Row 0")
        Text("Row 1")
        Text("Row 2")
        Text("Row 3")
        Text("Row 4")
        Text("Row 5")
        Text("Row 6")
        Text("Row 7")
      }
    }
    .id(Phase1BenchmarkIdentity.scrollRegion)
    .frame(width: 12, height: 3, alignment: .topLeading)
  }
}

private struct LazyForEachScrollBenchmarkView: View {
  let position: ScrollBox

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: true,
      position: Binding(
        get: { position.position },
        set: { position.position = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<5) { index in
          Text("Row \(index)")
        }
      }
    }
    .id(Phase1BenchmarkIdentity.scrollRegion)
    .frame(width: 12, height: 3, alignment: .topLeading)
  }
}

private func benchmarkContext(
  focusedIdentity: Identity?
) -> ResolveContext {
  var environmentValues = EnvironmentValues()
  environmentValues.focusedIdentity = focusedIdentity
  return .init(
    identity: Phase1BenchmarkIdentity.root,
    environmentValues: environmentValues
  )
}

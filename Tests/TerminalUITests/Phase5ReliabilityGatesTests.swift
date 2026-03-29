import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@Suite
struct Phase5ReliabilityGatesTests {
  @MainActor
  @Test("an identical rerender stays idle and reuses the cached subtree")
  func identicalRerenderStaysIdle() throws {
    let harness = Phase5PresentationHarness()

    let first = try harness.render(
      Phase5StableTextView(),
      context: .init(identity: testIdentity("Phase5", "Root"))
    )

    let second = try harness.render(
      Phase5StableTextView(),
      context: .init(identity: testIdentity("Phase5", "Root"))
    )

    #expect(first.presentation.strategy == .fullRepaint)
    #expect(second.presentation.bytesWritten == 0)
    #expect(second.presentation.linesTouched == 0)
    #expect(second.presentation.cellsChanged == 0)
    #expect(second.diagnostics.measuredNodesReused > 0)
    #expect(second.diagnostics.placedNodesReused > 0)
  }
}

private struct Phase5PresentationFrame {
  let diagnostics: FrameDiagnostics
  let presentation: TerminalPresentationMetrics
}

private final class Phase5PresentationHarness {
  private let renderer = DefaultRenderer(
    layoutEngine: .init(cache: MeasurementCache())
  )
  private let host = TerminalHost(
    inputFileDescriptor: 0,
    outputFileDescriptor: 1,
    fallbackSize: .init(width: 16, height: 2),
    controller: Phase5PresentationController(),
    capabilityProfile: .previewUnicode
  )

  func render<V: View>(
    _ view: V,
    context: ResolveContext
  ) throws -> Phase5PresentationFrame {
    let artifacts = renderer.render(view, context: context)
    let presentation = try host.present(artifacts.rasterSurface)
    return .init(diagnostics: artifacts.diagnostics, presentation: presentation)
  }
}

private final class Phase5PresentationController: TerminalControlling {
  func isATTY(_: Int32) -> Bool {
    true
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 16, height: 2)
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

private struct Phase5StableTextView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Name: Ada")
      Text("Ready")
    }
  }
}

import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
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
    #expect(!second.presentation.usedSynchronizedOutput)
    #expect(second.presentation.graphicsReplayScope == .none)
    #expect(second.presentation.editOperationLowering == .none)
    #expect(second.presentation.editOperationCount == 0)
    #expect(second.diagnostics.measuredNodesReused > 0)
    #expect(second.diagnostics.placedNodesReused > 0)
  }

  @MainActor
  @Test("full repaint metrics report synchronized framing when the capability profile supports it")
  func synchronizedFullRepaintMetricsAreVisible() throws {
    let harness = Phase5PresentationHarness(
      capabilityProfile: synchronizedPreviewCapabilityProfile()
    )

    let first = try harness.render(
      Phase5StableTextView(),
      context: .init(identity: testIdentity("Phase5", "SyncRoot"))
    )

    #expect(first.presentation.strategy == .fullRepaint)
    #expect(first.presentation.usedSynchronizedOutput)
    #expect(first.presentation.graphicsReplayScope == .none)
    #expect(first.presentation.editOperationLowering == .none)
    #expect(first.presentation.editOperationCount == 0)
  }
}

private struct Phase5PresentationFrame {
  let diagnostics: FrameDiagnostics
  let presentation: TerminalPresentationMetrics
}

@MainActor
private final class Phase5PresentationHarness {
  private let renderer: DefaultRenderer
  private let host: TerminalHost

  init(
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  ) {
    renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 16, height: 2),
      controller: Phase5PresentationController(),
      capabilityProfile: capabilityProfile
    )
  }

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

  func windowSize(of _: Int32) throws -> CellSize {
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

private func synchronizedPreviewCapabilityProfile() -> TerminalCapabilityProfile {
  .init(
    glyphLevel: .unicode,
    colorLevel: .none,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: false,
    supportsMouseReporting: false,
    supportsSynchronizedOutput: true
  )
}

import Foundation
import SwiftTUIViews
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@MainActor
@Suite
struct RenderDriverInstrumentationCostTests {
  @Test("Rendering without reading diagnostics does not walk diagnostic trees")
  func diagnosticsAreLazy() {
    FrameDiagnostics.debugResetSummaryComputationCount()
    let renderer = DefaultRenderer()
    let artifacts = renderer.render(
      VStack {
        Text("a")
        Text("b")
      },
      context: .init(identity: testIdentity("DiagnosticsLazyRoot")))

    _ = artifacts.rasterSurface

    #expect(
      FrameDiagnostics.debugSummaryComputationCount() == 0,
      "diagnostics summary was computed despite no diagnostics consumer")
  }

  @Test("Reading diagnostics computes the summary exactly once")
  func diagnosticsComputedOnceWhenRead() {
    FrameDiagnostics.debugResetSummaryComputationCount()
    let renderer = DefaultRenderer()
    let artifacts = renderer.render(
      VStack {
        Text("a")
        Text("b")
      },
      context: .init(identity: testIdentity("DiagnosticsReadRoot")))

    _ = artifacts.diagnostics.counts.resolvedNodes
    _ = artifacts.diagnostics.counts.resolvedNodes

    #expect(FrameDiagnostics.debugSummaryComputationCount() == 1)
  }

  @Test("Artifact construction does not call FrameDiagnostics.summarize eagerly")
  func artifactConstructionDoesNotCallFrameDiagnosticsSummarize() throws {
    let root = try repositoryRoot()
    let rendererSource = try String(
      contentsOf: root.appendingPathComponent("Sources/SwiftTUIRuntime/SwiftTUI.swift"),
      encoding: .utf8
    )

    #expect(!rendererSource.contains("FrameDiagnostics.summarize("))
  }
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw RenderDriverInstrumentationSourceError.missingPackageRoot
}

private enum RenderDriverInstrumentationSourceError: Error {
  case missingPackageRoot
}

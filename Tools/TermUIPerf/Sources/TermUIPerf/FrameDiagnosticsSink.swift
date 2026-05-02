import Foundation
@_spi(Runners) import TerminalUI

@MainActor
public final class FrameDiagnosticsSink {
  public let framesURL: URL
  public let logger: FrameDiagnosticsLogger

  public init(runDirectory: URL) throws {
    framesURL = runDirectory.appendingPathComponent("frames.tsv")
    guard let logger = FrameDiagnosticsLogger(path: framesURL.path) else {
      throw PerfScenarioError.cannotCreateDiagnostics(framesURL.path)
    }
    self.logger = logger
  }
}

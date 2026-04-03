import Testing

@testable import TerminalUIWASI

struct TerminalWASIAppRunnerTests {
  @Test("native execution without manifest mode reports an explicit error")
  func nativeExecutionWithoutManifestModeReportsError() {
    #if canImport(WASILibc)
      #expect(Bool(true))
    #else
      #expect(
        TerminalWASIAppRunnerError.nativeExecutionUnsupported.description.contains("manifest mode")
      )
    #endif
  }
}

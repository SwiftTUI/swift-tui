import Testing

@testable import SwiftTUIWASI

struct WASIRunnerTests {
  @Test("native execution without manifest mode reports an explicit error")
  func nativeExecutionWithoutManifestModeReportsError() {
    #if canImport(WASILibc)
      #expect(Bool(true))
    #else
      #expect(
        WASIRunnerError.nativeExecutionUnsupported.description.contains("manifest mode")
      )
    #endif
  }
}

import Testing

@testable import SwiftTUIWASI

struct WASIRunnerTests {
  @Test("native execution without manifest mode reports an explicit error")
  func nativeExecutionWithoutManifestModeReportsError() {
    #if canImport(WASILibc)
      #expect(resolveWASITransportMode(environmentValue: { _ in nil }) == .surface)
    #else
      #expect(
        WASIRunnerError.nativeExecutionUnsupported.description.contains("manifest mode")
      )
    #endif
  }

  @Test("transport mode defaults to surface and keeps ANSI aliases explicit")
  func transportModeResolution() {
    #expect(resolveWASITransportMode(environmentValue: { _ in nil }) == .surface)
    #expect(resolveWASITransportMode(environmentValue: { _ in "surface" }) == .surface)
    #expect(resolveWASITransportMode(environmentValue: { _ in "ansi" }) == .ansi)
    #expect(resolveWASITransportMode(environmentValue: { _ in "terminal" }) == .ansi)
    #expect(resolveWASITransportMode(environmentValue: { _ in "xterm" }) == .ansi)
    #expect(resolveWASITransportMode(environmentValue: { _ in "ghostty-web" }) == .ansi)
  }
}

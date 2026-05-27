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

  @Test("surface delta parser enables only explicit truthy values")
  func surfaceDeltaParser() {
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in nil }) == false)
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in "1" }) == true)
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in "true" }) == true)
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in "yes" }) == true)
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in "on" }) == true)
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in "0" }) == false)
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in "false" }) == false)
    #expect(wasiSurfaceDeltaEnabled(environmentValue: { _ in "off" }) == false)
  }

  @Test("frame diagnostics parser rejects falsey values")
  func frameDiagnosticsParser() {
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in nil }) == false)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in "" }) == false)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in "0" }) == false)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in "false" }) == false)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in "off" }) == false)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in "none" }) == false)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in "1" }) == true)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { _ in "yes" }) == true)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { name in
      name == "TUIGUI_FRAME_DIAGNOSTICS" ? "0" : "1"
    }) == false)
    #expect(wasiFrameDiagnosticsEnabled(environmentValue: { name in
      name == "TERMUI_DIAGNOSTICS" ? "1" : nil
    }) == true)
  }
}

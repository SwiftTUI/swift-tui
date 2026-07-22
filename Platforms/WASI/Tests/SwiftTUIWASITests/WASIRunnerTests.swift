import SwiftTUIRuntime
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

  @Test("env capability resolution: absence means today's defaults")
  func wireCapabilitiesResolution() {
    #expect(
      wasiHostWireCapabilities(environmentValue: { _ in nil })
        == HostWireCapabilities()
    )
    // The pre-existing delta opt-in maps onto acceptsDeltaFrames and implies
    // the v3 record shape.
    #expect(
      wasiHostWireCapabilities(environmentValue: { name in
        name == "TUIGUI_SURFACE_DELTA" ? "1" : nil
      })
        == HostWireCapabilities(maxWebSurfaceVersion: 3, acceptsDeltaFrames: true)
    )
    // An explicit max version wins over the delta implication.
    #expect(
      wasiHostWireCapabilities(environmentValue: { name in
        switch name {
        case "TUIGUI_SURFACE_DELTA": "1"
        case "TUIGUI_SURFACE_MAX_VERSION": "2"
        default: nil
        }
      })
        == HostWireCapabilities(maxWebSurfaceVersion: 2, acceptsDeltaFrames: true)
    )
    #expect(
      wasiHostWireCapabilities(environmentValue: { name in
        name == "TUIGUI_SURFACE_MAX_VERSION" ? " 3 " : nil
      })
        == HostWireCapabilities(maxWebSurfaceVersion: 3)
    )
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

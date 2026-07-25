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
    // TUIGUI_SURFACE_DELTA is the whole WASI declaration.
    #expect(
      wasiHostWireCapabilities(environmentValue: { name in
        name == "TUIGUI_SURFACE_DELTA" ? "1" : nil
      })
        == HostWireCapabilities(acceptsDeltaFrames: true)
    )
  }

  @Test("the retired version-ceiling key is inert")
  func retiredVersionCeilingKeyIsInert() {
    // This pins the resolution of a real defect rather than a hypothetical.
    // TUIGUI_SURFACE_MAX_VERSION used to overwrite a declared ceiling while
    // the transport took its delta switch from a second, independently
    // resolved env read — so this exact pairing declared a v2 ceiling and
    // then emitted v3 delta records into it. The ceiling is gone and the
    // transport has only one answer to take, so the key now does nothing.
    let withCeiling = wasiHostWireCapabilities(environmentValue: { name in
      switch name {
      case "TUIGUI_SURFACE_DELTA": "1"
      case "TUIGUI_SURFACE_MAX_VERSION": "2"
      default: nil
      }
    })
    #expect(withCeiling == HostWireCapabilities(acceptsDeltaFrames: true))

    let ceilingAlone = wasiHostWireCapabilities(environmentValue: { name in
      name == "TUIGUI_SURFACE_MAX_VERSION" ? " 3 " : nil
    })
    #expect(ceilingAlone == HostWireCapabilities())
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

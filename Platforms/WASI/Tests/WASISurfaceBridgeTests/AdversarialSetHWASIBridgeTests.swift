// Adversarial set H, pass 1 (F6 platform edges): the WASI surface bridge's
// numeric grammar and budget boundaries (setH083–setH094). Swift's
// Double(String) and Int(String) grammars are the parser's number grammar;
// the host-wire contract speaks decimal. Pure parser calls; no descriptors.
import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import CRT
#endif

/// Keeps an unmarked reproduction path (`SWIFTTUI_SETH_UNMARKED=1`) while
/// limiting each guard to its exact reproduced assertion.
private func setHKnown(_ comment: Comment, _ body: () throws -> Void) rethrows {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETH_UNMARKED"] == "1" {
    try body()
  } else {
    withKnownIssue(comment) { try body() }
  }
}

private func setHKnown(_ comment: Comment, _ body: () async throws -> Void) async rethrows {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETH_UNMARKED"] == "1" {
    try await body()
  } else {
    await withKnownIssue(comment) { try await body() }
  }
}

@Suite("Adversarial set H: WASI bridge grammar")
struct AdversarialSetHWASIBridgeTests {
  private func record(_ command: String) -> [UInt8] {
    [0x1E] + Array(command.utf8) + [0x0A]
  }

  private func feed(_ command: String) -> (
    events: [InputEvent], controlMessages: [WebSurfaceInputControlMessage]
  ) {
    var parser = WebSurfaceInputParser()
    return parser.feed(record(command))
  }

  // The parser checks only isFinite; PointerLocation.subCell then computes
  // Point.containingCell with an unchecked Int conversion.
  @Test func setH083HugeFiniteMouseCoordinateTraps() async {
    await setHKnown(
      "STUI-823: setH083: mouse:moved:1e300 traps the WASI bridge host (3e9 already traps on wasm32 under Bun and wasmkit); the parser admits any finite Double (WebSurfaceInputParser.swift:343-344) and PointerLocation.subCell calls Point.containingCell (setH055 mechanism, PointerLocation.swift:79); contract: host-wire input never traps the host; adjacent STUI-1145"
    ) {
      await #expect(processExitsWith: .success) {
        var parser = WebSurfaceInputParser()
        let result = parser.feed([0x1E] + Array("mouse:moved:1e300:0:none:0:0:0".utf8) + [0x0A])
        #expect(result.events.isEmpty)
      }
    }
  }

  @Test func setH084HexFloatMouseCoordinateAccepted() {
    let hex = feed("mouse:moved:0x1p3:0:none:0:0:0")
    setHKnown(
      "STUI-1229: setH084: mouse:moved:0x1p3 is accepted with x == 8; Swift Double(String) accepts hexadecimal floats (WebSurfaceInputParser.swift:343-344); contract: HOST-WIRE-CONTRACT numbers are decimal (docs/HOST-WIRE-CONTRACT.md:39, 107); adjacent STUI-1145"
    ) {
      #expect(hex.events.isEmpty, "\(hex.events)")
    }
    #expect(feed("mouse:moved:inf:0:none:0:0:0").events.isEmpty)
    #expect(feed("mouse:moved:nan:0:none:0:0:0").events.isEmpty)
  }

  @Test func setH085ResizeIntegerGrammar() {
    #expect(feed("resize:0x10:24").controlMessages.isEmpty)
    #expect(feed("resize:1_0:24").controlMessages.isEmpty)
    #expect(feed("resize: 10:24").controlMessages.isEmpty)
    #expect(
      feed("resize:+10:24").controlMessages
        == [.resize(CellSize(width: 10, height: 24), cellPixelSize: nil)])
  }

  @Test func setH086GeometryRevisionGrammar() {
    let messages = feed("geometry:007:80:24:8:16").controlMessages
    guard case .geometry(let request)? = messages.first else {
      Issue.record("geometry record rejected: \(messages)")
      return
    }
    #expect(request.revision == 7)
    #expect(feed("geometry:-1:80:24:8:16").controlMessages.isEmpty)
    #expect(feed("geometry:18446744073709551616:80:24:8:16").controlMessages.isEmpty)
  }

  @Test func setH087ResizeBeyondInt32Rejected() {
    #expect(feed("resize:2147483648:24").controlMessages.isEmpty)
  }

  @Test func setH088WouldBlockErrnoClassification() {
    #expect(webSurfaceErrnoIsWouldBlock(EAGAIN))
    #expect(webSurfaceErrnoIsWouldBlock(EWOULDBLOCK))
    #expect(!webSurfaceErrnoIsWouldBlock(EINTR))
  }

  @Test func setH089BudgetAdmitsBoundaries() {
    #expect(HostWireBudget.admits(CellSize(width: 1024, height: 64)))
    #expect(!HostWireBudget.admits(CellSize(width: 1024, height: 65)))
    #expect(!HostWireBudget.admits(CellSize(width: 1024, height: 1024)))
    #expect(!HostWireBudget.admits(CellSize(width: 65535, height: 65535)))
    #expect(!HostWireBudget.admits(CellSize(width: -1, height: 1)))
  }

  @Test func setH090PercentDecodingRequiresTwoHexDigits() {
    #expect(feed("key:character:%4:0").events.isEmpty)
    #expect(feed("key:character:%:0").events.isEmpty)
    #expect(feed("key:character:%zz:0").events.isEmpty)
    #expect(feed("key:character:%41:0").events == [.key(KeyPress(.character("A"), modifiers: []))])
  }

  @Test func setH091FourByteCharacterDecodes() {
    let single = feed("key:character:%F0%9F%98%80:0").events
    #expect(single == [.key(KeyPress(.character("\u{1F600}"), modifiers: []))])
    let pair = feed("key:character:%F0%9F%98%80%F0%9F%98%80:0").events
    #expect(pair == [.key(KeyPress(.character("\u{1F600}"), modifiers: []))])
  }

  @Test func setH092NegativeMouseCoordinatesFloor() {
    let events = feed("mouse:moved:-0.5:-0.5:none:0:0:0").events
    guard case .mouse(let event)? = events.first else {
      Issue.record("mouse record rejected: \(events)")
      return
    }
    #expect(event.location.cell == CellPoint(x: -1, y: -1))
    #expect(event.location.precision.isSubCell)
  }

  @Test func setH093StandardDescriptorsArePlatformConstants() {
    #expect(webSurfaceStandardInputFileDescriptor == 0)
    #expect(webSurfaceStandardOutputFileDescriptor == 1)
  }

  @Test func setH094BudgetFallbackAndRejectionRecord() {
    #expect(
      HostWireBudget.initialSize(CellSize(width: 2000, height: 2000))
        == CellSize(width: 80, height: 24))
    let bytes = Array(HostWireBudget.rejectionRecord.utf8)
    #expect(bytes.first == 0x1E)
    #expect(bytes.last == 0x0A)
  }
}

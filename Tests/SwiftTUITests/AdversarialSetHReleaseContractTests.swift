// Adversarial set H, pass 1 (F6 platform edges): contracts that only a
// release configuration or a different libc exercises (setH069–setH074,
// setH076–setH082). `_isDebugAssertConfiguration()` attributes the
// configuration-split expectations; POSIX pieces are compiled out on Windows.
import Foundation
import SwiftTUIPrimitives
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite("Adversarial set H: release and configuration contracts", .serialized)
struct AdversarialSetHReleaseContractTests {
  // Two processes encode the same surface; style-table ids, cell rows and
  // the record framing must not depend on per-process hash seeds.
  @Test func setH069WireEncodingIsDeterministicAcrossProcesses() async {
    let first = await #expect(processExitsWith: .success, observing: [\.standardOutputContent]) {
      setH069PrintEncodedFrame()
    }
    let second = await #expect(processExitsWith: .success, observing: [\.standardOutputContent]) {
      setH069PrintEncodedFrame()
    }
    let firstBytes = first?.standardOutputContent ?? []
    #expect(!firstBytes.isEmpty)
    #expect(firstBytes == second?.standardOutputContent ?? [])
  }

  // Mutating presentation state during an update is a runtime warning in
  // SwiftUI. Every configuration refuses the mutation and records one
  // warning; nothing traps (STUI-1226).
  @Test func setH070PresentationMutationGuardWarnsWithoutTrapping() async {
    let (allowed, issues) = await MainActor.run {
      _ = ImperativeRuntimeIssueQueue.drain()
      let allowed = ViewUpdateGuard.withViewUpdate {
        PresentationMutationGuard.allowMutation("setH070")
      }
      return (allowed, ImperativeRuntimeIssueQueue.drain())
    }
    #expect(!allowed)
    #expect(issues.map(\.code) == ["presentation.mutationDuringViewUpdate"])
    #expect(issues.map(\.severity) == [.warning])
    #expect(issues.map(\.source) == ["PresentationCoordinator"])
    #expect(issues.first?.message.hasPrefix("setH070") == true)
    await setH070RefusesWithoutTrapping()
  }

  @Test func setH071PrintChangesOutsideBodyNeverTraps() async {
    await MainActor.run {
      Text._printChanges()
      Text._logChanges()
    }
  }

  @Test func setH072RasterVerificationGatesDefaultOff() {
    #expect(!FeatureGate.rasterVerifyIncremental.initialIsEnabled())
    #expect(!FeatureGate.rasterTrustSoundDamage.initialIsEnabled())
  }

  @Test func setH073DebugOnlyProbesStayZeroInRelease() async {
    let expected = _isDebugAssertConfiguration() ? 1 : 0
    let membership = await MainActor.run {
      CollectionSelectionProbe.reset()
      CollectionSelectionProbe.recordMembershipTest()
      return CollectionSelectionProbe.membershipTests
    }
    #expect(membership == expected)
    TableLayoutDerivationProbe.reset()
    TableLayoutDerivationProbe.recordDerivation()
    #expect(TableLayoutDerivationProbe.derivationCount == expected)
  }

  @Test func setH074TextFigureConfigurationErrorNeverTrapsUnderTest() {
    reportTextFigureConfigurationError("setH074 deliberate configuration error")
  }

  #if canImport(Darwin) || canImport(Glibc)
    // read(2) with nbyte == 0 returns 0 without transferring data; the chunk
    // reader maps every zero to end of file.
    @Test func setH076ZeroByteReadIsNotEndOfFile() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      let result = readTerminalInputChunk(from: pipe.readEnd, maxBytes: 0)
      setHKnown(
        "STUI-1227: setH076: readTerminalInputChunk(maxBytes: 0) reports .endOfFile on an open pipe; every bytesRead == 0 maps to end of file (TerminalInputStreamReading.swift:88-94); contract: POSIX read(2) with nbyte 0 transfers nothing and is not end of file; adjacent: none"
      ) {
        #expect(result != .endOfFile, "\(result)")
      }
    }

    @Test func setH077ChunkReadErrnoClassification() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      let flags = fcntl(pipe.readEnd, F_GETFL)
      try #require(fcntl(pipe.readEnd, F_SETFL, flags | O_NONBLOCK) == 0)
      #expect(readTerminalInputChunk(from: pipe.readEnd, maxBytes: 8) == .wouldBlock)
      let closed = try SetHPipe()
      closed.closeAll()
      #expect(readTerminalInputChunk(from: closed.readEnd, maxBytes: 8) == .failure(errno: EBADF))
      let directory = ".".withCString { unsafe open($0, O_RDONLY) }
      try #require(directory >= 0)
      defer { _ = close(directory) }
      #expect(readTerminalInputChunk(from: directory, maxBytes: 8) == .failure(errno: EISDIR))
    }

    @Test func setH078DrainLoopsUntilWouldBlockOrEOF() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      let flags = fcntl(pipe.readEnd, F_GETFL)
      try #require(fcntl(pipe.readEnd, F_SETFL, flags | O_NONBLOCK) == 0)
      try pipe.send([1, 2, 3])
      let small = drainAvailableTerminalInput(from: pipe.readEnd, maxBytesPerRead: 1)
      #expect(small.bytes == [1, 2, 3])
      #expect(!small.shouldFinish)
      let payload = [UInt8](repeating: 0x5A, count: 10_240)
      try pipe.send(payload)
      let large = drainAvailableTerminalInput(from: pipe.readEnd, maxBytesPerRead: 4096)
      #expect(large.bytes == payload)
      #expect(!large.shouldFinish)
      pipe.closeWrite()
      let ended = drainAvailableTerminalInput(from: pipe.readEnd, maxBytesPerRead: 4096)
      #expect(ended.bytes.isEmpty)
      #expect(ended.shouldFinish)
      #expect(ended.failureErrno == nil)
      pipe.closeRead()
    }
  #endif

  // `detect` selects the console arm on Windows; this pins the POSIX arm.
  #if !os(Windows)
    @Test func setH079EmptyEnvironmentConsoleProfile() {
      let detected = TerminalCapabilityProfile.detect(environment: [:], isTTY: true)
      #expect(detected.glyphLevel == .ascii)
      #expect(detected.colorLevel == .ansi16)
      #expect(detected.supportsScrollRegions)
      #expect(!detected.supportsMouseReporting)
    }
  #endif

  @Test func setH080FractionInCellIsTotal() {
    let fraction = Point(x: 1e300, y: -2.25).fractionInCell
    #expect(fraction.x == 0)
    #expect(fraction.y == 0.75)
  }

  #if canImport(Darwin) || canImport(Glibc)
    // Pipes refuse a diagnostic above PIPE_BUF so a fragment never lands;
    // PIPE_BUF is 512 on Darwin and 4096 on Linux.
    @Test func setH081DiagnosticPipeAtomicityByPlatform() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      let atomic = fpathconf(pipe.writeEnd, Int32(_PC_PIPE_BUF))
      try #require(atomic > 0)
      let message = String(repeating: "x", count: 1000)
      let accepted = DebugLogRouter.writeDiagnostic(message, to: pipe.writeEnd)
      #expect(accepted == (1000 <= atomic), "PIPE_BUF \(atomic)")
      #expect(DebugLogRouter.writeDiagnostic("short", to: pipe.writeEnd))
      let drained = try pipe.drainAvailable()
      #expect(drained == (accepted ? 1005 : 5))
    }

    @Test func setH082DiagnosticToClosedPipeSurvives() async {
      await #expect(processExitsWith: .success) {
        let pipe = try SetHPipe()
        pipe.closeRead()
        defer { pipe.closeWrite() }
        #expect(!DebugLogRouter.writeDiagnostic("setH082", to: pipe.writeEnd))
      }
    }
  #endif
}

/// The mutation is refused and the process survives.
private func setH070RefusesWithoutTrapping() async {
  await #expect(processExitsWith: .success) {
    let allowed = await MainActor.run {
      ViewUpdateGuard.withViewUpdate { PresentationMutationGuard.allowMutation("setH070") }
    }
    #expect(!allowed)
    let pending = await MainActor.run { ImperativeRuntimeIssueQueue.drain() }
    #expect(pending.map(\.code) == ["presentation.mutationDuringViewUpdate"])
  }
}

/// Encodes one fixed surface and prints the record without a trailing newline
/// (the exit tests compare the captured standard output byte for byte).
private func setH069PrintEncodedFrame() {
  let red = ResolvedTextStyle(foregroundColor: .red)
  let blue = ResolvedTextStyle(backgroundColor: .blue)
  let rows: [[RasterCell]] = [
    [
      RasterCell(character: "a", style: red), RasterCell(character: "b", style: blue), RasterCell(),
    ],
    [
      RasterCell(character: "c", style: blue), RasterCell(character: "d", style: red), RasterCell(),
    ],
  ]
  let surface = RasterSurface(size: CellSize(width: 3, height: 2), cells: rows)
  print(WebSurfaceFrameEncoder.encode(surface), terminator: "")
}

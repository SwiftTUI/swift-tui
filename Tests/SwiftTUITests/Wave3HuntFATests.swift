import Foundation
import SwiftTUIPrimitives
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

// Campaign two, wave-3 regression hunt part FA (STUI-1167): forty pre-specified
// neighbours of the wave-3 repairs FW3-A (3af7dd55), FW3-B (fa1b02ef,
// 9d74b0fb), FW3-C (fc86adcc) and FW3-D (6b3a985e). The attach-discovery and
// Linux facade cases (w3fa005, w3fa006, w3fa010) live in
// Platforms/CLI/Tests/SwiftTUICLITests/Wave3HuntFACLITests.swift. Contracts,
// inputs and predictions: docs/reports/evidence/2026-10-25-campaign-two-wave-3-hunt/fa/
// in the coordination root. Reproduced expectations are wrapped in
// `w3faKnown`; `SWIFTTUI_W3HUNT_UNMARKED=1` runs them as plain assertions.

func w3faKnown(_ comment: Comment, _ body: () throws -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W3HUNT_UNMARKED"] == "1" {
    do { try body() } catch { Issue.record(error) }
  } else {
    withKnownIssue(comment) { try body() }
  }
}

func w3faKnownAsync(_ comment: Comment, _ body: () async throws -> Void) async {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W3HUNT_UNMARKED"] == "1" {
    do { try await body() } catch { Issue.record(error) }
  } else {
    await withKnownIssue(comment) { try await body() }
  }
}

// MARK: - FW3-A: POSIX edges and redirected diagnostics

#if canImport(Darwin) || canImport(Glibc)
  private let w3faIsLinux: Bool = {
    #if os(Linux)
      return true
    #else
      return false
    #endif
  }()

  #if canImport(Glibc)
    private let w3faStreamSocketType = Int32(SOCK_STREAM.rawValue)
    private let w3faDatagramSocketType = Int32(SOCK_DGRAM.rawValue)
  #else
    private let w3faStreamSocketType = SOCK_STREAM
    private let w3faDatagramSocketType = SOCK_DGRAM
  #endif

  /// The socket kinds the STUI-1271 pins cross: TCP, UDP, TCPv6 and AF_UNIX.
  private let w3faSocketKinds: [(name: String, family: Int32, type: Int32)] = [
    ("tcp", AF_INET, w3faStreamSocketType), ("udp", AF_INET, w3faDatagramSocketType),
    ("tcp6", AF_INET6, w3faStreamSocketType), ("unix", AF_UNIX, w3faStreamSocketType),
  ]

  /// A fresh unbound socket of `kind`, or nil when the host lacks the family
  /// (an IPv6-less container).
  private func w3faSocket(
    _ kind: (name: String, family: Int32, type: Int32)
  ) throws -> Int32? {
    let descriptor = socket(kind.family, kind.type, 0)
    if descriptor < 0, errno == EAFNOSUPPORT { return nil }
    try #require(descriptor >= 0, "\(kind.name) socket: errno \(errno)")
    return descriptor
  }

  /// Reads whatever `descriptor` holds without blocking.
  func w3faReadAvailable(_ descriptor: Int32) -> String {
    let flags = fcntl(descriptor, F_GETFL)
    _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    defer { _ = fcntl(descriptor, F_SETFL, flags) }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
      let count = buffer.withUnsafeMutableBytes {
        unsafe read(descriptor, $0.baseAddress, $0.count)
      }
      if count <= 0 { break }
      bytes.append(contentsOf: buffer[0..<count])
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  @Suite(.serialized)
  struct Wave3HuntFAPlatformTests {
    // w3fa001 (blocked: linux): glibc's VEOL2 sits at index 16, where the
    // positional write used to land; an authored VEOL2 survives raw entry and
    // restoration (termios(3), cfmakeraw; TerminalPOSIXController.swift:101-110).
    @Test(.enabled(if: w3faIsLinux, "blocked: linux (glibc VEOL2 index)"))
    func w3fa001LinuxRawModeKeepsAuthoredVEOL2() throws {
      #if canImport(Glibc)
        try withSetHPTY { pty in
          var authored = try setHAttributes(pty.slave)
          withUnsafeMutableBytes(of: &authored.c_cc) { controls in
            unsafe controls[Int(VEOL2)] = 0x07
          }
          try #require(unsafe tcsetattr(pty.slave, TCSANOW, &authored) == 0)
          let controller = POSIXTerminalController()
          let snapshot = try controller.enterRawMode(input: pty.slave, output: pty.slave)
          let raw = setHControlCharacters(try setHAttributes(pty.slave))
          try controller.restore(snapshot, input: pty.slave, output: pty.slave)
          let restored = setHControlCharacters(try setHAttributes(pty.slave))
          #expect(raw[Int(VEOL2)] == 0x07, "\(raw)")
          #expect(raw[Int(VMIN)] == 1)
          #expect(raw[Int(VTIME)] == 0)
          #expect(restored[Int(VEOL2)] == 0x07, "\(restored)")
        }
      #endif
    }

    // w3fa002: a non-positive `maxBytes` returns [] at once and leaves input
    // pending (TerminalPOSIXController.swift:51-55, 246-248). The empty case
    // runs in a child whose alarm bounds a call that would otherwise block.
    @Test func w3fa002NegativeMaxBytesReadReturnsAtOnce() async throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      try pipe.send([0x41])
      let controller = POSIXTerminalController()
      #expect(try controller.read(from: pipe.readEnd, maxBytes: -1, timeoutMilliseconds: -1) == [])
      #expect(
        try controller.read(from: pipe.readEnd, maxBytes: 1, timeoutMilliseconds: 0) == [0x41])
      await #expect(processExitsWith: .success) {
        alarm(5)
        let empty = try SetHPipe()
        defer { empty.closeAll() }
        let bytes = try POSIXTerminalController().read(
          from: empty.readEnd, maxBytes: -1, timeoutMilliseconds: -1)
        #expect(bytes == [])
      }
    }

    // w3fa003: the extreme timeout clamps to poll(2)'s int range instead of
    // trapping (TerminalPOSIXController.swift:255-262; setH009's neighbour).
    @Test func w3fa003IntMaxTimeoutReadsAvailableData() async {
      await #expect(processExitsWith: .success) {
        let pipe = try SetHPipe()
        defer { pipe.closeAll() }
        try pipe.send([0x41])
        let bytes = try POSIXTerminalController().read(
          from: pipe.readEnd, maxBytes: 1, timeoutMilliseconds: Int.max)
        #expect(bytes == [0x41])
      }
    }

    // w3fa004: "a request for zero (or fewer) bytes" transfers nothing, and a
    // non-positive drain budget neither finishes nor consumes input
    // (TerminalInputStreamReading.swift:78-89, 114-118).
    @Test func w3fa004NegativeChunkRequestAndDrainBudgetTransferNothing() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      try pipe.send([0x41])
      #expect(readTerminalInputChunk(from: pipe.readEnd, maxBytes: -1) == .bytes([]))
      #expect(
        drainAvailableTerminalInput(from: pipe.readEnd, maxBytesPerRead: -1)
          == TerminalInputDrainResult(bytes: [], shouldFinish: false))
      #expect(readTerminalInputChunk(from: pipe.readEnd, maxBytes: 1) == .bytes([0x41]))
    }

    // w3fa007: a regular-file presentation owner refuses its own file opened
    // again as a separate description (same st_dev/st_ino), and admits a
    // different file (fw3-a decision table; DiagnosticScreenOwnership.swift:73-78).
    @Test func w3fa007RegularFileOwnerRefusesItsOwnFileOpenedAgain() throws {
      let path = NSTemporaryDirectory() + "w3fa007-" + UUID().uuidString + ".out"
      let other = NSTemporaryDirectory() + "w3fa007-" + UUID().uuidString + ".log"
      let owner = path.withCString { unsafe open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o600) }
      let again = path.withCString { unsafe open($0, O_WRONLY | O_APPEND) }
      let separate = other.withCString { unsafe open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o600) }
      defer {
        for descriptor in [owner, again, separate] where descriptor >= 0 { _ = close(descriptor) }
        for file in [path, other] { _ = file.withCString { unsafe unlink($0) } }
      }
      try #require(owner >= 0 && again >= 0 && separate >= 0)
      DiagnosticScreenOwnership.acquire(owner)
      defer { DiagnosticScreenOwnership.release(owner) }
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: again))
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: separate))
    }

    // w3fa008: under a pipe owner, a runtime issue streams to the redirected
    // pipe once and is not also deferred (RuntimeIssueSink+Standard.swift:6-41).
    @MainActor
    @Test func w3fa008PipeOwnerStreamsRuntimeIssueOnceWithoutDeferral() throws {
      var owner: [Int32] = [-1, -1]
      var redirected: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      try #require(unsafe pipe(&redirected) == 0)
      defer { for descriptor in owner + redirected { _ = close(descriptor) } }
      let code = "w3fa008.pipeOwner"
      DiagnosticScreenOwnership.acquire(owner[1])
      RuntimeIssueSink.standardError(to: redirected[1]).report(
        RuntimeIssue(severity: .warning, code: code, message: "redirected"))
      DiagnosticScreenOwnership.release(owner[1])
      // Inspect the deferral buffer without consuming other tests' lines.
      let deferred = DeferredRuntimeIssueBuffer.drain()
      for line in deferred where !line.hasPrefix("SwiftTUI runtime issues:") {
        DeferredRuntimeIssueBuffer.append(line)
      }
      let received = w3faReadAvailable(redirected[0])
      #expect(received.components(separatedBy: code).count - 1 == 1, "\(received)")
      #expect(w3faReadAvailable(owner[0]).isEmpty)
      #expect(!deferred.contains { $0.contains(code) }, "\(deferred)")
    }

    // w3fa009: a stream owner refuses only its own file. Two different AF_INET
    // sockets are different files (commit 3af7dd55; fw3-a decision table row
    // "includes a stream | open non-tty, different file | allow").
    @Test func w3fa009InetSocketOwnerAllowsADifferentInetSocket() throws {
      let ownerSocket = socket(AF_INET, w3faStreamSocketType, 0)
      let destination = socket(AF_INET, w3faStreamSocketType, 0)
      var pair: [Int32] = [-1, -1]
      try #require(unsafe socketpair(AF_UNIX, w3faStreamSocketType, 0, &pair) == 0)
      defer {
        for descriptor in [ownerSocket, destination] + pair where descriptor >= 0 {
          _ = close(descriptor)
        }
      }
      try #require(ownerSocket >= 0 && destination >= 0)
      DiagnosticScreenOwnership.acquire(ownerSocket)
      defer { DiagnosticScreenOwnership.release(ownerSocket) }
      // Controls: the owner's own socket is refused; a unix socket is admitted.
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: ownerSocket))
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: pair[0]))
      // STUI-1271 (repaired): macOS identifies a socket by its kernel handle.
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: destination))
    }

    // STUI-1271 neighbours of w3fa009: two sockets are two files whatever
    // their families and types, so each distinct destination is admitted
    // under each owner (Darwin's fstat(2) reports 0/0 for every inet socket).
    @Test func socketOwnerAllowsEveryDistinctSocket() throws {
      for ownerKind in w3faSocketKinds {
        guard let owner = try w3faSocket(ownerKind) else { continue }
        defer { _ = close(owner) }
        DiagnosticScreenOwnership.acquire(owner)
        defer { DiagnosticScreenOwnership.release(owner) }
        for destinationKind in w3faSocketKinds {
          guard let destination = try w3faSocket(destinationKind) else { continue }
          defer { _ = close(destination) }
          #expect(
            DiagnosticScreenOwnership.allowsDiagnosticWrite(to: destination),
            "\(ownerKind.name) owner, distinct \(destinationKind.name) destination")
        }
      }
    }

    // The owner's own socket stays refused through every descriptor of it:
    // the acquired one and a dup(2), which shares the open socket.
    @Test func socketOwnerRefusesItsOwnSocketThroughEveryDescriptor() throws {
      for kind in w3faSocketKinds {
        guard let owner = try w3faSocket(kind) else { continue }
        let duplicate = dup(owner)
        defer {
          for descriptor in [owner, duplicate] where descriptor >= 0 { _ = close(descriptor) }
        }
        try #require(duplicate >= 0)
        DiagnosticScreenOwnership.acquire(owner)
        defer { DiagnosticScreenOwnership.release(owner) }
        #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: owner), "\(kind.name)")
        #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: duplicate), "\(kind.name) dup")
      }
    }
  }
#endif

// MARK: - FW3-B: table widths, clip masks, projected bindings

@MainActor
@Suite(.serialized)
struct Wave3HuntFATableClipBindingTests {
  // w3fa011: a scroll-hosted table whose width hugs its columns widens when
  // row20x scrolls in, and the armed layout shadow agrees (SOUNDNESS-ORACLES.md
  // layout-shadow-divergence; LayoutShadowOracle.swift:182-192).
  @Test func w3fa011HuggingScrollHostedTableWidensWithoutShadowDivergence() async {
    let result = await #expect(
      processExitsWith: .success, observing: [\.standardErrorContent]
    ) {
      try await MainActor.run {
        SoundnessProbeConfiguration.isEnabled = true
        SoundnessProbeConfiguration.sampleEveryNFrames = 1
        let before = SoundnessProbeConfiguration.layoutShadowDivergenceCount
        let h = try W3FATable.harness("w3fa011", rows: W3FATable.wideRows(at: 20), shape: .hugging)
        defer { h.shutdown() }
        let reached = try W3FATable.wheel(h, until: { $0.contains("row21") })
        #expect(reached, "\(h.frame)")
        #expect(
          SoundnessProbeConfiguration.layoutShadowDivergenceCount == before,
          "\(SoundnessProbeConfiguration.lastViolationDetailByKind["layout-shadow-divergence"] ?? "")"
        )
      }
    }
    if let result, result.exitStatus != .exitCode(EXIT_SUCCESS) {
      print(
        "w3fa011 child stderr: \(String(decoding: result.standardErrorContent.suffix(1_500), as: UTF8.self))"
      )
    }
  }

  // w3fa012: the same hugging table shows the widened column whole: one table
  // line shape, row20x untruncated, unchanged after a re-render
  // (Collections.md:133-138). The shadow is w3fa011's subject, so it is off here.
  @Test func w3fa012HuggingScrollHostedTableShowsTheWidenedColumnWhole() throws {
    let saved = SoundnessProbeConfiguration.isEnabled
    SoundnessProbeConfiguration.isEnabled = false
    defer { SoundnessProbeConfiguration.isEnabled = saved }
    let h = try W3FATable.harness("w3fa012", rows: W3FATable.wideRows(at: 20), shape: .hugging)
    defer { h.shutdown() }
    try #require(try W3FATable.wheel(h, until: { $0.contains("row21") }), "\(h.frame)")
    let frame = h.frame
    let rerendered = try h.render()
    #expect(frame.contains("row20x") && !frame.contains("row2…"), "\(frame)")
    #expect(W3FATable.tableLineShapes(frame).count == 1, "\(frame)")
    #expect(
      W3FATable.tableLineShapes(rerendered) == W3FATable.tableLineShapes(frame), "\(rerendered)")
  }

  // w3fa013: each automatic column keeps its own high-water width: only the
  // column holding the wider value widens (Collections.md:133-138).
  @Test func w3fa013TwoColumnTableWidensOnlyTheWiderColumn() throws {
    var rows = W3FATable.rows(30)
    rows[20].detail = "v20wide"
    let h = try W3FATable.harness("w3fa013", rows: rows, shape: .twoColumn)
    defer { h.shutdown() }
    let initial = W3FATable.firstRuleAfter("row01", in: h.frame)
    try #require(try W3FATable.wheel(h, until: { $0.contains("row21") }), "\(h.frame)")
    let widened = W3FATable.firstRuleAfter("row21", in: h.frame)
    #expect(h.frame.contains("v20wide") && !h.frame.contains("v2…"), "\(h.frame)")
    #expect(!h.frame.contains("row2…"), "\(h.frame)")
    #expect(
      initial != nil && initial == widened,
      "\(String(describing: initial)) → \(String(describing: widened))\n\(h.frame)")
    #expect(W3FATable.tableLineShapes(h.frame).count == 1, "\(h.frame)")
  }

  // w3fa014: a keyboard End into a wide last row shows it untruncated
  // (Collections.md:133-138). Correction C2: in a scroll-hosted collection the
  // first End stops short of the far edge (a table does not move at all; also
  // with FW3-B or FW3-E reverted, so outside this part's scope), so the case
  // presses End until the far edge is reached.
  @Test func w3fa014KeyboardEndRevealsTheWideLastRowWhole() throws {
    var rows = W3FATable.rows(30)
    rows[29].id = "row29x"
    let h = try W3FATable.harness("w3fa014", rows: rows, shape: .plain)
    defer { h.shutdown() }
    _ = try h.clickText("row01")
    _ = try h.pressKey(.init(.end))
    _ = try h.pressKey(.init(.end))
    let frame = try h.render()
    #expect(frame.contains("row29x"), "\(frame)")
    #expect(!frame.contains("row2…"), "\(frame)")
  }

  // w3fa015: two-axis scroll hosting widens like vertical hosting.
  @Test func w3fa015TwoAxisScrollHostedTableWidensItsColumn() throws {
    let h = try W3FATable.harness("w3fa015", rows: W3FATable.wideRows(at: 20), shape: .twoAxis)
    defer { h.shutdown() }
    try #require(try W3FATable.wheel(h, until: { $0.contains("row21") }), "\(h.frame)")
    #expect(h.frame.contains("row20x"), "\(h.frame)")
    #expect(!h.frame.contains("row2…"), "\(h.frame)")
  }

  // w3fa016: a clip mask follows the fill of the same shape under a bouncy
  // spring (Shapes.md:125-127).
  @Test func w3fa016ClipMaskFollowsTheFillUnderASpring() throws {
    let animation = Animation.spring(duration: .milliseconds(400), bounce: 0.3)
    var fillAt150 = 0.0
    for milliseconds in [60, 150, 400] {
      let fill = try W3FAMorph.sampledWidth(.fill, animation: animation, at: milliseconds)
      let clip = try W3FAMorph.sampledWidth(.clip, animation: animation, at: milliseconds)
      if milliseconds == 150 { fillAt150 = fill }
      #expect(abs(fill - clip) < 1e-9, "\(milliseconds) ms: fill \(fill), clip \(clip)")
    }
    #expect(
      fillAt150 > 0.2 && abs(fillAt150 - 1) > 1e-6, "the fill must be mid-flight: \(fillAt150)")
  }

  // w3fa017: retargeted mid-flight, a clip mask still follows the fill.
  @Test func w3fa017ClipMaskFollowsTheFillThroughARetarget() throws {
    let first = Animation.linear(duration: .milliseconds(200))
    let second = Animation.linear(duration: .milliseconds(200))
    for milliseconds in [150, 300] {
      let fill = try W3FAMorph.sampledWidth(
        .fill, animation: first, at: milliseconds, retarget: (0.5, second, 100))
      let clip = try W3FAMorph.sampledWidth(
        .clip, animation: first, at: milliseconds, retarget: (0.5, second, 100))
      #expect(abs(fill - clip) < 1e-9, "\(milliseconds) ms: fill \(fill), clip \(clip)")
    }
  }

  // w3fa018: an implicit `.animation(_:value:)` morphs the clip mask: at 500 of
  // 1000 ms it paints like a static clip at fraction 0.625 (Shapes.md:125-127).
  @Test func w3fa018ImplicitAnimationMorphsTheClipMask() throws {
    let log = W3FAClipLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fa018"), size: .init(width: 20, height: 4)
    ) { W3FAImplicitClipRoot(log: log) }
    defer { h.shutdown() }
    try #require(W3FAMorph.maxPaintedX(in: h.frame) == 4, "\(h.frame)")
    let controller = h.runLoop.renderer.internalAnimationController
    let clock = W3FAClock()
    h.runLoop.frameClock = { clock.now }
    let binding = try #require(log.fraction)
    let extent = try withAnimationSinks(controller) { () throws -> Int in
      binding.wrappedValue = 1.0
      _ = try h.render()
      let target = clock.now.advanced(by: .milliseconds(500))
      var turns = 0
      while let wake = h.runLoop.scheduler.nextWakeInstant(after: clock.now), wake < target,
        turns < 256
      {
        clock.now = wake
        _ = try h.render()
        turns += 1
      }
      clock.now = target
      h.runLoop.scheduler.requestDeadline(clock.now)
      _ = try h.render()
      return W3FAMorph.maxPaintedX(in: h.frame)
    }
    let midway = W3FAMorph.staticClipExtent(fraction: 0.625)
    #expect(midway > 4 && midway < 19, "\(midway)")
    #expect(extent == midway, "implicit morph \(extent) vs static \(midway)")
  }

  // w3fa019: a reader of a collection-element binding of a state is named like
  // a member projection (Logging-And-Diagnostics.md:213-214; CHANGELOG.md:46-47).
  @Test func w3fa019CollectionElementBindingReadersAreNamed() throws {
    let log = W3FADiagnosticLog()
    let h = try BodyChangeOutput.$sink.withValue(log.sink) {
      try StressRuntimeHarness(
        rootIdentity: testIdentity("w3fa019"), size: .init(width: 30, height: 6)
      ) { W3FAElementDiagnosticRoot(log: log) }
    }
    defer { h.shutdown() }
    let items = try #require(log.items)
    log.records.removeAll()
    try BodyChangeOutput.$sink.withValue(log.sink) {
      items.wrappedValue[0].count = 7
      _ = try h.render()
    }
    #expect(
      h.frame.contains("e 7") && h.frame.contains("p 7") && h.frame.contains("k 7"), "\(h.frame)")
    #if DEBUG
      // Control: the key-path projection is a member projection and is named.
      #expect(log.namedCauses("W3FAKeyPathReader") == ["_value"], "\(log.records)")
      let element = log.namedCauses("W3FAElementReader")
      let positional = log.namedCauses("W3FAPositionalReader")
      w3faKnown(
        "NEW-2: _printChanges/_logChanges name no property for a reader of a collection-element binding of a state (ForEach($items) row bindings and $items[0]): the state/exact cause carries property nil; mechanism: projectedElementBinding (ForEachBinding.swift:84-145) and Binding's positional Collection subscript (BindingCollection.swift:42-51) copy the transaction and value identity but not bindingSourceID, so bodyDebugStateSlot's derivationRoot (State.swift:847) has no source to peel; contract: Logging-And-Diagnostics.md:213-214, CHANGELOG.md:46-47; adjacent STUI-1131"
      ) {
        #expect(element == ["_value"], "\(element)")
        #expect(positional == ["_value"], "\(positional)")
      }
    #else
      #expect(log.records.isEmpty)
    #endif
  }

  // w3fa020: derived bindings keep their source chain: `.animation()` and the
  // optional-unwrapping `Binding(_:)` (ViewBaseTypes.swift:90-113, 171-176).
  @Test func w3fa020DerivedBindingReadersAreNamed() throws {
    let log = W3FADiagnosticLog()
    let h = try BodyChangeOutput.$sink.withValue(log.sink) {
      try StressRuntimeHarness(
        rootIdentity: testIdentity("w3fa020"), size: .init(width: 30, height: 6)
      ) { W3FADerivedDiagnosticRoot(log: log) }
    }
    defer { h.shutdown() }
    let model = try #require(log.model)
    log.records.removeAll()
    try BodyChangeOutput.$sink.withValue(log.sink) {
      model.wrappedValue.count = 7
      _ = try h.render()
    }
    #expect(h.frame.contains("a 7"), "\(h.frame)")
    #if DEBUG
      #expect(log.namedCauses("W3FAAnimatedReader") == ["_value"], "\(log.records)")
    #endif
    log.records.removeAll()
    try BodyChangeOutput.$sink.withValue(log.sink) {
      model.wrappedValue.maybe = 7
      _ = try h.render()
    }
    #expect(h.frame.contains("u 7"), "\(h.frame)")
    #if DEBUG
      #expect(log.namedCauses("W3FAUnwrappedReader") == ["_value"], "\(log.records)")
    #else
      #expect(log.records.isEmpty)
    #endif
  }
}

// MARK: - FW3-C: wholly offscreen lazy stacks and invalidation summaries

@MainActor
@Suite(.serialized)
struct Wave3HuntFALazyInvalidationTests {
  // w3fa021: a claim-denied lazy stack wholly ABOVE the viewport places no
  // rows either (LayoutEngine+StackLazyAllocation.swift:72-82).
  @Test func w3fa021WhollyAboveClaimDeniedStackPlacesNoRows() throws {
    let below = try W3FALazy.placedStacks(W3FAPositionedStacks(offset: 0), name: "w3fa021-below")
    let above = try W3FALazy.placedStacks(W3FAPositionedStacks(offset: 16), name: "w3fa021-above")
    try #require(below.stacks.count == 2 && above.stacks.count == 2)
    // Control: the group's wholly-below case.
    #expect(below.stacks[1].children.count == 0)
    #expect(above.text.contains("tail"), "\(above.text)")
    #expect(above.stacks[1].children.count == 0, "placed \(above.stacks[1].children.count)")
    #expect(above.stacks[0].children.count == 0, "placed \(above.stacks[0].children.count)")
  }

  // w3fa022: a proxy command reaches a row of a wholly offscreen claim-denied
  // stack, as it reaches an unrealized row of the windowed one
  // (ScrollViewReader.swift:33-43; Scrolling.md:216-219).
  @Test func w3fa022ProxyScrollReachesAWhollyOffscreenClaimDeniedRow() async throws {
    // The first unmarked run trapped the whole process in this fixture's
    // harness init (layout-shadow-divergence at the windowed first stack), so
    // the armed launch runs in a child and the proxy contract runs disarmed.
    await w3faKnownAsync(
      "NEW-3: a scroll view below a header whose windowed lazy stack has rows wider than its first window traps at launch on the DEBUG layout-shadow oracle (measure divergence at the lazy stack: production width 10 over all 20 rows, shadow 9 over the window, proposal 40x0); mechanism: the scroll layout's zero-height first round makes the stack measure exhaustively and the hint-agnostic measurement cache (MeasurementCache.swift:4) serves that product to the finite rounds, while the fresh shadow windows; LayoutShadowOracle excludes only products carrying a measuredWindow, and the exhaustive product's cross-axis width differs; FW3-C recorded the cache asymmetry as placement-equivalent only; traps before and after fc86adcc; contract: SOUNDNESS-ORACLES.md layout-shadow-divergence, STUI-1231 (launch trap removed); adjacent STUI-1231"
    ) {
      await #expect(processExitsWith: .success) {
        try await MainActor.run {
          SoundnessProbeConfiguration.isEnabled = true
          SoundnessProbeConfiguration.sampleEveryNFrames = 1
          let h = try StressRuntimeHarness(
            rootIdentity: testIdentity("w3fa022-armed"), size: .init(width: 40, height: 8)
          ) { W3FATwoStacks(firstCount: 20, log: W3FAStackLog()) }
          h.shutdown()
        }
      }
    }
    let saved = SoundnessProbeConfiguration.isEnabled
    SoundnessProbeConfiguration.isEnabled = false
    defer { SoundnessProbeConfiguration.isEnabled = saved }
    let log = W3FAStackLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fa022"), size: .init(width: 40, height: 8)
    ) { W3FATwoStacks(firstCount: 20, log: log) }
    defer { h.shutdown() }
    let proxy = try #require(log.proxy)
    try #require(!h.frame.contains("second"), "\(h.frame)")
    // Control: an unrealized row of the windowed first stack.
    proxy.scrollTo("first 15")
    let windowed = try h.render()
    #expect(windowed.contains("first 15"), "\(windowed)")
    try #require(!windowed.contains("second"), "\(windowed)")
    proxy.scrollTo("second 3")
    let claimDenied = try h.render()
    #expect(claimDenied.contains("second 3"), "\(claimDenied)")
  }

  // w3fa023: focus on a row of the claim-denied stack survives scrolling the
  // stack wholly offscreen and back (Scrolling.md:212-224, "Focus and
  // scrolling stay independent"; 0.19.3 placed the stack's rows offscreen).
  // Correction C1: the windowed control's focus expectations were dropped;
  // an unrealized windowed row falls back to the scroll view, which the same
  // paragraph also allows ("unavailable controls use normal fallback").
  @Test func w3fa023FocusedClaimDeniedRowSurvivesScrollingAway() throws {
    let log = W3FAStackLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fa023"), size: .init(width: 40, height: 8)
    ) { W3FATwoStacks(firstCount: 4, log: log) }
    defer { h.shutdown() }
    // The windowed first stack scrolled wholly away and back first.
    _ = try h.focusText("first 1")
    let firstFocus = h.runLoop.focusTracker.currentFocusIdentity
    try #require(firstFocus != nil)
    try #require(try W3FALazy.wheel(h, until: { $0.contains("tail 2") }), "\(h.frame)")
    #expect(!h.frame.contains("first"), "\(h.frame)")
    try #require(
      try W3FALazy.wheel(h, deltaY: -1, until: { $0.contains("first 0") }), "\(h.frame)")

    // Subject: the claim-denied second stack.
    try #require(try W3FALazy.wheel(h, until: { $0.contains("second 4") }), "\(h.frame)")
    _ = try h.focusText("second 1")
    let secondFocus = h.runLoop.focusTracker.currentFocusIdentity
    try #require(secondFocus != nil && secondFocus != firstFocus)
    try #require(
      try W3FALazy.wheel(h, deltaY: -1, until: { $0.contains("first 0") }), "\(h.frame)")
    #expect(!h.frame.contains("second"), "\(h.frame)")
    let whileAway = h.runLoop.focusTracker.currentFocusIdentity
    try #require(try W3FALazy.wheel(h, until: { $0.contains("second 4") }), "\(h.frame)")
    let afterReturn = h.runLoop.focusTracker.currentFocusIdentity
    #expect(whileAway == secondFocus, "focus moved to \(String(describing: whileAway))")
    #expect(afterReturn == secondFocus, "focus moved to \(String(describing: afterReturn))")
  }

  // w3fa024: a viewport shrink that leaves a focused claim-denied row wholly
  // below the viewport reveals it, as for the windowed stack
  // (Scrolling.md:216-219; ARCHITECTURE.md:115-116).
  @Test func w3fa024ViewportShrinkRevealsAFocusedClaimDeniedRow() throws {
    // Control: a windowed row.
    let controlLog = W3FAStackLog()
    let control = try W3FAResizeHarness(name: "w3fa024-control", size: .init(width: 40, height: 16))
    {
      W3FATwoStacks(firstCount: 4, log: controlLog)
    }
    defer { control.shutdown() }
    try control.focusText("first 3")
    let controlFocus = control.loop.focusTracker.currentFocusIdentity
    try control.resize(width: 40, height: 3)
    #expect(control.frame.contains("first 3"), "\(control.frame)")
    #expect(control.loop.focusTracker.currentFocusIdentity == controlFocus)

    let log = W3FAStackLog()
    let h = try W3FAResizeHarness(name: "w3fa024", size: .init(width: 40, height: 16)) {
      W3FATwoStacks(firstCount: 4, log: log)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("second 2"), "\(h.frame)")
    try h.focusText("second 2")
    let focus = h.loop.focusTracker.currentFocusIdentity
    try #require(focus != nil)
    try h.resize(width: 40, height: 6)
    let frame = h.frame
    let after = h.loop.focusTracker.currentFocusIdentity
    w3faKnown(
      "NEW-4: a viewport shrink that leaves a focused row of a claim-denied (exhaustive) lazy stack wholly below the viewport neither reveals it nor keeps its focus: focus falls back to the scroll view; mechanism: lazyStackVisibleChildRange returns 0..<0 for the wholly offscreen stack (LayoutEngine+StackLazyAllocation.swift:124-128, fc86adcc), so the focused row is no longer placed and the focus-sync reveal that realizes a windowed row from its allocation estimate does not reach it; 0.19.3 placed the row offscreen and kept focus (bisect); contract: Scrolling.md:216-219, ARCHITECTURE.md:115-116; adjacent STUI-1231"
    ) {
      #expect(frame.contains("second 2"), "\(frame)")
      #expect(after == focus, "focus moved to \(String(describing: after))")
    }
  }

  // w3fa025: a claim-denied LazyHStack wholly right of its viewport places no
  // cells, and places them once scrolled into view.
  @Test func w3fa025WhollyOffscreenLazyHStackPlacesNoCells() throws {
    let start = try W3FALazy.placedStacks(
      W3FAHorizontalStacks(offset: 0), name: "w3fa025-start", width: 20, height: 2)
    let end = try W3FALazy.placedStacks(
      W3FAHorizontalStacks(offset: 40), name: "w3fa025-end", width: 20, height: 2)
    try #require(start.stacks.count == 2 && end.stacks.count == 2)
    #expect(start.stacks[1].children.count == 0, "placed \(start.stacks[1].children.count)")
    #expect(end.stacks[1].children.count > 0)
    #expect(end.text.contains("b4"), "\(end.text)")
  }

  // w3fa026: offscreen claim-denied rows are not exposed; once revealed they
  // are, and activation runs their action (Accessibility.md:131-132).
  @Test func w3fa026ClaimDeniedRowsAreExposedOnlyOnceRevealed() throws {
    let log = W3FAStackLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fa026"), size: .init(width: 40, height: 8)
    ) { W3FATwoStacks(firstCount: 4, log: log) }
    defer { h.shutdown() }
    func node(_ label: String) -> AccessibilityNode? {
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == label }
    }
    #expect(node("second 1") == nil)
    try #require(try W3FALazy.wheel(h, until: { $0.contains("second 2") }), "\(h.frame)")
    let revealed = try #require(node("second 1"), "\(h.frame)")
    let target = try #require(revealed.actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate)) == .accepted)
    _ = try h.render()
    #expect(log.activated == ["second 1"])
  }

  // w3fa027: a state write inside a presented sheet and a base write while the
  // sheet is open both reach their readers (ResolveContext.swift:695-706;
  // FrameResolveState.swift:243-264).
  @Test func w3fa027SheetAndBaseWritesReachTheirReaders() throws {
    let log = W3FASheetLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fa027"), size: .init(width: 40, height: 12)
    ) { W3FASheetRoot(log: log) }
    defer { h.shutdown() }
    log.isPresented = true
    let opened = try h.renderAfterExternalMutation()
    try #require(opened.contains("inner 0"), "\(opened)")
    let inner = try #require(log.inner)
    inner.wrappedValue = 5
    let afterInner = try h.render()
    #expect(afterInner.contains("inner 5"), "\(afterInner)")
    let base = try #require(log.base)
    let evaluations = log.baseEvaluations
    base.wrappedValue = 3
    _ = try h.render()
    #expect(log.baseEvaluations > evaluations, "the base did not re-evaluate")
    log.isPresented = false
    let closed = try h.renderAfterExternalMutation()
    #expect(closed.contains("base 3"), "\(closed)")
  }

  // w3fa028: one row's write updates that row; a shared parent write updates
  // every row.
  @Test func w3fa028RowAndParentWritesUpdateExactlyTheirReaders() throws {
    let log = W3FARowsLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fa028"), size: .init(width: 20, height: 41)
    ) { W3FARowsRoot(log: log) }
    defer { h.shutdown() }
    let row = try #require(log.counts[17])
    row.wrappedValue = 1
    let afterRow = try h.render()
    #expect(afterRow.contains("r17 1 0"), "\(afterRow)")
    #expect(afterRow.contains("r16 0 0") && afterRow.contains("r18 0 0"), "\(afterRow)")
    let shared = try #require(log.shared)
    shared.wrappedValue = 5
    let afterShared = try h.render()
    let lines = afterShared.split(separator: "\n").filter { $0.hasPrefix("r") }
    #expect(lines.count == 40, "\(afterShared)")
    #expect(
      lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasSuffix(" 5") }, "\(afterShared)"
    )
    #expect(afterShared.contains("r17 1 5"), "\(afterShared)")
  }
}

// MARK: - FW3-D: departure ordering

@MainActor
@Suite(.serialized)
struct Wave3HuntFADepartureTests {
  // w3fa029: a write to a view present in both graphs (a sibling outside the
  // TabView) during the offloaded relayout survives the switch (Runtime.md:127-131).
  @Test func w3fa029SiblingWriteDuringOffloadedRelayoutSurvivesTheSwitch() async {
    let model = W3FATabModel()
    let probe = W3FAHopProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("w3fa029")
    func render() async -> RenderSnapshot {
      await renderer.renderAsync(
        W3FAHopFixture(model: model, probe: probe), context: w3faContext(root))
    }
    #expect(w3faText(await render()).contains("S count 0"))
    let gates = W3FAHopGates(renderer: renderer, realized: probe.realized)
    defer { gates.releaseAll() }
    model.selection = "B"
    let finished = AsyncEvent()
    let switchTask = Task { @MainActor in
      let snapshot = await render()
      finished.fire()
      return snapshot
    }
    let blocked = await firstFrameTailSignal(blocked: gates.layout, orFinished: finished)
    #expect(blocked, "the arriving GeometryReader relayout never left the main actor")
    guard blocked else {
      gates.releaseAll()
      _ = await switchTask.value
      return
    }
    probe.writeSibling?(1)
    let duringHop = probe.readSibling?()
    gates.layout.release()
    await gates.raster.waitUntilBlocked()
    let duringRaster = probe.readSibling?()
    gates.raster.release()
    let switched = await switchTask.value
    gates.releaseAll()
    let after = await render()
    #expect(duringHop == 1)
    #expect(duringRaster == 1)
    #expect(w3faText(switched).contains("B width"), "\(w3faText(switched))")
    #expect(probe.readSibling?() == 1)
    #expect(w3faText(after).contains("S count 1"), "\(w3faText(after))")
  }

  // w3fa030: two departing writes during the hop: the newer one wins
  // (ViewGraphFrameDraft.swift:556-565).
  @Test func w3fa030NewestDepartingWriteDuringTheHopWins() async {
    let model = W3FATabModel()
    let probe = W3FAHopProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("w3fa030")
    func render() async -> RenderSnapshot {
      await renderer.renderAsync(
        W3FAHopFixture(model: model, probe: probe), context: w3faContext(root))
    }
    #expect(w3faText(await render()).contains("A count 0"))
    let gates = W3FAHopGates(renderer: renderer, realized: probe.realized)
    defer { gates.releaseAll() }
    model.selection = "B"
    let finished = AsyncEvent()
    let switchTask = Task { @MainActor in
      let snapshot = await render()
      finished.fire()
      return snapshot
    }
    let blocked = await firstFrameTailSignal(blocked: gates.layout, orFinished: finished)
    #expect(blocked)
    guard blocked else {
      gates.releaseAll()
      _ = await switchTask.value
      return
    }
    probe.writeDeparting?(1)
    probe.writeDeparting?(2)
    let duringHop = probe.readDeparting?()
    gates.layout.release()
    await gates.raster.waitUntilBlocked()
    let duringRaster = probe.readDeparting?()
    gates.raster.release()
    _ = await switchTask.value
    #expect(duringHop == 2)
    #expect(duringRaster == 2)
  }

  // w3fa031: with no owner retired the prepared graph stays live through the
  // offloaded relayout, and a sibling write survives (FrameHeadDraftTransaction.swift:185-205).
  @Test func w3fa031SiblingWriteSurvivesARelayoutThatRetiresNothing() async {
    let model = W3FATabModel()
    let probe = W3FAHopProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("w3fa031")
    func render() async -> RenderSnapshot {
      await renderer.renderAsync(
        W3FAArrivingGeometryFixture(model: model, probe: probe), context: w3faContext(root))
    }
    #expect(w3faText(await render()).contains("S count 0"))
    let gates = W3FAHopGates(renderer: renderer, realized: probe.realized)
    defer { gates.releaseAll() }
    model.showsGeometry = true
    let finished = AsyncEvent()
    let showTask = Task { @MainActor in
      let snapshot = await render()
      finished.fire()
      return snapshot
    }
    let blocked = await firstFrameTailSignal(blocked: gates.layout, orFinished: finished)
    #expect(blocked, "the GeometryReader relayout never left the main actor")
    guard blocked else {
      gates.releaseAll()
      _ = await showTask.value
      return
    }
    probe.writeSibling?(1)
    gates.layout.release()
    await gates.raster.waitUntilBlocked()
    let duringRaster = probe.readSibling?()
    gates.raster.release()
    let shown = await showTask.value
    gates.releaseAll()
    let after = await render()
    #expect(duringRaster == 1)
    #expect(w3faText(shown).contains("G width"), "\(w3faText(shown))")
    #expect(w3faText(after).contains("S count 1"), "\(w3faText(after))")
  }

  // w3fa032: a `.task(id:)` restart in a pass that moves focus cancels the
  // old task at the commit and starts exactly one new task (Runtime.md:119-122).
  @Test func w3fa032TaskIDRestartInAFocusMovingPassCancelsAtTheCommit() async throws {
    let model = W3FATaskIDModel()
    let probe = W3FATaskProbe()
    let root = testIdentity("w3fa032")
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 30, height: 6)) {
      W3FATaskIDFixture(model: model, probe: probe)
    }
    defer { h.shutdown() }
    await probe.readyEvent(generation: 1).wait()
    _ = try h.focusText("Next")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    h.runLoop.renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      h.runLoop.renderer.setFrameTailRenderHooks(nil)
    }
    model.generation = 1
    h.runLoop.scheduler.requestInvalidation(of: [root])
    let finished = AsyncEvent()
    let renderTask = Task { @MainActor in
      var frames = 0
      _ = try await h.runLoop.renderPendingFramesAsync(
        renderedFrames: &frames, eventPump: w3faEmptyPump(W3FATaskIDFixture.self))
      finished.fire()
    }
    let blocked = await firstFrameTailSignal(blocked: gate, orFinished: finished)
    var endedAtHold: [Int] = []
    var cancelledAtHold: [Int] = []
    if blocked {
      await probe.tick().wait()
      endedAtHold = probe.endedGenerations
      cancelledAtHold = probe.cancellationObserved
    }
    gate.release()
    try await renderTask.value
    _ = try h.render()
    let running = h.activeTaskCount
    if running == 1 {
      await probe.readyEvent(generation: 2).wait()
    }
    #expect(blocked, "removing the focused button did not re-render for focus")
    #expect(endedAtHold == [1], "\(endedAtHold)")
    #expect(cancelledAtHold == [1])
    #expect(running == 1)
    #expect(probe.taskStarts == 2)
    #expect(probe.endedGenerations == [1])
  }

  // w3fa033: the departing task is cancelled by the time the focus-moving
  // switch is held, and before its disappear handler runs, which runs once
  // (Runtime.md:117, 120-126). Correction C3: the hold is not reliably the
  // focus re-render (an elided re-render runs the carried handlers at once,
  // as the rules allow), so the handler's own view of the task registry
  // carries the cancel-before-disappear order.
  @Test func w3fa033DepartingTaskCancelsBeforeItsDisappearHandler() async throws {
    let model = W3FATabModel()
    let probe = W3FATaskProbe()
    let root = testIdentity("w3fa033")
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 48, height: 10)) {
      W3FADepartingTaskFixture(model: model, probe: probe)
    }
    defer { h.shutdown() }
    probe.activeTasks = { h.activeTaskCount }
    await probe.readyEvent(generation: 1).wait()
    _ = try h.focusText("Bump")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    h.runLoop.renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      h.runLoop.renderer.setFrameTailRenderHooks(nil)
    }
    model.selection = "B"
    h.runLoop.scheduler.requestInvalidation(of: [root])
    let finished = AsyncEvent()
    let renderTask = Task { @MainActor in
      var frames = 0
      _ = try await h.runLoop.renderPendingFramesAsync(
        renderedFrames: &frames, eventPump: w3faEmptyPump(W3FADepartingTaskFixture.self))
      finished.fire()
    }
    let blocked = await firstFrameTailSignal(blocked: gate, orFinished: finished)
    var endedAtHold: [Int] = []
    var cancelledAtHold: [Int] = []
    if blocked {
      await probe.tick().wait()
      endedAtHold = probe.endedGenerations
      cancelledAtHold = probe.cancellationObserved
    }
    gate.release()
    try await renderTask.value
    #expect(blocked, "the tab switch did not re-render for focus")
    #expect(endedAtHold == [1])
    #expect(cancelledAtHold == [1])
    #expect(probe.disappears == 1)
    #expect(probe.activeTasksAtDisappear == [0], "\(probe.activeTasksAtDisappear)")
  }

  // w3fa034: the open's carried task never runs against the palette body the
  // next frame dismissed, and no task outlives the dismissal (Runtime.md:117-126).
  @Test func w3fa034CarriedPaletteTaskNeverRunsAgainstTheDismissedBody() async throws {
    let model = PaletteAppearModel()
    let probe = W3FAPaletteProbe()
    let root = testIdentity("w3fa034")
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 60, height: 16)) {
      W3FAPaletteFixture(model: model, probe: probe)
    }
    defer { h.shutdown() }
    let baseline = h.activeTaskCount
    let blocked = try await w3faOpenAndDismissDuringFocusRerender(
      harness: h, root: root, setPresented: { model.isPresented = $0 },
      beforeOpen: { probe.opens = 1 })
    _ = try h.render()
    let afterDismissal = h.activeTaskCount
    let firstLifetimeStarts = probe.taskStarts.filter { $0.open == 1 }
    probe.opens = 2
    model.isPresented = true
    #expect(try h.renderAfterExternalMutation().contains("Probe filter"))
    if h.activeTaskCount > baseline {
      await probe.startedEvent(open: 2).wait()
    }
    let secondLifetimeStarts = probe.taskStarts.filter { $0.open == 2 }
    model.isPresented = false
    _ = try h.renderAfterExternalMutation()
    #expect(blocked, "opening the palette never reached its frame tail")
    let firstLifetimeLanded = firstLifetimeStarts.allSatisfy { $0.landed }
    #expect(firstLifetimeLanded, "\(firstLifetimeStarts)")
    #expect(afterDismissal == baseline, "a task outlived the dismissal")
    let secondLifetimeLanded = secondLifetimeStarts.allSatisfy { $0.landed }
    #expect(secondLifetimeStarts.count == 1 && secondLifetimeLanded, "\(secondLifetimeStarts)")
    #expect(h.activeTaskCount == baseline)
  }

  // w3fa035: a sheet whose open moves focus, dismissed while its frame is held,
  // still runs every appear on a live owner (Runtime.md:123-126).
  @Test func w3fa035SheetAppearCarriedPastAHeldOpenRunsWhileMounted() async throws {
    let model = PaletteAppearModel()
    let probe = W3FASheetProbe()
    let root = testIdentity("w3fa035")
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 60, height: 16)) {
      W3FASheetFixture(model: model, probe: probe)
    }
    defer { h.shutdown() }
    let coordinator = h.runLoop.lifecycleCoordinator
    let appearSkips = coordinator.appearHandlerSkipCount
    let blocked = try await w3faOpenAndDismissDuringFocusRerender(
      harness: h, root: root, setPresented: { model.isPresented = $0 },
      beforeOpen: { probe.opens = 1 })
    probe.opens = 2
    model.isPresented = true
    #expect(try h.renderAfterExternalMutation().contains("sheet body"))
    model.isPresented = false
    _ = try h.renderAfterExternalMutation()
    #expect(blocked, "opening the sheet never reached its frame tail")
    #expect(probe.appears == [1, 2], "\(probe.appears)")
    #expect(probe.appearLanded == [true, true], "\(probe.appearLanded)")
    #expect(probe.disappears == 2)
    #expect(coordinator.appearHandlerSkipCount == appearSkips)
  }

  // w3fa036: under the superseded focus re-render the carried appear runs
  // before the carried initial change (Runtime.md:102-104, 118).
  @Test func w3fa036CarriedAppearPrecedesTheInitialChange() async throws {
    let model = PaletteAppearModel()
    let probe = W3FAPaletteProbe()
    let root = testIdentity("w3fa036")
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 60, height: 16)) {
      W3FAPaletteFixture(model: model, probe: probe)
    }
    defer { h.shutdown() }
    let blocked = try await w3faOpenAndDismissDuringFocusRerender(
      harness: h, root: root, setPresented: { model.isPresented = $0 },
      beforeOpen: { probe.opens = 1 })
    _ = try h.render()
    let first = probe.events.filter { $0.hasSuffix(" 1") }
    #expect(blocked)
    #expect(Array(first.prefix(2)) == ["appear 1", "change 1"], "\(probe.events)")
  }
}

// MARK: - Cross-group

@MainActor
@Suite(.serialized)
struct Wave3HuntFACrossGroupTests {
  #if canImport(Darwin) || canImport(Glibc)
    // w3fa037: body-change output shares the safe stderr gate: under a pipe
    // owner a record reaches a redirected pipe, nothing reaches the owner and
    // nothing is suppressed (Logging-And-Diagnostics.md:217-222).
    @Test func w3fa037BodyChangeRecordsReachARedirectedPipeUnderAPipeOwner() throws {
      var owner: [Int32] = [-1, -1]
      var redirected: [Int32] = [-1, -1]
      var scratch: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      try #require(unsafe pipe(&redirected) == 0)
      try #require(unsafe pipe(&scratch) == 0)
      defer { for descriptor in owner + redirected + scratch { _ = close(descriptor) } }
      // Clear any suppressed count an earlier test left.
      BodyChangeOutput.flushSuppressed(to: scratch[1])
      _ = w3faReadAvailable(scratch[0])
      DiagnosticScreenOwnership.acquire(owner[1])
      let record = BodyChangeRecord(
        typeName: "W3FAReader", kind: "view",
        causes: [.init("state", precision: "exact", property: "_value")])
      BodyChangeOutput.emitPortable(record, format: .text, descriptor: redirected[1])
      DiagnosticScreenOwnership.release(owner[1])
      BodyChangeOutput.flushSuppressed(to: scratch[1])
      let received = w3faReadAvailable(redirected[0])
      #expect(received.contains("W3FAReader") && received.contains("_value"), "\(received)")
      #expect(w3faReadAvailable(owner[0]).isEmpty)
      #expect(w3faReadAvailable(scratch[0]).isEmpty, "a record was suppressed")
    }
  #endif

  // w3fa038: a widened scroll-hosted table in a tab survives a switch to a
  // layout-dependent tab and back (Collections.md:133-138; Dormant-Tab-State.md:8-12).
  @Test func w3fa038WidenedTableSurvivesALayoutDependentTabSwitch() throws {
    let model = W3FATabModel()
    let box = W3FASelection()
    let rows = W3FATable.wideRows(at: 20)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fa038"), size: .init(width: 24, height: 14)
    ) { W3FATabTableFixture(model: model, rows: rows, selection: box.binding) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "row01"), "\(h.frame)")
    try #require(try W3FATable.wheel(h, at: point, until: { $0.contains("row21") }), "\(h.frame)")
    #expect(h.frame.contains("row20x"), "\(h.frame)")
    model.selection = "B"
    #expect(try h.renderAfterExternalMutation().contains("B width"), "\(h.frame)")
    model.selection = "A"
    _ = try h.renderAfterExternalMutation()
    try #require(try W3FATable.wheel(h, at: point, until: { $0.contains("row21") }), "\(h.frame)")
    #expect(h.frame.contains("row20x"), "\(h.frame)")
    #expect(!h.frame.contains("row2…"), "\(h.frame)")
  }

  // w3fa039: a scroll-hosted table followed by a lazy stack: the table widens
  // when row20x scrolls in, and the wholly-below stack's rows appear once
  // scrolled into view (Collections.md:133-138, 153-156).
  @Test func w3fa039TableThenLazyStackInOneScrollContent() throws {
    let h = try W3FATable.harness("w3fa039", rows: W3FATable.wideRows(at: 20), shape: .lazyTail)
    defer { h.shutdown() }
    #expect(!h.frame.contains("tail"), "\(h.frame)")
    try #require(try W3FATable.wheel(h, until: { $0.contains("row21") }), "\(h.frame)")
    #expect(h.frame.contains("row20x") && !h.frame.contains("row2…"), "\(h.frame)")
    let reached = try W3FATable.wheel(h, limit: 120, until: { $0.contains("tail 1") })
    #expect(reached, "\(h.frame)")
  }

  #if canImport(Darwin) || canImport(Glibc)
    // w3fa040: during an offloaded relayout of an arriving tab, a runtime issue
    // under a pipe owner reaches the redirected pipe at once (CHANGELOG.md:35-36).
    @Test func w3fa040RuntimeIssueDuringAnOffloadedRelayoutReachesRedirectedStderr() async throws {
      var owner: [Int32] = [-1, -1]
      var redirected: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      try #require(unsafe pipe(&redirected) == 0)
      defer { for descriptor in owner + redirected { _ = close(descriptor) } }
      let model = W3FATabModel()
      let probe = W3FAHopProbe()
      let renderer = DefaultRenderer()
      let root = testIdentity("w3fa040")
      func render() async -> RenderSnapshot {
        await renderer.renderAsync(
          W3FAHopFixture(model: model, probe: probe), context: w3faContext(root))
      }
      _ = await render()
      let gates = W3FAHopGates(renderer: renderer, realized: probe.realized)
      defer { gates.releaseAll() }
      model.selection = "B"
      let finished = AsyncEvent()
      let switchTask = Task { @MainActor in
        let snapshot = await render()
        finished.fire()
        return snapshot
      }
      let blocked = await firstFrameTailSignal(blocked: gates.layout, orFinished: finished)
      var received = ""
      if blocked {
        DiagnosticScreenOwnership.acquire(owner[1])
        RuntimeIssueSink.standardError(to: redirected[1]).report(
          RuntimeIssue(severity: .warning, code: "w3fa040.hop", message: "during the hop"))
        DiagnosticScreenOwnership.release(owner[1])
        received = w3faReadAvailable(redirected[0])
      }
      gates.releaseAll()
      _ = await switchTask.value
      #expect(blocked)
      #expect(received.contains("w3fa040.hop"), "\(received)")
      #expect(w3faReadAvailable(owner[0]).isEmpty)
    }
  #endif
}

// MARK: - Table fixtures (w3fa011–015, 038, 039)

struct W3FARow: Identifiable, Hashable, Sendable {
  var id: String
  var detail: String
}

@MainActor
final class W3FASelection {
  var selected: String?
  var binding: Binding<String?> {
    Binding(get: { self.selected }, set: { self.selected = $0 })
  }
}

enum W3FATableShape: Sendable {
  case plain, hugging, twoColumn, twoAxis, lazyTail
}

struct W3FATableHost: View {
  let rows: [W3FARow]
  let selection: Binding<String?>
  let shape: W3FATableShape

  var body: some View {
    switch shape {
    case .plain:
      ScrollView { table }.scrollIndicators(.hidden)
    case .hugging:
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          table.fixedSize(horizontal: true, vertical: false)
        }
      }.scrollIndicators(.hidden)
    case .twoColumn:
      ScrollView {
        Table(
          rows, selection: selection, columns: [TableColumn("Name"), TableColumn("Value")]
        ) { row in
          Text(row.id)
          Text(row.detail)
        }
      }.scrollIndicators(.hidden)
    case .twoAxis:
      ScrollView([.vertical, .horizontal]) { table }.scrollIndicators(.hidden)
    case .lazyTail:
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          table
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
              Text("tail \(index)")
            }
          }
        }
      }.scrollIndicators(.hidden)
    }
  }

  private var table: some View {
    Table(rows, selection: selection, columns: [TableColumn("Name")]) { row in
      Text(row.id)
    }
  }
}

struct W3FATabTableFixture: View {
  let model: W3FATabModel
  let rows: [W3FARow]
  let selection: Binding<String?>

  var body: some View {
    TabView(selection: model.selectionBinding) {
      Tab("A", value: "A") {
        ScrollView {
          Table(rows, selection: selection, columns: [TableColumn("Name")]) { row in
            Text(row.id)
          }
        }.scrollIndicators(.hidden)
      }
      Tab("B", value: "B") {
        GeometryReader { proxy in
          Text("B width \(proxy.size.width)")
        }
      }
    }
  }
}

@MainActor
enum W3FATable {
  /// `row00`…`rowNN`, detail `v00`…
  static func rows(_ count: Int) -> [W3FARow] {
    (0..<count).map { index in
      let digits = index < 10 ? "0\(index)" : "\(index)"
      return W3FARow(id: "row\(digits)", detail: "v\(digits)")
    }
  }

  /// Thirty five-character rows with one six-character row at `index`.
  static func wideRows(at index: Int) -> [W3FARow] {
    var rows = rows(30)
    rows[index].id += "x"
    return rows
  }

  static func harness(_ name: String, rows: [W3FARow], shape: W3FATableShape) throws
    -> StressRuntimeHarness<W3FATableHost>
  {
    let box = W3FASelection()
    return try StressRuntimeHarness(
      rootIdentity: testIdentity(name), size: .init(width: 24, height: 10)
    ) {
      W3FATableHost(rows: rows, selection: box.binding, shape: shape)
    }
  }

  /// One wheel notch at a time over `point` until `done` holds.
  static func wheel<Content: View>(
    _ h: StressRuntimeHarness<Content>, at point: Point = Point(x: 2, y: 5), deltaY: Int = 1,
    limit: Int = 48, until done: (String) -> Bool
  ) throws -> Bool {
    for _ in 0..<limit {
      if done(h.frame) { return true }
      _ = try h.scrollPointer(at: point, deltaY: deltaY)
    }
    return done(h.frame)
  }

  /// Width and vertical-rule columns of every line that carries a rule.
  static func tableLineShapes(_ frame: String) -> Set<String> {
    Set(
      frame.split(separator: "\n").map(String.init).filter { $0.contains("│") }.map { line in
        let trimmed = trimmedTrailing(line)
        let rules = trimmed.enumerated().filter { $0.element == "│" }.map(\.offset)
        return "\(trimmed.count):\(rules)"
      })
  }

  /// The column of the first rule after `text` on the line that carries it.
  static func firstRuleAfter(_ text: String, in frame: String) -> Int? {
    for line in frame.split(separator: "\n").map(String.init) {
      guard let range = line.range(of: text) else { continue }
      let characters = Array(line)
      let start = line.distance(from: line.startIndex, to: range.upperBound)
      return characters.indices.first { $0 >= start && characters[$0] == "│" }
    }
    return nil
  }

  private static func trimmedTrailing(_ line: String) -> String {
    var result = Substring(line)
    while result.last == " " { result.removeLast() }
    return String(result)
  }
}

// MARK: - Clip morph fixtures (w3fa016–018)

@MainActor
enum W3FAMorph {
  enum Kind { case fill, clip }

  static func path(width: Double) -> Path {
    Path(Rect(origin: .zero, size: .init(width: width, height: 1)))
  }

  static func node(_ kind: Kind, width: Double) -> ResolvedNode {
    let geometry = ShapeGeometry.path(BoxedPath(path(width: width)), .nonZero)
    switch kind {
    case .fill:
      return ResolvedNode(
        identity: Identity(components: ["w3fa-morph"]), kind: .view("Path"),
        drawPayload: .shape(.init(geometry: geometry, operation: .fill(style: .color(.white)))))
    case .clip:
      var node = ResolvedNode(
        identity: Identity(components: ["w3fa-clip"]), kind: .view("VStack"),
        children: [
          ResolvedNode(
            identity: Identity(components: ["w3fa-clip", "text"]), kind: .view("Text"),
            drawPayload: .text("####"))
        ])
      var metadata = node.drawMetadata
      metadata.shapeClips = [.init(geometry: geometry, insetAmount: 0)]
      node.drawMetadata = metadata
      return node
    }
  }

  static func width(of node: ResolvedNode, _ kind: Kind) -> Double? {
    let geometry: ShapeGeometry?
    switch kind {
    case .fill:
      if case .shape(let payload) = node.drawPayload {
        geometry = payload.geometry
      } else {
        geometry = nil
      }
    case .clip:
      geometry = node.drawMetadata.shapeClips.first?.geometry
    }
    guard case .path(let boxed, _) = geometry else { return nil }
    return boxed.path.boundingRect?.size.width
  }

  /// Animates width 0.2 -> 1 at t0 (optionally retargeting to `retarget.width`
  /// at `retarget.at` ms) and returns the sampled width at `milliseconds`.
  static func sampledWidth(
    _ kind: Kind, animation: Animation, at milliseconds: Int,
    retarget: (width: Double, animation: Animation, at: Int)? = nil
  ) throws -> Double {
    let controller = AnimationController()
    _ = controller.register(animation)
    let time = MonotonicInstant.now()
    controller.processResolvedTree(node(kind, width: 0.2), transaction: .init(), timestamp: time)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(node(kind, width: 1), transaction: transaction, timestamp: time)
    var destination = 1.0
    if let retarget {
      _ = controller.register(retarget.animation)
      var second = TransactionSnapshot()
      second.animationRequest = .animate(retarget.animation.animationBox)
      controller.processResolvedTree(
        node(kind, width: retarget.width), transaction: second,
        timestamp: time.advanced(by: .milliseconds(retarget.at)))
      destination = retarget.width
    }
    var sample = node(kind, width: destination)
    _ = controller.applyInterpolations(
      to: &sample, at: time.advanced(by: .milliseconds(milliseconds)))
    return try #require(width(of: sample, kind))
  }

  static func maxPaintedX(in frame: String) -> Int {
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard let top = rows.first else { return -1 }
    var last = -1
    for (index, character) in top.enumerated() where character != " " {
      last = index
    }
    return last
  }

  static func staticClipExtent(fraction: Double) -> Int {
    let surface = DefaultRenderer().render(
      W3FAClipRows().clipShape(W3FAClipShape(fraction: fraction)),
      proposal: .init(width: 20, height: 4)
    ).rasterSurface
    return maxPaintedX(in: surface.lines.joined(separator: "\n"))
  }
}

@MainActor
final class W3FAClipLog {
  var fraction: Binding<Double>?
}

@MainActor
final class W3FAClock { var now = MonotonicInstant.now() }

struct W3FAClipShape: Shape {
  var fraction: Double

  func path(in rect: Rect) -> Path {
    var path = Path()
    let right = rect.origin.x + rect.size.width * fraction
    let bottom = rect.origin.y + rect.size.height
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: bottom))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.closeSubpath()
    return path
  }
}

struct W3FAClipRows: View {
  var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<4, id: \.self) { _ in Text(String(repeating: "#", count: 20)) }
    }
  }
}

struct W3FAImplicitClipRoot: View {
  @State private var fraction = 0.25
  let log: W3FAClipLog

  var body: some View {
    let _ = capture()
    W3FAClipRows()
      .clipShape(W3FAClipShape(fraction: fraction))
      .animation(.linear(duration: .seconds(1)), value: fraction)
  }

  private func capture() {
    log.fraction = $fraction
  }
}

// MARK: - Diagnostic fixtures (w3fa019, w3fa020)

struct W3FAItem: Identifiable, Equatable, Sendable {
  var id: Int
  var count: Int
}

struct W3FADiagnosticModel: Equatable, Sendable {
  var count = 1
  var maybe: Int? = 1
}

@MainActor
final class W3FADiagnosticLog {
  var records: [BodyChangeRecord] = []
  var items: Binding<[W3FAItem]>?
  var model: Binding<W3FADiagnosticModel>?
  var sink: BodyChangeSink { .init { [self] record, _ in records.append(record) } }

  /// The properties named by state/exact causes of the readers of `type`.
  func namedCauses(_ type: String) -> Set<String> {
    Set(
      records.filter { $0.typeName.contains(type) }.flatMap(\.causes)
        .filter { $0.category == "state" && $0.precision == "exact" }.compactMap(\.property))
  }
}

struct W3FAElementDiagnosticRoot: View {
  @State private var items = [W3FAItem(id: 0, count: 1), W3FAItem(id: 1, count: 1)]
  let log: W3FADiagnosticLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      ForEach($items) { item in
        if item.wrappedValue.id == 0 {
          W3FAElementReader(value: item.count)
        }
      }
      W3FAPositionalReader(value: $items[0].count)
      W3FAKeyPathReader(value: $items[dynamicMember: \[W3FAItem].[0].count])
    }
  }

  private func capture() {
    log.items = $items
  }
}

struct W3FAElementReader: View {
  @Binding var value: Int
  var body: some View {
    Self._printChanges()
    return Text("e \(value)")
  }
}

struct W3FAPositionalReader: View {
  @Binding var value: Int
  var body: some View {
    Self._printChanges()
    return Text("p \(value)")
  }
}

struct W3FAKeyPathReader: View {
  @Binding var value: Int
  var body: some View {
    Self._printChanges()
    return Text("k \(value)")
  }
}

struct W3FADerivedDiagnosticRoot: View {
  @State private var model = W3FADiagnosticModel()
  let log: W3FADiagnosticLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      W3FAAnimatedReader(value: $model.count.animation(.linear(duration: .milliseconds(10))))
      if let unwrapped = Binding<Int>($model.maybe) {
        W3FAUnwrappedReader(value: unwrapped)
      }
    }
  }

  private func capture() {
    log.model = $model
  }
}

struct W3FAAnimatedReader: View {
  @Binding var value: Int
  var body: some View {
    Self._printChanges()
    return Text("a \(value)")
  }
}

struct W3FAUnwrappedReader: View {
  @Binding var value: Int
  var body: some View {
    Self._printChanges()
    return Text("u \(value)")
  }
}

// MARK: - Lazy stack fixtures (w3fa021–026)

@MainActor
final class W3FAStackLog {
  var proxy: ScrollViewProxy?
  var activated: [String] = []

  func capture(_ proxy: ScrollViewProxy) {
    self.proxy = proxy
  }
}

/// Header, then a scroll view holding a windowed first lazy stack, six
/// fillers, a claim-denied second lazy stack of five buttons and twelve tail
/// rows: only the outermost indexed container claims the viewport.
struct W3FATwoStacks: View {
  let firstCount: Int
  let log: W3FAStackLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      ScrollViewReader { proxy in
        let _ = log.capture(proxy)
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach((0..<firstCount).map { "first \($0)" }, id: \.self) { name in
                Button(name) { log.activated.append(name) }
              }
            }
            ForEach(0..<6, id: \.self) { index in
              Text("filler \(index)")
            }
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach((0..<5).map { "second \($0)" }, id: \.self) { name in
                Button(name) { log.activated.append(name) }
              }
            }
            ForEach(0..<12, id: \.self) { index in
              Text("tail \(index)")
            }
          }
        }.scrollIndicators(.hidden)
      }
    }
  }
}

/// The two-stack shape with text rows at a fixed scroll offset.
struct W3FAPositionedStacks: View {
  let offset: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      ScrollView(position: .constant(ScrollCellOffset(y: offset))) {
        VStack(alignment: .leading, spacing: 0) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in Text("first \(index)") }
          }
          ForEach(0..<6, id: \.self) { index in Text("filler \(index)") }
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5, id: \.self) { index in Text("second \(index)") }
          }
          ForEach(0..<12, id: \.self) { index in Text("tail \(index)") }
        }
      }.scrollIndicators(.hidden)
    }
  }
}

struct W3FAHorizontalStacks: View {
  let offset: Int

  var body: some View {
    ScrollView(.horizontal, position: .constant(ScrollCellOffset(x: offset))) {
      HStack(spacing: 1) {
        LazyHStack(spacing: 1) {
          ForEach(0..<4, id: \.self) { index in Text("a\(index)") }
        }
        ForEach(0..<6, id: \.self) { index in Text("f\(index)") }
        LazyHStack(spacing: 1) {
          ForEach(0..<5, id: \.self) { index in Text("b\(index)") }
        }
      }
    }.scrollIndicators(.hidden)
  }
}

@MainActor
enum W3FALazy {
  struct Placement {
    var stacks: [PlacedNode]
    var text: String
  }

  /// A one-shot render's placed lazy stacks, in tree order. The layout shadow
  /// is not this helper's subject (FW3-C's armed exit test owns it).
  static func placedStacks(
    _ view: some View, name: String, width: Int = 40, height: Int = 8
  ) throws -> Placement {
    let saved = SoundnessProbeConfiguration.isEnabled
    SoundnessProbeConfiguration.isEnabled = false
    defer { SoundnessProbeConfiguration.isEnabled = saved }
    let snapshot = DefaultRenderer().render(
      view, context: .init(identity: testIdentity(name)),
      proposal: .init(width: .finite(width), height: .finite(height)))
    var found: [PlacedNode] = []
    var pending = [snapshot.placedTree]
    while let node = pending.popLast() {
      if node.lazyStackAllocationSnapshot != nil {
        found.append(node)
      }
      pending.append(contentsOf: node.children.reversed())
    }
    return Placement(stacks: found, text: snapshot.rasterSurface.lines.joined(separator: "\n"))
  }

  static func wheel<Content: View>(
    _ h: StressRuntimeHarness<Content>, deltaY: Int = 1, limit: Int = 48,
    until done: (String) -> Bool
  ) throws -> Bool {
    try W3FATable.wheel(h, at: Point(x: 2, y: 3), deltaY: deltaY, limit: limit, until: done)
  }
}

/// A run-loop harness whose surface can be resized (SIGWINCH), in the shape of
/// `AdversarialSetATerminalInteractionDepthTests`' depth harness.
@MainActor
final class W3FAResizeHarness<Content: View> {
  let surface: W3FAResizableSurface
  let loop: SwiftTUIRuntime.RunLoop<Int, Content>
  private let root: Identity
  private var rendered = 0

  init(name: String, size: CellSize, @ViewBuilder content: @escaping () -> Content) throws {
    root = testIdentity(name)
    surface = W3FAResizableSurface(size: size)
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: root, presentationSurface: surface,
      inputReader: W3FAEmptyInput(), signalReader: W3FAEmptySignals(), scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus,
      viewBuilder: { _, _ in content() })
    focus.invalidator = scheduler
    scheduler.requestInvalidation(of: [root])
    try render()
    loop.renderer.enableSelectiveEvaluation()
  }

  var frame: String { surface.surface?.lines.joined(separator: "\n") ?? "" }

  func render() throws { try loop.renderPendingFrames(renderedFrames: &rendered) }

  func shutdown() { loop.lifecycleCoordinator.shutdown() }

  func send(_ event: RuntimeEvent) throws {
    #expect(loop.withRuntimeRegistrationScope { loop.handle(event) } == nil)
    try render()
  }

  func resize(width: Int, height: Int) throws {
    surface.surfaceSize = .init(width: width, height: height)
    try send(.signal("SIGWINCH"))
  }

  func focusText(_ text: String) throws {
    let rows = try #require(surface.surface).lines
    var location: Point?
    for (y, row) in rows.enumerated() {
      if let range = row.range(of: text) {
        location = Point(
          x: Double(row.distance(from: row.startIndex, to: range.lowerBound) + text.count / 2),
          y: Double(y))
        break
      }
    }
    let point = try #require(location, "missing '\(text)' in \(frame)")
    let region = try #require(
      loop.focusTracker.focusRegions.last { $0.rect.contains(point.containingCell) })
    let changed = loop.focusTracker.setFocus(to: region.identity)
    try #require(changed || loop.focusTracker.currentFocusIdentity == region.identity)
    try render()
  }
}

final class W3FAResizableSurface: PresentationSurface {
  let supportsUserExit = true
  var surfaceSize: CellSize
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  var surface: RasterSurface?
  init(size: CellSize) { surfaceSize = size }
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}
  func present(_ surface: RasterSurface) throws -> PresentationMetrics {
    self.surface = surface
    return .init(
      linesTouched: surface.size.height, cellsChanged: surface.size.width * surface.size.height)
  }
}

final class W3FAEmptyInput: InputReading {
  func events() -> AsyncStream<KeyPress> { AsyncStream { $0.finish() } }
}

final class W3FAEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

// MARK: - Invalidation fixtures (w3fa027, w3fa028)

@MainActor
final class W3FASheetLog {
  var isPresented = false
  var base: Binding<Int>?
  var inner: Binding<Int>?
  var baseEvaluations = 0
  var presented: Binding<Bool> {
    Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
  }
}

struct W3FASheetRoot: View {
  @State private var base = 0
  let log: W3FASheetLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("base \(base)")
      Text("pad")
    }
    .sheet(isPresented: log.presented) {
      W3FASheetInner(log: log)
    }
  }

  private func capture() {
    log.base = $base
    log.baseEvaluations += 1
  }
}

struct W3FASheetInner: View {
  @State private var inner = 0
  let log: W3FASheetLog

  var body: some View {
    let _ = capture()
    Text("inner \(inner)")
  }

  private func capture() {
    log.inner = $inner
  }
}

@MainActor
final class W3FARowsLog {
  var counts: [Int: Binding<Int>] = [:]
  var shared: Binding<Int>?
}

struct W3FARowsRoot: View {
  @State private var shared = 0
  let log: W3FARowsLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<40, id: \.self) { index in
        W3FACounterRow(index: index, shared: shared, log: log)
      }
    }
  }

  private func capture() {
    log.shared = $shared
  }
}

struct W3FACounterRow: View {
  let index: Int
  let shared: Int
  let log: W3FARowsLog
  @State private var count = 0

  var body: some View {
    let _ = capture()
    Text("r\(index) \(count) \(shared)")
  }

  private func capture() {
    log.counts[index] = $count
  }
}

// MARK: - Departure fixtures (w3fa029–036, w3fa040)

@MainActor
final class W3FATabModel {
  var selection = "A"
  var showsGeometry = false

  var selectionBinding: Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
}

@MainActor
func w3faContext(_ root: Identity) -> ResolveContext {
  ResolveContext(
    identity: root,
    localActionRegistry: LocalActionRegistry(),
    localKeyHandlerRegistry: nil,
    applyEnvironmentValues: true
  )
}

func w3faText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

@MainActor
func w3faEmptyPump<Content: View>(_: Content.Type)
  -> SwiftTUIRuntime.RunLoop<Int, Content>
  .EventPump
{
  .init(
    stream: AsyncStream { $0.finish() }, drainEvents: { [] }, hasPendingEvents: { false },
    cancel: {}, scheduleDeadlineWake: { _ in })
}

/// Set by layout-realized content when the inline pass realizes it; read by
/// the frame-tail layout hook on the worker.
final class W3FARealizedFlag: Sendable {
  private let state = Mutex(false)
  var isSet: Bool { state.withLock { $0 } }
  func set() { state.withLock { $0 = true } }
}

@MainActor
final class W3FAHopProbe {
  var writeSibling: ((Int) -> Void)?
  var readSibling: (() -> Int)?
  var writeDeparting: ((Int) -> Void)?
  var readDeparting: (() -> Int)?
  let realized = W3FARealizedFlag()
}

/// Blocks the first layout pass after layout-dependent content was realized
/// (its offloaded relayout) and the raster stage after it.
@MainActor
final class W3FAHopGates {
  let layout = AsyncFrameTailBlockingGate()
  let raster = AsyncFrameTailBlockingGate()
  private let renderer: DefaultRenderer

  init(renderer: DefaultRenderer, realized: W3FARealizedFlag) {
    self.renderer = renderer
    let layout = layout
    let raster = raster
    renderer.setFrameTailRenderHooks(
      .init(
        beforeLayout: {
          if realized.isSet {
            layout.beforeRaster()
          }
        },
        beforeRaster: { raster.beforeRaster() }
      ))
  }

  func releaseAll() {
    layout.release()
    raster.release()
    renderer.setFrameTailRenderHooks(nil)
  }
}

struct W3FAHopSibling: View {
  let probe: W3FAHopProbe
  @State private var value = 0

  var body: some View {
    probe.writeSibling = { value = $0 }
    probe.readSibling = { value }
    return Text("S count \(value)")
  }
}

struct W3FAHopDeparting: View {
  let probe: W3FAHopProbe
  @State private var value = 0

  var body: some View {
    probe.writeDeparting = { value = $0 }
    probe.readDeparting = { value }
    return Text("A count \(value)")
  }
}

struct W3FAHopFixture: View {
  let model: W3FATabModel
  let probe: W3FAHopProbe

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      W3FAHopSibling(probe: probe)
      TabView(selection: model.selectionBinding) {
        Tab("A", value: "A") {
          W3FAHopDeparting(probe: probe)
        }
        Tab("B", value: "B") {
          GeometryReader { proxy in
            probe.realized.set()
            return Text("B width \(proxy.size.width)")
          }
        }
      }
    }
  }
}

struct W3FAArrivingGeometryFixture: View {
  let model: W3FATabModel
  let probe: W3FAHopProbe

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      W3FAHopSibling(probe: probe)
      if model.showsGeometry {
        GeometryReader { proxy in
          probe.realized.set()
          return Text("G width \(proxy.size.width)")
        }
      }
    }
  }
}

/// Producer-owned signals for a `.task` loop: readiness per generation, a
/// tick that fires once consumed or once the task has ended, and how it ended.
@MainActor
final class W3FATaskProbe {
  private(set) var taskStarts = 0
  private(set) var endedGenerations: [Int] = []
  private(set) var cancellationObserved: [Int] = []
  private(set) var events: [String] = []
  private(set) var disappears = 0
  private(set) var activeTasksAtDisappear: [Int] = []
  /// The run loop's live task handles, read when the disappear handler runs.
  var activeTasks: (() -> Int)?
  private var readyEvents: [Int: AsyncEvent] = [:]
  private var continuation: AsyncStream<Void>.Continuation?
  private var pendingTick: AsyncEvent?

  func readyEvent(generation: Int) -> AsyncEvent {
    if let event = readyEvents[generation] {
      return event
    }
    let event = AsyncEvent()
    readyEvents[generation] = event
    return event
  }

  func startTask() -> (generation: Int, ticks: AsyncStream<Void>) {
    taskStarts += 1
    let (ticks, continuation) = AsyncStream<Void>.makeStream()
    self.continuation = continuation
    readyEvent(generation: taskStarts).fire()
    return (taskStarts, ticks)
  }

  func tick() -> AsyncEvent {
    let event = AsyncEvent()
    guard let continuation else {
      event.fire()
      return event
    }
    pendingTick = event
    continuation.yield(())
    return event
  }

  func recordIteration() {
    pendingTick?.fire()
    pendingTick = nil
  }

  func recordEnd(generation: Int, cancelled: Bool) {
    endedGenerations.append(generation)
    events.append("end \(generation)")
    if cancelled {
      cancellationObserved.append(generation)
    }
    continuation = nil
    pendingTick?.fire()
    pendingTick = nil
  }

  func recordDisappear() {
    disappears += 1
    events.append("disappear")
    activeTasksAtDisappear.append(activeTasks?() ?? -1)
  }
}

@MainActor
final class W3FATaskIDModel {
  var generation = 0
}

struct W3FATaskIDFixture: View {
  let model: W3FATaskIDModel
  let probe: W3FATaskProbe

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.generation == 0 {
        Button("Next") {}
      }
      Button("Other") {}
      Text("gen \(model.generation)")
        .task(id: model.generation) {
          let (generation, ticks) = probe.startTask()
          for await _ in ticks {
            probe.recordIteration()
          }
          probe.recordEnd(generation: generation, cancelled: Task.isCancelled)
        }
    }
  }
}

struct W3FADepartingTaskFixture: View {
  let model: W3FATabModel
  let probe: W3FATaskProbe

  var body: some View {
    TabView(selection: model.selectionBinding) {
      Tab("A", value: "A") {
        W3FADepartingTaskContent(probe: probe)
      }
      Tab("B", value: "B") {
        Text("plain-B")
      }
    }
  }
}

/// The FW3-D departing-task content (`DormantTabStateTests`), plus a
/// disappear probe (correction C3).
struct W3FADepartingTaskContent: View {
  let probe: W3FATaskProbe
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("A count \(count)")
      Button("Bump") { count += 1 }
    }
    .onChange(of: count) {}
    .onDisappear {
      probe.recordDisappear()
    }
    .task {
      let (generation, ticks) = probe.startTask()
      for await _ in ticks {
        count += 1
        probe.recordIteration()
      }
      probe.recordEnd(generation: generation, cancelled: Task.isCancelled)
    }
  }
}

/// Opens a presentation through the async driver, holds the open's own frame
/// tail (raster entry 1) and dismisses while it is held, the interleaving of
/// `PresentationSurfaceTests.openAndDismissDuringFocusRerender`. Returns
/// whether the open reached its tail.
@MainActor
func w3faOpenAndDismissDuringFocusRerender<Content: View>(
  harness: StressRuntimeHarness<Content>,
  root: Identity,
  setPresented: (Bool) -> Void,
  beforeOpen: () -> Void
) async throws -> Bool {
  let gate = AsyncFrameTailBlockingGate(blockingEntry: 1)
  harness.runLoop.renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
  defer {
    gate.release()
    harness.runLoop.renderer.setFrameTailRenderHooks(nil)
  }
  beforeOpen()
  setPresented(true)
  harness.runLoop.scheduler.requestInvalidation(of: [root])
  let finished = AsyncEvent()
  let renderTask = Task { @MainActor in
    var frames = 0
    _ = try await harness.runLoop.renderPendingFramesAsync(
      renderedFrames: &frames, eventPump: w3faEmptyPump(Content.self))
    finished.fire()
  }
  let blocked = await firstFrameTailSignal(blocked: gate, orFinished: finished)
  if blocked {
    setPresented(false)
    harness.runLoop.scheduler.requestInvalidation(of: [root])
  }
  gate.release()
  try await renderTask.value
  if !blocked {
    setPresented(false)
    _ = try harness.renderAfterExternalMutation()
  }
  return blocked
}

/// Records each palette lifetime's appear, initial change, disappear and task
/// starts, and whether each handler's own @State write landed on a live owner.
@MainActor
final class W3FAPaletteProbe {
  struct TaskStart: Equatable {
    var open: Int
    var landed: Bool
  }

  var opens = 0
  private(set) var events: [String] = []
  private(set) var taskStarts: [TaskStart] = []
  private var startedEvents: [Int: AsyncEvent] = [:]
  private var continuations: [AsyncStream<Void>.Continuation] = []

  func startedEvent(open: Int) -> AsyncEvent {
    if let event = startedEvents[open] {
      return event
    }
    let event = AsyncEvent()
    startedEvents[open] = event
    return event
  }

  func record(_ event: String) {
    events.append(event)
  }

  /// Keeps a task's stream open until the task is cancelled.
  func retain(_ continuation: AsyncStream<Void>.Continuation) {
    continuations.append(continuation)
  }

  func recordTaskStart(open: Int, landed: Bool) {
    taskStarts.append(.init(open: open, landed: landed))
    startedEvent(open: open).fire()
  }
}

struct W3FAPaletteFixture: View {
  let model: PaletteAppearModel
  let probe: W3FAPaletteProbe

  var body: some View {
    Panel(id: "w3fa-palette-source") {
      Text("Workspace")
    }
    .paletteCommand(name: "Alpha") {}
    .paletteCommand(name: "Beta") {}
    .panel(id: "w3fa-palette-host")
    .paletteSheet("Command palette", isPresented: model.binding)
    .paletteStyle(W3FAProbePaletteStyle(probe: probe))
  }
}

private struct W3FAProbePaletteStyle: PaletteStyle {
  let probe: W3FAPaletteProbe

  @MainActor func makeBody(configuration: PaletteStyleConfiguration) -> some View {
    W3FAProbePaletteBody(commandCount: configuration.commands.count, probe: probe)
  }
}

private struct W3FAProbePaletteBody: View {
  let commandCount: Int
  let probe: W3FAPaletteProbe
  @State private var query = "seed"
  @State private var mark = -1
  @FocusState private var isQueryFocused: Bool
  @Namespace private var filterScope

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField("Probe filter", text: $query)
        .focused($isQueryFocused)
        .prefersDefaultFocus(in: filterScope)
      Text("commands \(commandCount)")
    }
    .focusScope(filterScope)
    .onAppear {
      query = ""
      probe.record("appear \(probe.opens)")
    }
    .onChange(of: commandCount, initial: true) {
      probe.record("change \(probe.opens)")
    }
    .onDisappear {
      probe.record("disappear \(probe.opens)")
    }
    .task {
      let open = probe.opens
      probe.recordTaskStart(open: open, landed: stampLanded(open))
      let (ticks, continuation) = AsyncStream<Void>.makeStream()
      probe.retain(continuation)
      for await _ in ticks {}
    }
  }

  private func stampLanded(_ open: Int) -> Bool {
    mark = open
    return mark == open
  }
}

@MainActor
final class W3FASheetProbe {
  var opens = 0
  private(set) var appears: [Int] = []
  private(set) var appearLanded: [Bool] = []
  var disappears = 0

  func recordAppear(open: Int, landed: Bool) {
    appears.append(open)
    appearLanded.append(landed)
  }
}

struct W3FASheetFixture: View {
  let model: PaletteAppearModel
  let probe: W3FASheetProbe

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Workspace")
      Button("Elsewhere") {}
    }
    .sheet(isPresented: model.binding) {
      W3FASheetProbeBody(probe: probe)
    }
  }
}

private struct W3FASheetProbeBody: View {
  let probe: W3FASheetProbe
  @State private var text = ""
  @State private var mark = -1

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField("Sheet field", text: $text)
      Text("sheet body")
    }
    .onAppear {
      let open = probe.opens
      mark = open
      probe.recordAppear(open: open, landed: mark == open)
    }
    .onDisappear {
      probe.disappears += 1
    }
  }
}

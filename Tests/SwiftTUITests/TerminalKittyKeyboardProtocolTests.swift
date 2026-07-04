import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Host-side kitty keyboard protocol enablement (F14 stage 2): the probe
/// (`CSI ? u` piggybacking `CSI c`), the flag push after entering the
/// alternate screen, and the pop before leaving it.
@MainActor
@Suite
struct TerminalKittyKeyboardProtocolTests {
  private static let flagsReportWithDeviceAttributes = Array(
    "\u{001B}[?1u\u{001B}[?62;4c".utf8
  )
  private static let deviceAttributesOnly = Array("\u{001B}[?62;4c".utf8)

  @Test("Supporting terminals get the enhancement push after the alternate screen")
  func supportingTerminalGetsPush() throws {
    let controller = KittyKeyboardMockTerminalController(
      readResponses: [Self.flagsReportWithDeviceAttributes]
    )
    let host = makeHost(controller: controller)

    try host.enableRawMode()

    let output = controller.writes.joined()
    let altScreenRange = try #require(output.firstLiteralRange(of: "\u{001B}[?1049h"))
    let pushRange = try #require(output.firstLiteralRange(of: "\u{001B}[>1u"))
    #expect(altScreenRange.upperBound <= pushRange.lowerBound)
  }

  @Test("Disabling raw mode pops the enhancement before leaving the alternate screen")
  func disableRawModePopsBeforeAlternateScreenExit() throws {
    let controller = KittyKeyboardMockTerminalController(
      readResponses: [Self.flagsReportWithDeviceAttributes]
    )
    let host = makeHost(controller: controller)

    try host.enableRawMode()
    try host.disableRawMode()

    let output = controller.writes.joined()
    let popRange = try #require(output.firstLiteralRange(of: "\u{001B}[<u"))
    let exitRange = try #require(output.firstLiteralRange(of: "\u{001B}[?1049l"))
    #expect(popRange.upperBound <= exitRange.lowerBound)
  }

  @Test("Terminals without the protocol get no push and no pop")
  func unsupportingTerminalGetsNoPush() throws {
    let controller = KittyKeyboardMockTerminalController(
      readResponses: [Self.deviceAttributesOnly]
    )
    let host = makeHost(controller: controller)

    try host.enableRawMode()
    try host.disableRawMode()

    let output = controller.writes.joined()
    // The probe itself ran (DA-terminated), but no flags were pushed.
    #expect(output.contains("\u{001B}[?u"))
    #expect(!output.contains("\u{001B}[>1u"))
    #expect(!output.contains("\u{001B}[<u"))
  }

  @Test("SWIFTTUI_KITTY_KEYBOARD=0 suppresses the probe entirely")
  func killSwitchSuppressesProbe() throws {
    let controller = KittyKeyboardMockTerminalController(
      readResponses: [Self.flagsReportWithDeviceAttributes]
    )
    let host = makeHost(
      controller: controller,
      environment: ["TERM": "xterm-kitty", "SWIFTTUI_KITTY_KEYBOARD": "0"]
    )

    try host.enableRawMode()

    let output = controller.writes.joined()
    #expect(!output.contains("\u{001B}[?u"))
    #expect(!output.contains("\u{001B}[>1u"))
  }

  @Test("Terminal multiplexers suppress the probe (tmux owns the panes)")
  func multiplexerSuppressesProbe() throws {
    let controller = KittyKeyboardMockTerminalController(
      readResponses: [Self.flagsReportWithDeviceAttributes]
    )
    let host = makeHost(
      controller: controller,
      environment: ["TERM": "xterm-kitty", "TMUX": "/tmp/tmux-1000/default,42,0"]
    )

    try host.enableRawMode()

    let output = controller.writes.joined()
    #expect(!output.contains("\u{001B}[?u"))
    #expect(!output.contains("\u{001B}[>1u"))
  }

  @Test("Crash-path reset bytes include the pop while pushed")
  func processExitResetIncludesPop() {
    let reset = TerminalHostEscapeSequences.processExitReset(
      mouseCoordinateMode: .cells,
      hoverEnabled: false,
      kittyKeyboardPushed: true
    )
    let popRange = reset.firstLiteralRange(of: "\u{001B}[<u")
    let exitRange = reset.firstLiteralRange(of: "\u{001B}[?1049l")
    #expect(popRange != nil)
    #expect(exitRange != nil)
    if let popRange, let exitRange {
      #expect(popRange.upperBound <= exitRange.lowerBound)
    }

    let unpushed = TerminalHostEscapeSequences.processExitReset(
      mouseCoordinateMode: .cells,
      hoverEnabled: false,
      kittyKeyboardPushed: false
    )
    #expect(!unpushed.contains("\u{001B}[<u"))
  }

  @Test("Flags report parsing tolerates the piggybacked device attributes")
  func flagsReportParsing() {
    #expect(parseKittyKeyboardFlagsReport(from: Self.flagsReportWithDeviceAttributes) == 1)
    #expect(parseKittyKeyboardFlagsReport(from: Self.deviceAttributesOnly) == nil)
    #expect(parseKittyKeyboardFlagsReport(from: []) == nil)
    // DA arriving before the flags report must not mask it.
    #expect(
      parseKittyKeyboardFlagsReport(
        from: Array("\u{001B}[?62;4c\u{001B}[?5u".utf8)
      ) == 5
    )
  }

  private func makeHost(
    controller: KittyKeyboardMockTerminalController,
    environment: [String: String] = ["TERM": "xterm-kitty"]
  ) -> TerminalHost {
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: environment
    )
    // The appearance detection's OSC queries run before the keyboard
    // probe and would consume the queued read responses; mark it probed
    // so the queue lines up with the keyboard flags query.
    host.capabilityProbe.hasProbedAppearance = true
    return host
  }
}

/// Minimal TTY mock for keyboard-protocol tests. Reports no cell pixel
/// metrics so `enableRawMode` skips the SGR-pixels mode probe and the
/// queued read responses line up with the keyboard flags query.
private final class KittyKeyboardMockTerminalController: TerminalControlling {
  private let queuedReadResponsesStorage: LockedBox<[[UInt8]]>
  private let writesStorage = LockedBox<[String]>([])

  private(set) var writes: [String] {
    get { writesStorage.value }
    set { writesStorage.value = newValue }
  }

  init(readResponses: [[UInt8]] = []) {
    queuedReadResponsesStorage = LockedBox(readResponses)
  }

  func isATTY(_: Int32) -> Bool {
    true
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> PixelSize? {
    nil
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_ output: String, to _: Int32) throws {
    writesStorage.withLock { $0.append(output) }
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    queuedReadResponsesStorage.withLock { queuedReadResponses in
      guard !queuedReadResponses.isEmpty else {
        return []
      }
      return queuedReadResponses.removeFirst()
    }
  }
}

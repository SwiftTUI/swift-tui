// Adversarial set B: terminal capability detection, probe sessions, and scene identity.
// The terminal is only observed indirectly (environment variables and escape-sequence replies on
// the shared input descriptor), so a misread degrades silently into the wrong feature set, a
// dropped keystroke, or an unselectable scene. Motivated by the Sept–Oct 2026 reports: hyperlink,
// mouse and synchronized-output misdetection for common TERM values (STUI-927…941), keystrokes
// eaten by mid-session probes (STUI-949), ungated reader→grid probes, and STUI-708 collisions.

import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: terminal capabilities", .serialized)
struct AdversarialSetBTerminalTests {
  private static let locale = ["LANG": "en_US.UTF-8"]

  private static func posix(_ environment: [String: String], isTTY: Bool = true)
    -> TerminalCapabilityProfile
  {
    TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: locale.merging(environment) { $1 }, isTTY: isTTY)
  }

  private static func windows(_ environment: [String: String]) -> TerminalCapabilityProfile {
    TerminalCapabilityProfile.detectWindowsConsole(environment: environment, isTTY: true)
  }

  @Test func setB081GenericXtermIsRefinedOnlyByKnownEmulators() throws {
    // Hypothesis: an emulator outside the refinement table (Apple Terminal) can borrow the OSC 8
    // and synchronized-output claims of a known emulator through a generic xterm TERM, while a
    // generic xterm variant (xterm-direct) loses a known emulator's refinement.
    let apple = Self.posix(["TERM": "xterm-256color", "TERM_PROGRAM": "Apple_Terminal"])
    #expect(!apple.supportsHyperlinks)
    #expect(!apple.supportsSynchronizedOutput)
    #expect(apple.supportsMouseReporting)
    #expect(apple.colorLevel == .ansi256)
    #expect(apple.supportsScrollRegions)

    let appleTrueColor = Self.posix([
      "TERM": "xterm-256color", "TERM_PROGRAM": "Apple_Terminal", "COLORTERM": "truecolor",
    ])
    #expect(appleTrueColor.colorLevel == .trueColor)
    #expect(!appleTrueColor.supportsHyperlinks)
    #expect(!appleTrueColor.supportsSynchronizedOutput)

    let iterm = Self.posix(["TERM": "xterm-256color", "TERM_PROGRAM": "iTerm.app"])
    #expect(iterm.supportsHyperlinks)
    #expect(iterm.supportsSynchronizedOutput)
    #expect(iterm.supportsMouseReporting)

    let ghostty = Self.posix(["TERM": "XTERM", "TERM_PROGRAM": "Ghostty"])
    #expect(ghostty.supportsHyperlinks)
    #expect(ghostty.supportsSynchronizedOutput)
    #expect(ghostty.supportsMouseReporting)

    // xterm-direct is xterm's own true-color terminfo entry, not an intervening terminal, so the
    // documented "refine generic xterm entries" rule applies to it as well.
    let direct = Self.posix(["TERM": "xterm-direct", "TERM_PROGRAM": "WezTerm"])
    do {
      #expect(direct.supportsHyperlinks)
      #expect(direct.supportsSynchronizedOutput)
    }
    #expect(direct.supportsMouseReporting)
  }

  @Test func setB082NonFamilyTerminalsNeverClaimRichFeatures() throws {
    // Hypothesis: a dotted screen TERM, a dumb TERM with COLORTERM, an unset TERM, or a bare
    // console TERM can land on a rich feature set, or screen's own TERM spelling can be treated
    // as a non-multiplexer while the host still treats it as one.
    let dotted = Self.posix(["TERM": "screen.xterm-256color"])
    let dashed = Self.posix(["TERM": "screen-256color"])
    do {
      #expect(dotted.supportsMouseReporting == dashed.supportsMouseReporting)
      #expect(dotted.supportsMouseReporting)
    }
    #expect(!dotted.supportsHyperlinks)
    #expect(!dotted.supportsSynchronizedOutput)
    #expect(dotted.colorLevel == .ansi256)
    let dottedHost = makeSetBHost(
      controller: SetBMockTerminalController(isTTY: true),
      environment: ["TERM": "screen.xterm-256color"])
    #expect(dottedHost.isInsideTerminalMultiplexer)

    let dumb = Self.posix(["TERM": "dumb", "COLORTERM": "truecolor"])
    #expect(dumb.colorLevel == .none)
    #expect(!dumb.emitsStyleEscapeSequences)
    #expect(!dumb.supportsHyperlinks)
    #expect(!dumb.supportsMouseReporting)
    #expect(!dumb.supportsSynchronizedOutput)
    #expect(!dumb.supportsScrollRegions)
    #expect(dumb.glyphLevel == .unicode)

    let unset = TerminalCapabilityProfile.detectPOSIXTerminal(environment: [:], isTTY: true)
    #expect(unset.colorLevel == .ansi16)
    #expect(unset.emitsStyleEscapeSequences)
    #expect(!unset.supportsHyperlinks)
    #expect(!unset.supportsMouseReporting)
    #expect(!unset.supportsSynchronizedOutput)
    #expect(unset.supportsScrollRegions)
    #expect(unset.glyphLevel == .ascii)

    for console in ["linux", "vt100"] {
      let profile = Self.posix(["TERM": console])
      #expect(profile.colorLevel == .ansi16, "\(console)")
      #expect(!profile.supportsHyperlinks, "\(console)")
      #expect(!profile.supportsMouseReporting, "\(console)")
      #expect(!profile.supportsSynchronizedOutput, "\(console)")
      #expect(profile.supportsScrollRegions, "\(console)")
    }

    // NO_COLOR is honored only when non-empty (no-color.org); an empty value changes nothing.
    let emptyNoColor = Self.posix(["TERM": "xterm-kitty", "NO_COLOR": ""])
    #expect(emptyNoColor.colorLevel == .ansi16)
    #expect(emptyNoColor.emitsStyleEscapeSequences)
    #expect(emptyNoColor.supportsHyperlinks)
    #expect(emptyNoColor.supportsMouseReporting)
    #expect(emptyNoColor.supportsSynchronizedOutput)
  }

  @Test func setB083WindowsTerminalAndKonsoleMarkersNeverLeakAcrossArms() throws {
    // Hypothesis: WT_SESSION can upgrade the POSIX arm, a foreign TERM under Windows Terminal can
    // still collect the Windows Terminal upgrades, or KONSOLE_VERSION can stand in for TERM.
    let posixWindowsTerminal = Self.posix(["TERM": "xterm-256color", "WT_SESSION": "abc"])
    #expect(!posixWindowsTerminal.supportsHyperlinks)
    #expect(!posixWindowsTerminal.supportsSynchronizedOutput)
    #expect(posixWindowsTerminal.supportsMouseReporting)

    let foreignUnderWindowsTerminal = Self.windows(["TERM": "screen-256color", "WT_SESSION": "abc"])
    #expect(!foreignUnderWindowsTerminal.supportsHyperlinks)
    #expect(!foreignUnderWindowsTerminal.supportsSynchronizedOutput)
    #expect(foreignUnderWindowsTerminal.supportsMouseReporting)
    #expect(foreignUnderWindowsTerminal.colorLevel == .ansi256)

    let upperXtermUnderWindowsTerminal = Self.windows(["TERM": "XTERM", "WT_SESSION": "abc"])
    #expect(upperXtermUnderWindowsTerminal.supportsHyperlinks)
    #expect(upperXtermUnderWindowsTerminal.supportsSynchronizedOutput)
    #expect(upperXtermUnderWindowsTerminal.supportsMouseReporting)
    #expect(upperXtermUnderWindowsTerminal.colorLevel == .ansi16)

    let bareWindowsTerminal = Self.windows(["WT_SESSION": "abc"])
    #expect(bareWindowsTerminal.colorLevel == .trueColor)
    #expect(bareWindowsTerminal.supportsHyperlinks)
    #expect(bareWindowsTerminal.supportsSynchronizedOutput)
    #expect(bareWindowsTerminal.supportsMouseReporting)

    let konsoleMarker = Self.posix(["TERM": "xterm-256color", "KONSOLE_VERSION": "230804"])
    #expect(!konsoleMarker.supportsHyperlinks)
    #expect(!konsoleMarker.supportsSynchronizedOutput)
    #expect(konsoleMarker.supportsMouseReporting)

    let konsoleTerm = Self.posix(["TERM": "konsole", "KONSOLE_VERSION": "230804"])
    #expect(konsoleTerm.supportsHyperlinks)
    #expect(konsoleTerm.supportsSynchronizedOutput)
    #expect(konsoleTerm.supportsMouseReporting)
  }

  @Test func setB084DeviceAttributesSplitAcrossReadsKeepsUserKeys() throws {
    // Hypothesis: a DA1 reply that straddles read boundaries, with user keys typed before, after,
    // or inside it, can lose a user key or type a fragment of the reply as text.
    let gate = SetBSpyInputSuspensionGate()
    let controller = SetBMockTerminalController(
      isTTY: true,
      readResponses: [Array("a\u{1B}[?62;".utf8), Array("22c".utf8), Array("b".utf8)])
    let host = makeSetBHost(controller: controller, gate: gate, environment: ["TERM": "xterm"])

    let buffer = try host.performInputCapabilityQuery(.kittyKeyboardFlags)
    #expect(buffer == Array("a\u{1B}[?62;22c".utf8))
    #expect(parsePrimaryDeviceAttributes(from: buffer) == [62, 22])
    #expect(parseKittyKeyboardFlagsReport(from: buffer) == nil)
    #expect(gate.replayed == buffer)
    var parser = TerminalInputParser()
    let delivered = parser.feed(gate.replayed) + parser.flush()
    #expect(delivered == [.key(.character("a"))])
    // The probe stopped at the terminator: the next user byte is still on the descriptor.
    let remaining = try controller.read(from: 0, maxBytes: 512, timeoutMilliseconds: 0)
    #expect(remaining == Array("b".utf8))

    // Two complete replies in one read with user keys between and after them: both replies
    // are consumed by the probe and every user key is replayed, in order, as itself.
    let pairedGate = SetBSpyInputSuspensionGate()
    let pairedController = SetBMockTerminalController(
      isTTY: true,
      readResponses: [Array("a\u{1B}[?62;22cb\u{1B}[?5uc".utf8), []])
    let pairedHost = makeSetBHost(
      controller: pairedController, gate: pairedGate, environment: ["TERM": "xterm"])
    let paired = try pairedHost.performInputCapabilityQuery(.kittyKeyboardFlags)
    #expect(paired == Array("a\u{1B}[?62;22cb\u{1B}[?5uc".utf8))
    #expect(parsePrimaryDeviceAttributes(from: paired) == [62, 22])
    #expect(parseKittyKeyboardFlagsReport(from: paired) == 5)
    #expect(pairedGate.replayed == paired)
    var pairedParser = TerminalInputParser()
    let pairedKeys = pairedParser.feed(pairedGate.replayed) + pairedParser.flush()
    #expect(pairedKeys == Array("abc").map { .key(.character($0)) })
  }

  @Test func setB085LateReplyAfterProbeTimeoutIsDroppedAndLatched() throws {
    // Hypothesis: a reply that arrives after its probe gave up can be typed as keystrokes, or can
    // reopen a probe that already recorded its answer for the session.
    let gate = SetBSpyInputSuspensionGate()
    let controller = SetBMockTerminalController(
      isTTY: true, readResponses: [[], Array("\u{1B}[?62;22c".utf8)])
    let reads = LockedBox(0)
    controller.onRead = { reads.withLock { $0 += 1 } }
    let host = makeSetBHost(controller: controller, gate: gate, environment: ["TERM": "xterm"])

    let timedOut = try host.performInputCapabilityQuery(.decPrivateMode(mode: 1016))
    #expect(timedOut.isEmpty)
    #expect(gate.replayed.isEmpty)
    #expect(reads.value == 1)
    #expect(gate.engagements == 1)

    let first = host.resolvedGraphicsCapabilities(probingProtocols: true)
    #expect(first.supportedProtocols.isEmpty)
    #expect(first.preferredProtocol == nil)
    #expect(gate.replayed == Array("\u{1B}[?62;22c".utf8))
    var parser = TerminalInputParser()
    #expect(parser.feed(gate.replayed).isEmpty)
    let kittyQueries = controller.writes.filter { $0.hasPrefix("\u{1B}_G") }
    #expect(kittyQueries.count == 1)
    let readsAfterProbe = reads.value
    let engagementsAfterProbe = gate.engagements
    #expect(readsAfterProbe > 1)

    let second = host.resolvedGraphicsCapabilities(probingProtocols: true)
    #expect(second == first)
    #expect(controller.writes.filter { $0.hasPrefix("\u{1B}_G") }.count == 1)
    #expect(reads.value == readsAfterProbe)
    #expect(gate.engagements == engagementsAfterProbe)
    #expect(gate.replayed == Array("\u{1B}[?62;22c".utf8))
  }

  @Test func setB086OneReadCarryingTwoRepliesStaysInsideOneSuspension() throws {
    // Hypothesis: a single read that carries the appearance reply and a stale DA1 reply can nest
    // or escape the suspension window, lose the stale bytes, or let the stale DA1 satisfy the
    // kitty keyboard probe that never received its own answer.
    let gate = SetBSpyInputSuspensionGate()
    let reply = Array("\u{1B}]10;rgb:0/0/0\u{7}\u{1B}[?62;4c".utf8)
    let controller = SetBMockTerminalController(isTTY: true, readResponses: [reply])
    let host = makeSetBHost(controller: controller, gate: gate, environment: ["TERM": "xterm"])
    let surface = TerminalReaderSurface(terminal: host, enabled: false)

    try surface.enableRawMode()
    defer { try? surface.disableRawMode() }

    #expect(host.appearance.source == .activeQuery)
    #expect(host.appearance.foregroundColor == Color(red: 0, green: 0, blue: 0))
    #expect(host.appearance.backgroundColor == TerminalAppearance.fallback.backgroundColor)
    #expect(gate.replayed == reply)
    #expect(gate.maxDepth == 1)
    #expect(gate.engagements >= 2)
    #expect(!gate.isSuspended)
    var parser = TerminalInputParser()
    #expect(parser.feed(gate.replayed).isEmpty)
    let output = controller.writes.joined()
    #expect(output.contains("\u{1B}]10;?"))
    #expect(output.contains("\u{1B}[?1049h"))
    #expect(output.contains("\u{1B}[?u"))
    #expect(!output.contains("\u{1B}[>1u"))
  }

  @Test func setB087SynchronizedOutputModeReportTable() throws {
    // Hypothesis: DECRPM for mode 2026 can map a state value to the wrong enablement decision,
    // accept an out-of-range or malformed state, or match a neighboring mode number.
    let table: [(value: Int, state: DECPrivateModeState, canEnable: Bool)] = [
      (0, .notRecognized, false),
      (1, .set, true),
      (2, .reset, true),
      (3, .permanentlySet, true),
      (4, .permanentlyReset, false),
    ]
    for row in table {
      let bytes = Array("\u{1B}[?2026;\(row.value)$y".utf8)
      let parsed = parseDECPrivateModeReport(from: bytes, mode: 2026)
      #expect(parsed == row.state, "state \(row.value)")
      #expect(parsed?.canEnable == row.canEnable, "state \(row.value)")
    }
    for malformed in [
      "\u{1B}[?2026;5$y", "\u{1B}[?2026;$y", "\u{1B}[?2026;1$Y", "\u{1B}[?20261;1$y",
      "\u{1B}[?2026;01$p",
    ] {
      #expect(
        parseDECPrivateModeReport(from: Array(malformed.utf8), mode: 2026) == nil,
        "\(malformed.dropFirst())")
    }
    #expect(parseDECPrivateModeReport(from: Array("\u{1B}[?2026;1$y".utf8), mode: 26) == nil)
    #expect(parseDECPrivateModeReport(from: Array("\u{1B}[?2026;1$y".utf8), mode: 202) == nil)

    // The host emits the exact DECRQM request and leaves the environment-derived profile alone.
    let gate = SetBSpyInputSuspensionGate()
    let controller = SetBMockTerminalController(
      isTTY: true, readResponses: [Array("\u{1B}[?2026;2$y".utf8)])
    let host = makeSetBHost(
      controller: controller, gate: gate, environment: ["TERM": "xterm-256color"],
      capabilityProfile: nil)
    #expect(!host.capabilityProfile.supportsSynchronizedOutput)
    let buffer = try host.performInputCapabilityQuery(.decPrivateMode(mode: 2026))
    #expect(controller.writes == ["\u{1B}[?2026$p"])
    #expect(parseDECPrivateModeReport(from: buffer, mode: 2026) == .reset)
    #expect(gate.replayed == buffer)
    #expect(!host.capabilityProfile.supportsSynchronizedOutput)
  }

  @Test func setB088BackgroundColorReplySpellings() throws {
    // Hypothesis: equivalent OSC 11 spellings can resolve to different colors, malformed replies
    // can resolve to a color, or a single failed query can leave a half-queried appearance.
    let white = Color(red: 1, green: 1, blue: 1)
    for spelling in ["rgb:ffff/ffff/ffff", "rgb:ff/ff/ff", "rgb:f/ff/fff", "#ffffff", "#fff"] {
      #expect(TerminalAppearanceQuery.background.parseColor(from: spelling) == white, "\(spelling)")
    }
    for malformed in [
      "rgb:ff/ff", "rgb:ff/ff/ff/ff", "rgba:ffff/ffff/ffff/ffff", "rgb:g0/00/00", "rgb:", "",
      "#ffffffff00",
    ] {
      #expect(
        TerminalAppearanceQuery.background.parseColor(from: malformed) == nil, "\(malformed)")
    }

    let hashReply = Array("\u{1B}]11;#ffffff\u{1B}\\".utf8)
    let extracted = try #require(
      TerminalAppearanceQuery.background.extractResponse(from: hashReply))
    #expect(extracted == "#ffffff")
    #expect(TerminalAppearanceQuery.background.parseColor(from: extracted) == white)
    let foregroundOnly = Array("\u{1B}]10;#ffffff\u{7}".utf8)
    #expect(TerminalAppearanceQuery.background.extractResponse(from: foregroundOnly) == nil)

    let appearance = TerminalAppearance.detect(
      environment: [:], capabilityProfile: .trueColor
    ) { query in
      if case .background = query { throw SetBQueryFailure() }
      return Color(red: 0, green: 0, blue: 0)
    }
    #expect(appearance.source == .fallback)
    #expect(appearance.foregroundColor == TerminalAppearance.fallback.foregroundColor)
    #expect(appearance.backgroundColor == TerminalAppearance.fallback.backgroundColor)
  }

  @Test func setB089OversizedNumeralsAndUnknownKittyFlagsNeverEscalate() throws {
    // Hypothesis: a numeral wider than Int can trap a reply parser or the input decoder, and a
    // flags report carrying bits the host does not know can be rejected as unsupported.
    let big = String(repeating: "9", count: 40)
    var parser = TerminalInputParser()
    #expect(parser.feed(Array("\u{1B}[\(big);\(big)R".utf8)).isEmpty)
    #expect(parser.feed(Array("x".utf8)) == [.key(.character("x"))])
    #expect(parsePrimaryDeviceAttributes(from: Array("\u{1B}[?\(big)c".utf8)) == nil)
    #expect(
      parseDECPrivateModeReport(from: Array("\u{1B}[?1016;\(big)$y".utf8), mode: 1016) == nil)
    #expect(parseWindowSizeResponse(from: Array("\u{1B}[4;\(big);1t".utf8), expectedCode: 4) == nil)
    #expect(parseKittyKeyboardFlagsReport(from: Array("\u{1B}[?\(big)u".utf8)) == nil)
    #expect(parseXTSMGraphicsResponse(from: Array("\u{1B}[?1;0;\(big)S".utf8), item: 1) == nil)
    #expect(parseKittySupportResponse(in: Array("\u{1B}_Gi=\(big);OK\u{1B}\\".utf8), id: 1) == nil)

    let deviceAttributes = "\u{1B}[?62;4c"
    let flagReplies: [(text: String, flags: Int?)] = [
      ("\u{1B}[?255u", 255), ("\u{1B}[?0u", 0), ("\u{1B}[?5;1u", nil), ("\u{1B}[?-1u", nil),
    ]
    for reply in flagReplies {
      let bytes = Array((reply.text + deviceAttributes).utf8)
      #expect(parseKittyKeyboardFlagsReport(from: bytes) == reply.flags)
    }

    // Unknown bits still mean "protocol spoken": the host pushes its enhancements after the
    // alternate screen, exactly as it does for a known flag value.
    let controller = SetBMockTerminalController(
      isTTY: true, readResponses: [Array("\u{1B}[?255u\(deviceAttributes)".utf8)])
    let host = makeSetBHost(controller: controller, environment: ["TERM": "xterm-kitty"])
    host.capabilityProbe.hasProbedAppearance = true
    try host.enableRawMode()
    defer { try? host.disableRawMode() }
    let output = controller.writes.joined()
    let alternateScreen = try #require(output.firstRange(of: "\u{1B}[?1049h"))
    let push = try #require(output.firstRange(of: "\u{1B}[>1u"))
    #expect(alternateScreen.upperBound <= push.lowerBound)

    // The kill switch skips the query entirely: no request, no descriptor read.
    let disabledController = SetBMockTerminalController(
      isTTY: true, readResponses: [Array("\u{1B}[?255u\(deviceAttributes)".utf8)])
    let disabledReads = LockedBox(0)
    disabledController.onRead = { disabledReads.withLock { $0 += 1 } }
    let disabledHost = makeSetBHost(
      controller: disabledController,
      environment: ["TERM": "xterm-kitty", "SWIFTTUI_KITTY_KEYBOARD": "0"])
    disabledHost.capabilityProbe.hasProbedAppearance = true
    try disabledHost.enableRawMode()
    defer { try? disabledHost.disableRawMode() }
    #expect(!disabledController.writes.joined().contains("\u{1B}[?u"))
    #expect(!disabledController.writes.joined().contains("\u{1B}[>1u"))
    #expect(disabledReads.value == 0)
  }

  @Test func setB090SceneTitlesCollideAfterNormalizationAndCanonicalEquivalence() throws {
    // Hypothesis: titles that normalize to one identifier, or that are canonically equivalent
    // Unicode strings, can slip past launch validation, while case-distinct titles can be
    // rejected as duplicates.
    #expect(WindowIdentifier("Main ") == WindowIdentifier("Main"))
    #expect(WindowIdentifier("main") != WindowIdentifier("Main"))
    #expect(WindowIdentifier("Ma in").rawValue == "Ma-in")
    #expect(WindowIdentifier("Ma in") == WindowIdentifier("Ma/in"))
    #expect(WindowIdentifier("\u{00A0}Main\t").rawValue == "Main")
    #expect(WindowIdentifier("   ").rawValue == "window")
    #expect(WindowIdentifier("").rawValue == "window")

    let composed = WindowIdentifier("Caf\u{E9}")
    let decomposed = WindowIdentifier("Cafe\u{301}")
    #expect(composed == decomposed)
    #expect(composed.hashValue == decomposed.hashValue)
    #expect(!composed.rawValue.utf8.elementsEqual(decomposed.rawValue.utf8))

    let trailing = collectWindowSceneDescriptors(from: SetBTrailingSpaceApp().body)
    let trailingIDs = trailing.map(\.id)
    #expect(trailingIDs == [WindowIdentifier("Main"), WindowIdentifier("Main")])
    #expect(throws: AppLaunchError.duplicateSceneIdentifier(WindowIdentifier("Main"))) {
      try validateWindowSceneIdentifiers(trailing)
    }

    let blank = collectWindowSceneDescriptors(from: SetBBlankTitleApp().body)
    #expect(throws: AppLaunchError.duplicateSceneIdentifier(WindowIdentifier("window"))) {
      try validateWindowSceneIdentifiers(blank)
    }

    let accented = collectWindowSceneDescriptors(from: SetBAccentApp().body)
    #expect(throws: AppLaunchError.duplicateSceneIdentifier(composed)) {
      try validateWindowSceneIdentifiers(accented)
    }

    let cased = collectWindowSceneDescriptors(from: SetBCaseApp().body)
    let casedIDs = cased.map(\.id)
    #expect(casedIDs == [WindowIdentifier("Main"), WindowIdentifier("main")])
    try validateWindowSceneIdentifiers(cased)
  }
}

// MARK: - Scene fixtures

private struct SetBTrailingSpaceApp: App {
  var body: some Scene {
    WindowGroup("Main") { EmptyView() }
    WindowGroup("Main ") { EmptyView() }
  }
}

private struct SetBBlankTitleApp: App {
  var body: some Scene {
    WindowGroup { EmptyView() }
    WindowGroup("   ") { EmptyView() }
  }
}

private struct SetBAccentApp: App {
  var body: some Scene {
    WindowGroup("Caf\u{E9}") { EmptyView() }
    WindowGroup("Cafe\u{301}") { EmptyView() }
  }
}

private struct SetBCaseApp: App {
  var body: some Scene {
    WindowGroup("Main") { EmptyView() }
    WindowGroup("main") { EmptyView() }
  }
}

private struct SetBQueryFailure: Error {}

// MARK: - Host construction

@MainActor
private func makeSetBHost(
  controller: SetBMockTerminalController,
  gate: SetBSpyInputSuspensionGate? = nil,
  environment: [String: String],
  capabilityProfile: TerminalCapabilityProfile? = .trueColor
) -> TerminalHost {
  let host = TerminalHost(
    inputFileDescriptor: 0,
    outputFileDescriptor: 1,
    fallbackSize: .init(width: 80, height: 24),
    controller: controller,
    capabilityProfile: capabilityProfile,
    environment: environment
  )
  host.inputSuspensionGate = gate
  return host
}

// MARK: - Mock controller (copied shape from TerminalGraphicsProtocolTests)

/// Scripted TTY: each `read` dequeues one chunk and returns `[]` once the script is exhausted, so
/// probe timeouts cost no wall-clock time.
private final class SetBMockTerminalController: TerminalControlling {
  private let isTTYValue: Bool
  private let cellPixelSizeValue: PixelSize?
  private let queuedReadResponsesStorage: LockedBox<[[UInt8]]>
  private let writesStorage = LockedBox<[String]>([])
  private let onReadStorage = LockedBox<(@Sendable () -> Void)?>(nil)

  /// Observes every `read(from:maxBytes:timeoutMilliseconds:)` call.
  var onRead: (@Sendable () -> Void)? {
    get { onReadStorage.value }
    set { onReadStorage.value = newValue }
  }

  var writes: [String] { writesStorage.value }

  init(
    isTTY: Bool,
    readResponses: [[UInt8]] = [],
    cellPixelSize: PixelSize? = nil
  ) {
    isTTYValue = isTTY
    cellPixelSizeValue = cellPixelSize
    queuedReadResponsesStorage = LockedBox(readResponses)
  }

  func isATTY(_: Int32) -> Bool {
    isTTYValue
  }

  func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
    TerminalModeSnapshot()
  }

  func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> PixelSize? {
    cellPixelSizeValue
  }

  func write(_ output: String, to _: Int32) throws {
    writesStorage.withLock { $0.append(output) }
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    onReadStorage.value?()
    return queuedReadResponsesStorage.withLock { queuedReadResponses in
      guard !queuedReadResponses.isEmpty else {
        return []
      }
      return queuedReadResponses.removeFirst()
    }
  }
}

// MARK: - Spy suspension gate (copied shape, plus nesting-depth tracking)

/// Records engagements, the live suspension depth, and the deepest nesting seen, so a probe can
/// assert that every replay happens inside exactly one suspension window.
private final class SetBSpyInputSuspensionGate: TerminalInputSuspending {
  private let state = LockedBox<(engagements: Int, depth: Int, maxDepth: Int)>((0, 0, 0))
  private let replayStorage = LockedBox<[UInt8]>([])

  var replayed: [UInt8] { replayStorage.value }
  var engagements: Int { state.value.engagements }
  var isSuspended: Bool { state.value.depth > 0 }
  var maxDepth: Int { state.value.maxDepth }

  func replayProbeInput(_ bytes: [UInt8]) {
    #expect(isSuspended, "probe bytes may only be replayed inside a suspension window")
    replayStorage.withLock { $0.append(contentsOf: bytes) }
  }

  func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T {
    state.withLock {
      $0.engagements += 1
      $0.depth += 1
      $0.maxDepth = max($0.maxDepth, $0.depth)
    }
    defer { state.withLock { $0.depth -= 1 } }
    return try body()
  }
}

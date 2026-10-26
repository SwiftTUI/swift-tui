@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F1 pass 3 (STUI-1282), area 5: terminal capability refinement across
/// environment combinations the wave hunts did not take (STUI-1224, 1225,
/// 1247). Contract: `Environment-Variables.md:26-56`.
@Suite
struct AdversarialSetCCapabilityTests {
  private func detect(_ environment: [String: String]) -> TerminalCapabilityProfile {
    TerminalCapabilityProfile.detectPOSIXTerminal(environment: environment, isTTY: true)
  }

  @Test func setC269VSCodeTrueColorLinksWithoutSync() {
    let p = detect(["TERM": "xterm-256color", "COLORTERM": "truecolor", "TERM_PROGRAM": "vscode"])
    #expect(p.colorLevel == .trueColor)
    #expect(p.supportsHyperlinks)
    #expect(!p.supportsSynchronizedOutput)
  }

  @Test func setC270TmuxProgramOutranksVTE() {
    let p = detect(["TERM": "xterm-direct", "TERM_PROGRAM": "tmux", "VTE_VERSION": "7600"])
    #expect(p.colorLevel == .trueColor)
    #expect(!p.supportsHyperlinks)
  }

  @Test func setC271EmptyProgramDoesNotOutrankWT() {
    let p = detect(["TERM": "xterm-256color", "WT_SESSION": "abc", "TERM_PROGRAM": ""])
    #expect(p.supportsHyperlinks)
    #expect(p.colorLevel == .ansi256)
  }

  @Test func setC272EmptyNoColorKeepsDirectColor() {
    let p = detect(["TERM": "xterm-direct", "NO_COLOR": ""])
    #expect(p.colorLevel == .trueColor)
    #expect(p.emitsStyleEscapeSequences)
  }

  @Test func setC273ExplicitCTypeOverridesUTF8Lang() {
    let p = detect([
      "TERM": "xterm-direct", "LC_ALL": "", "LC_CTYPE": "C", "LANG": "en_US.UTF-8",
    ])
    #expect(p.glyphLevel == .ascii)
    #expect(p.colorLevel == .trueColor)
  }

  @Test func setC274DottedScreenKeepsOwnCapabilities() {
    let p = detect(["TERM": "screen.xterm-256color", "VTE_VERSION": "7600"])
    #expect(!p.supportsHyperlinks)
    #expect(p.supportsMouseReporting)
    #expect(p.colorLevel == .ansi256)
  }

  @Test func setC275IncreasedContrastKeepsDirectColor() {
    var configuration = RuntimeConfiguration()
    configuration.accessibilityPreferences.contrast = .increased
    let p = detect(["TERM": "xterm-direct"]).applying(configuration)
    #expect(p.colorLevel == .trueColor)
    #expect(p.emitsStyleEscapeSequences)
  }

  @Test func setC276GhosttyFamilyIgnoresVSCodeMarker() {
    let p = detect(["TERM": "xterm-ghostty", "TERM_PROGRAM": "vscode"])
    #expect(p.supportsHyperlinks)
    #expect(p.supportsSynchronizedOutput)
    #expect(p.supportsMouseReporting)
  }
}

import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite("Adversarial set A: independent host policy boundaries")
struct AdversarialSetAHostPolicyTests {
  // Hypothesis: UTF-8 in a lower-priority locale overrides an explicit LC_ALL=C.
  // Locale precedence: https://www.gnu.org/software/libc/manual/html_node/Standard-Environment.html
  @Test func setA291LocaleOverrideWinsOverInheritedUTF8() {
    let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: [
        "TERM": "xterm", "LC_ALL": "C", "LC_CTYPE": "en_US.UTF-8", "LANG": "en_US.UTF-8",
      ],
      isTTY: true)
    withKnownIssue("STUI-962: locale detection ignores LC_ALL precedence") {
      #expect(profile.glyphLevel == .ascii)
    }
    #expect(profile.supportsMouseReporting)
  }

  // Hypothesis: forcing color on a pipe accidentally re-enables terminal input/output protocols.
  @Test func setA292ForcedPipeColorDoesNotInventInteractiveCapabilities() {
    let environment = ["TERM": "kitty", "FORCE_COLOR": "1", "LANG": "C.UTF-8"]
    let config = RuntimeConfiguration.detect(environment: environment, isStdoutTTY: false)
    let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: environment, isTTY: false
    )
    .applying(config)
    #expect(profile.colorLevel == .ansi16)
    #expect(profile.emitsStyleEscapeSequences)
    #expect(!profile.supportsMouseReporting && !profile.supportsHyperlinks)
    #expect(!profile.supportsScrollRegions && !profile.supportsSynchronizedOutput)
  }

  // Hypothesis: inherited TERM_PROGRAM punches through an explicitly named multiplexer.
  @Test func setA293MultiplexerKeepsAuthorityOverOuterTerminalIdentity() {
    let outer = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-256color", "TERM_PROGRAM": "WezTerm"], isTTY: true)
    #expect(outer.supportsHyperlinks && outer.supportsSynchronizedOutput)
    let inner = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "screen-256color", "TERM_PROGRAM": "WezTerm"], isTTY: true)
    #expect(inner.supportsMouseReporting)
    #expect(!inner.supportsHyperlinks && !inner.supportsSynchronizedOutput)
  }

  // Hypothesis: NO_COLOR is incorrectly treated as disabling independent hyperlink/mouse protocols.
  @Test func setA294ColorOptOutLeavesIndependentProtocolsAvailable() {
    let environment = ["TERM": "kitty", "NO_COLOR": "1", "FORCE_COLOR": "3"]
    let config = RuntimeConfiguration.detect(environment: environment, isStdoutTTY: true)
    let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: environment, isTTY: true
    )
    .applying(config)
    #expect(profile.colorLevel == .none && !profile.emitsStyleEscapeSequences)
    #expect(profile.supportsMouseReporting && profile.supportsHyperlinks)
    #expect(profile.supportsSynchronizedOutput && profile.supportsScrollRegions)
  }

  // Hypothesis: an explicit no-open preference is lost when web scene and ephemeral port are set.
  @Test func setA295BrowserLaunchOptOutSurvivesWebSceneConfiguration() throws {
    let config = RuntimeConfiguration.detect(
      environment: [
        "SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "0", "SWIFTTUI_OPEN": "1",
        "SWIFTTUI_NO_OPEN": "1", "SWIFTTUI_WEB_SCENE": "dashboard",
      ], isStdoutTTY: true)
    let web = try #require(config.web)
    #expect(!web.openBrowser)
    #expect(web.port == 0)
    #expect(web.sceneID == WindowIdentifier("dashboard"))
  }

  // Hypothesis: overflow in one port setting corrupts the other independently configured server.
  @Test func setA296OverflowingCompanionPortDoesNotDiscardValidWebPort() throws {
    let config = RuntimeConfiguration.detect(
      environment: [
        "SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "65535",
        "SWIFTTUI_COMPANION_PORT": String(repeating: "9", count: 200),
      ], isStdoutTTY: true)
    #expect(try #require(config.web).port == 65535)
    #expect(config.companionPort == 0)
  }

  // Hypothesis: malformed optional preferences become explicit false and suppress host defaults.
  @Test func setA297MalformedPreferenceRemainsUnspecified() {
    let config = RuntimeConfiguration.detect(
      environment: [
        "SWIFTTUI_INCREASE_CONTRAST": "perhaps", "SWIFTTUI_REDUCE_TRANSPARENCY": " ",
        "SWIFTTUI_DIFFERENTIATE_WITHOUT_COLOR": "TRUE",
      ], isStdoutTTY: true)
    #expect(config.accessibilityPreferences.contrast == nil)
    #expect(config.accessibilityPreferences.reduceTransparency == nil)
    #expect(config.accessibilityPreferences.differentiateWithoutColor == true)
  }

  // Hypothesis: stale Windows Terminal metadata overrides a foreign TERM after a nested session.
  @Test func setA298ForeignWindowsTermConstrainsInheritedSessionMetadata() {
    let profile = TerminalCapabilityProfile.detectWindowsConsole(
      environment: ["TERM": "vt100", "WT_SESSION": "inherited", "LANG": "C"], isTTY: true)
    #expect(profile.glyphLevel == .unicode)
    #expect(profile.colorLevel == .ansi16)
    #expect(!profile.supportsHyperlinks && !profile.supportsSynchronizedOutput)
    #expect(!profile.supportsMouseReporting)
  }

  // Hypothesis: terminal-family substring matching grants rich protocols to unrelated TERM names.
  @Test func setA299TerminalFamilyLookalikesDoNotAcquireRichProtocols() {
    let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "not-kitty-256color", "TERM_PROGRAM": "kitty"], isTTY: true)
    #expect(profile.colorLevel == .ansi256)
    #expect(!profile.supportsMouseReporting && !profile.supportsHyperlinks)
    #expect(!profile.supportsSynchronizedOutput)
  }

  // Hypothesis: Ctrl-letter case normalization leaks to bare keys or discards extra modifiers.
  @Test func setA300ExitChordCaseFoldingKeepsModifierBoundaries() {
    let exits = ExitKeyBindings([KeyPress(.character("Q"), modifiers: .ctrl)])
    #expect(exits.contains(KeyPress(.character("q"), modifiers: .ctrl)))
    #expect(!exits.contains(KeyPress(.character("q"), modifiers: [.ctrl, .alt])))
    #expect(!exits.contains(KeyPress(.character("q"))))
    let bare = ExitKeyBindings([KeyPress(.character("Q"))])
    #expect(!bare.contains(KeyPress(.character("q"))))
  }
}

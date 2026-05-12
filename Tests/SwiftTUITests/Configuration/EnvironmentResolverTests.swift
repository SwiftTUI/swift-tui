import Testing

@testable import SwiftTUIRuntime

struct EnvironmentResolverTests {
  @Test("Empty environment + TTY produces default-ish configuration")
  func emptyEnvironmentTTY() {
    let configuration = RuntimeConfiguration.detect(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .auto)
    #expect(configuration.glyphs == .ascii)  // No UTF-8 in locale → ascii fallback (matches TerminalCapabilityProfile.detect)
    #expect(configuration.motion == .normal)
    #expect(configuration.debug == false)
  }

  @Test("Empty environment + non-TTY suppresses color and motion")
  func emptyEnvironmentNoTTY() {
    let configuration = RuntimeConfiguration.detect(environment: [:], isStdoutTTY: false)
    #expect(configuration.color == .never)
    #expect(configuration.motion == .reduced)
  }

  @Test("NO_COLOR forces color off")
  func noColorEnvVar() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["NO_COLOR": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("FORCE_COLOR with non-TTY still forces color on")
  func forceColorEnvVar() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["FORCE_COLOR": "1"], isStdoutTTY: false)
    #expect(configuration.color == .always)
  }

  @Test("NO_COLOR wins over FORCE_COLOR")
  func noColorWinsOverForceColor() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["NO_COLOR": "1", "FORCE_COLOR": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("CLICOLOR=0 disables color")
  func cliColorZero() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["CLICOLOR": "0"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("CLICOLOR_FORCE=1 forces color on")
  func cliColorForce() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["CLICOLOR_FORCE": "1"], isStdoutTTY: false)
    #expect(configuration.color == .always)
  }

  @Test("CI=true triggers reduce-motion and no-progress without accessible output")
  func ciTriggersReducedMotion() {
    let configuration = RuntimeConfiguration.detect(environment: ["CI": "true"], isStdoutTTY: true)
    #expect(configuration.motion == .reduced)
    #expect(configuration.noProgress == true)
    #expect(configuration.output == .tui)
  }

  @Test("LANG=C forces ASCII glyphs")
  func langCForcesAscii() {
    let configuration = RuntimeConfiguration.detect(environment: ["LANG": "C"], isStdoutTTY: true)
    #expect(configuration.glyphs == .ascii)
  }

  @Test("LANG with UTF-8 enables unicode glyphs")
  func langUtf8EnablesUnicode() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["LANG": "en_US.UTF-8"], isStdoutTTY: true)
    #expect(configuration.glyphs == .unicode)
  }

  @Test("SWIFTTUI_ACCESSIBLE=1 sets accessible output mode and implied policy")
  func swiftTUIAccessible() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_ACCESSIBLE": "1", "LANG": "en_US.UTF-8"], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
    #expect(configuration.noProgress == true)
    #expect(configuration.linear == true)
  }

  @Test("SWIFTTUI_ASCII=1 sets ASCII glyphs")
  func swiftTUIAscii() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_ASCII": "1"], isStdoutTTY: true)
    #expect(configuration.glyphs == .ascii)
  }

  @Test("SWIFTTUI_REDUCE_MOTION=1 sets reduced motion")
  func swiftTUIReduceMotion() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_REDUCE_MOTION": "1"], isStdoutTTY: true)
    #expect(configuration.motion == .reduced)
  }

  @Test("SWIFTTUI_PLAIN=1 implies no-color, ascii, reduce-motion")
  func swiftTUIPlain() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_PLAIN": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
  }

  @Test("SWIFTTUI_DEBUG=1 sets debug=true")
  func swiftTUIDebug() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_DEBUG": "1"], isStdoutTTY: true)
    #expect(configuration.debug == true)
  }

  @Test("SWIFTTUI_VERBOSE=2 sets verbosity to .verbose(level: 2)")
  func swiftTUIVerbose() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_VERBOSE": "2"], isStdoutTTY: true)
    #expect(configuration.verbosity == .verbose(level: 2))
  }

  @Test("SWIFTTUI_QUIET=1 sets verbosity to .quiet")
  func swiftTUIQuiet() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_QUIET": "1"], isStdoutTTY: true)
    #expect(configuration.verbosity == .quiet)
  }

  @Test("SWIFTTUI_WEB=1 with default port produces WebConfig")
  func swiftTUIWeb() {
    let configuration = RuntimeConfiguration.detect(
      environment: [
        "SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "9999", "SWIFTTUI_BIND": "0.0.0.0",
        "SWIFTTUI_NO_OPEN": "1",
      ],
      isStdoutTTY: true)
    #expect(configuration.web?.port == 9999)
    #expect(configuration.web?.bind == "0.0.0.0")
    #expect(configuration.web?.openBrowser == false)
  }

  @Test("SWIFTTUI_JSON=1 sets output to .json")
  func swiftTUIJson() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_JSON": "1"], isStdoutTTY: true)
    #expect(configuration.output == .json)
  }

  @Test("SWIFTTUI_LINEAR=1 selects accessible linear output")
  func swiftTUILinear() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_LINEAR": "1", "LANG": "en_US.UTF-8"], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
    #expect(configuration.noProgress == true)
    #expect(configuration.linear == true)
  }

  @Test("SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1 sets cursorFollowsFocus=true")
  func swiftTUICursorFollowsFocus() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_CURSOR_FOLLOWS_FOCUS": "1"], isStdoutTTY: true)
    #expect(configuration.cursorFollowsFocus == true)
  }

  @Test("SWIFTTUI_NO_PROGRESS=1 sets noProgress=true without CI")
  func swiftTUINoProgressWithoutCI() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_NO_PROGRESS": "1"], isStdoutTTY: true)
    #expect(configuration.noProgress == true)
  }

  @Test("CI=true SWIFTTUI_REDUCE_MOTION=0 turns motion back on (explicit env override)")
  func ciWithExplicitMotionOff() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["CI": "true", "SWIFTTUI_REDUCE_MOTION": "0"], isStdoutTTY: true)
    #expect(configuration.motion == .normal)
  }

  @Test("CI=true SWIFTTUI_NO_PROGRESS=0 re-enables progress (explicit env override)")
  func ciWithExplicitProgressOn() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["CI": "true", "SWIFTTUI_NO_PROGRESS": "0"], isStdoutTTY: true)
    #expect(configuration.noProgress == false)
  }

  @Test("SWIFTTUI_JSON wins over SWIFTTUI_ACCESSIBLE when both set")
  func swiftTUIJsonBeatsAccessible() {
    let configuration = RuntimeConfiguration.detect(
      environment: [
        "SWIFTTUI_ACCESSIBLE": "1",
        "SWIFTTUI_JSON": "1",
        "LANG": "en_US.UTF-8",
      ], isStdoutTTY: true)
    #expect(configuration.output == .json)
    #expect(configuration.glyphs == .unicode)
    #expect(configuration.motion == .normal)
    #expect(configuration.noProgress == false)
    #expect(configuration.linear == false)
  }

  @Test("SWIFTTUI_JSON wins over SWIFTTUI_LINEAR when both set")
  func swiftTUIJsonBeatsLinear() {
    let configuration = RuntimeConfiguration.detect(
      environment: [
        "SWIFTTUI_LINEAR": "1",
        "SWIFTTUI_JSON": "1",
        "LANG": "en_US.UTF-8",
      ], isStdoutTTY: true)
    #expect(configuration.output == .json)
    #expect(configuration.glyphs == .unicode)
    #expect(configuration.motion == .normal)
    #expect(configuration.noProgress == false)
    #expect(configuration.linear == false)
  }

  @Test("SWIFTTUI_ACCESSIBLE=1 implications ignore explicit env opt-outs")
  func swiftTUIAccessibleIgnoresEnvOptOuts() {
    let configuration = RuntimeConfiguration.detect(
      environment: [
        "SWIFTTUI_ACCESSIBLE": "1",
        "SWIFTTUI_REDUCE_MOTION": "0",
        "SWIFTTUI_NO_PROGRESS": "0",
        "LANG": "en_US.UTF-8",
      ], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
    #expect(configuration.noProgress == true)
    #expect(configuration.linear == true)
  }
}

import Testing
@testable import SwiftTUI

struct EnvironmentResolverTests {
  @Test("Empty environment + TTY produces default-ish configuration")
  func emptyEnvironmentTTY() {
    let configuration = RuntimeConfiguration.detect(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .auto)
    #expect(configuration.glyphs == .ascii) // No UTF-8 in locale → ascii fallback (matches TerminalCapabilityProfile.detect)
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
    let configuration = RuntimeConfiguration.detect(environment: ["NO_COLOR": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("FORCE_COLOR with non-TTY still forces color on")
  func forceColorEnvVar() {
    let configuration = RuntimeConfiguration.detect(environment: ["FORCE_COLOR": "1"], isStdoutTTY: false)
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
    let configuration = RuntimeConfiguration.detect(environment: ["CLICOLOR": "0"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("CLICOLOR_FORCE=1 forces color on")
  func cliColorForce() {
    let configuration = RuntimeConfiguration.detect(environment: ["CLICOLOR_FORCE": "1"], isStdoutTTY: false)
    #expect(configuration.color == .always)
  }

  @Test("CI=true triggers reduce-motion and no-progress")
  func ciTriggersReducedMotion() {
    let configuration = RuntimeConfiguration.detect(environment: ["CI": "true"], isStdoutTTY: true)
    #expect(configuration.motion == .reduced)
    #expect(configuration.noProgress == true)
  }

  @Test("LANG=C forces ASCII glyphs")
  func langCForcesAscii() {
    let configuration = RuntimeConfiguration.detect(environment: ["LANG": "C"], isStdoutTTY: true)
    #expect(configuration.glyphs == .ascii)
  }

  @Test("LANG with UTF-8 enables unicode glyphs")
  func langUtf8EnablesUnicode() {
    let configuration = RuntimeConfiguration.detect(environment: ["LANG": "en_US.UTF-8"], isStdoutTTY: true)
    #expect(configuration.glyphs == .unicode)
  }

  @Test("SWIFTTUI_ACCESSIBLE=1 sets accessible output mode")
  func swiftTUIAccessible() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_ACCESSIBLE": "1"], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("SWIFTTUI_ASCII=1 sets ASCII glyphs")
  func swiftTUIAscii() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_ASCII": "1"], isStdoutTTY: true)
    #expect(configuration.glyphs == .ascii)
  }

  @Test("SWIFTTUI_REDUCE_MOTION=1 sets reduced motion")
  func swiftTUIReduceMotion() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_REDUCE_MOTION": "1"], isStdoutTTY: true)
    #expect(configuration.motion == .reduced)
  }

  @Test("SWIFTTUI_PLAIN=1 implies no-color, ascii, reduce-motion")
  func swiftTUIPlain() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_PLAIN": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
  }

  @Test("SWIFTTUI_DEBUG=1 sets debug=true")
  func swiftTUIDebug() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_DEBUG": "1"], isStdoutTTY: true)
    #expect(configuration.debug == true)
  }

  @Test("SWIFTTUI_VERBOSE=2 sets verbosity to .verbose(level: 2)")
  func swiftTUIVerbose() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_VERBOSE": "2"], isStdoutTTY: true)
    #expect(configuration.verbosity == .verbose(level: 2))
  }

  @Test("SWIFTTUI_QUIET=1 sets verbosity to .quiet")
  func swiftTUIQuiet() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_QUIET": "1"], isStdoutTTY: true)
    #expect(configuration.verbosity == .quiet)
  }

  @Test("SWIFTTUI_WEB=1 with default port produces WebConfig")
  func swiftTUIWeb() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "9999", "SWIFTTUI_BIND": "0.0.0.0", "SWIFTTUI_NO_OPEN": "1"],
      isStdoutTTY: true)
    #expect(configuration.web?.port == 9999)
    #expect(configuration.web?.bind == "0.0.0.0")
    #expect(configuration.web?.openBrowser == false)
  }

  @Test("SWIFTTUI_START_IN=panel-id propagates")
  func swiftTUIStartIn() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_START_IN": "panel-id"], isStdoutTTY: true)
    #expect(configuration.startIn == "panel-id")
  }
}

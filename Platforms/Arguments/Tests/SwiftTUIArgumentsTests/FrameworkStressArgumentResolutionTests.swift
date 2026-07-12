import ArgumentParser
import SwiftTUI
import Testing

@testable import SwiftTUIArguments

@Suite("SwiftTUI argument resolution stress behavior", .serialized)
struct FrameworkStressArgumentResolutionTests {
  @Test("stress argument resolution 001 every Boolean flag parses together")
  func argumentResolution001EveryBooleanFlagParsesTogether() throws {
    let options = try SwiftTUIOptions.parse([
      "--no-color", "--force-color", "--accessible", "--ascii", "--reduce-motion", "--no-progress",
      "--plain", "--linear", "--cursor-follows-focus", "--json", "--web", "--open", "--quiet",
      "--debug",
    ])
    #expect(options.noColor && options.forceColor && options.accessible && options.ascii)
    #expect(options.reduceMotion && options.noProgress && options.plain && options.linear)
    #expect(options.cursorFollowsFocus && options.json && options.web && options.open)
    #expect(options.quiet && options.debug)
  }

  @Test("stress argument resolution 002 bundled verbose flags preserve count")
  func argumentResolution002BundledVerboseFlagsPreserveCount() throws {
    #expect(try SwiftTUIOptions.parse(["-vvv"]).verbose == 3)
  }

  @Test("stress argument resolution 003 equals syntax preserves option values")
  func argumentResolution003EqualsSyntaxPreservesOptionValues() throws {
    let options = try SwiftTUIOptions.parse(["--port=8123", "--bind=::1", "--scene=detail"])
    #expect(options.port == 8123 && options.bind == "::1" && options.scene == "detail")
  }

  @Test("stress argument resolution 004 duplicate Boolean flags are idempotent")
  func argumentResolution004DuplicateBooleanFlagsAreIdempotent() throws {
    #expect(try SwiftTUIOptions.parse(["--web", "--web"]).web)
  }

  @Test("stress argument resolution 005 negative web ports are rejected")
  func argumentResolution005NegativeWebPortsAreRejected() {
    #expect(throws: (any Error).self) { _ = try SwiftTUIOptions.parse(["--port", "-1"]) }
  }

  @Test("stress argument resolution 006 maximum TCP port parses")
  func argumentResolution006MaximumTCPPortParses() throws {
    #expect(try SwiftTUIOptions.parse(["--port", "65535"]).port == 65_535)
  }

  @Test("stress argument resolution 007 out-of-range TCP ports are rejected")
  func argumentResolution007OutOfRangeTCPPortsAreRejected() {
    #expect(throws: (any Error).self) { _ = try SwiftTUIOptions.parse(["--port", "65536"]) }
  }

  @Test("stress argument resolution 008 empty bind addresses are rejected")
  func argumentResolution008EmptyBindAddressesAreRejected() {
    #expect(throws: (any Error).self) { _ = try SwiftTUIOptions.parse(["--bind="]) }
  }

  @Test("stress argument resolution 009 empty scene identifiers are rejected")
  func argumentResolution009EmptySceneIdentifiersAreRejected() {
    #expect(throws: (any Error).self) { _ = try SwiftTUIOptions.parse(["--scene="]) }
  }

  @Test("stress argument resolution 010 port is inert without web mode")
  func argumentResolution010PortIsInertWithoutWebMode() throws {
    let options = try SwiftTUIOptions.parse(["--port", "9000"])
    #expect(options.runtimeConfiguration(environment: [:], isStdoutTTY: true).web == nil)
  }

  @Test("stress argument resolution 011 bind is inert without web mode")
  func argumentResolution011BindIsInertWithoutWebMode() throws {
    let options = try SwiftTUIOptions.parse(["--bind", "0.0.0.0"])
    #expect(options.runtimeConfiguration(environment: [:], isStdoutTTY: true).web == nil)
  }

  @Test("stress argument resolution 012 scene is inert without web mode")
  func argumentResolution012SceneIsInertWithoutWebMode() throws {
    let options = try SwiftTUIOptions.parse(["--scene", "detail"])
    #expect(options.runtimeConfiguration(environment: [:], isStdoutTTY: true).web == nil)
  }

  @Test("stress argument resolution 013 open is inert without web mode")
  func argumentResolution013OpenIsInertWithoutWebMode() throws {
    let options = try SwiftTUIOptions.parse(["--open"])
    #expect(options.runtimeConfiguration(environment: [:], isStdoutTTY: true).web == nil)
  }

  @Test("stress argument resolution 014 CLI web values replace the environment tuple")
  func argumentResolution014CLIWebValuesReplaceEnvironmentTuple() throws {
    let options = try SwiftTUIOptions.parse([
      "--web", "--port", "7000", "--bind", "::1", "--scene", "cli",
    ])
    let config = options.runtimeConfiguration(
      environment: [
        "SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "9000", "SWIFTTUI_BIND": "env",
        "SWIFTTUI_WEB_SCENE": "env",
      ], isStdoutTTY: true)
    #expect(config.web?.port == 7000 && config.web?.bind == "::1")
    #expect(config.web?.sceneID == WindowIdentifier("cli"))
  }

  @Test("stress argument resolution 015 CLI web zero port overrides environment port")
  func argumentResolution015CLIWebZeroPortOverridesEnvironmentPort() throws {
    let options = try SwiftTUIOptions.parse(["--web"])
    #expect(
      options.runtimeConfiguration(
        environment: ["SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "9000"], isStdoutTTY: true
      ).web?.port == 0)
  }

  @Test("stress argument resolution 016 CLI web default bind overrides environment bind")
  func argumentResolution016CLIWebDefaultBindOverridesEnvironmentBind() throws {
    let options = try SwiftTUIOptions.parse(["--web"])
    #expect(
      options.runtimeConfiguration(
        environment: ["SWIFTTUI_WEB": "1", "SWIFTTUI_BIND": "0.0.0.0"], isStdoutTTY: true
      ).web?.bind == "127.0.0.1")
  }

  @Test("stress argument resolution 017 CLI quiet overrides environment verbosity")
  func argumentResolution017CLIQuietOverridesEnvironmentVerbosity() throws {
    let options = try SwiftTUIOptions.parse(["--quiet"])
    #expect(
      options.runtimeConfiguration(environment: ["SWIFTTUI_VERBOSE": "9"], isStdoutTTY: true)
        .verbosity == .quiet)
  }

  @Test("stress argument resolution 018 CLI verbosity overrides environment quiet")
  func argumentResolution018CLIVerbosityOverridesEnvironmentQuiet() throws {
    let options = try SwiftTUIOptions.parse(["-vv"])
    #expect(
      options.runtimeConfiguration(environment: ["SWIFTTUI_QUIET": "1"], isStdoutTTY: true)
        .verbosity == .verbose(level: 2))
  }

  @Test("stress argument resolution 019 CLI debug survives false environment value")
  func argumentResolution019CLIDebugSurvivesFalseEnvironmentValue() throws {
    let options = try SwiftTUIOptions.parse(["--debug"])
    #expect(
      options.runtimeConfiguration(environment: ["SWIFTTUI_DEBUG": "0"], isStdoutTTY: true).debug)
  }

  @Test("stress argument resolution 020 no-progress remains explicit in JSON mode")
  func argumentResolution020NoProgressRemainsExplicitInJSONMode() throws {
    let options = try SwiftTUIOptions.parse(["--json", "--no-progress"])
    #expect(options.runtimeConfiguration(environment: [:], isStdoutTTY: true).noProgress)
  }

  @Test("stress argument resolution 021 ASCII remains explicit in JSON mode")
  func argumentResolution021ASCIIRemainsExplicitInJSONMode() throws {
    let options = try SwiftTUIOptions.parse(["--json", "--ascii"])
    #expect(
      options.runtimeConfiguration(environment: ["LANG": "en_US.UTF-8"], isStdoutTTY: true).glyphs
        == .ascii)
  }

  @Test("stress argument resolution 022 reduced motion remains explicit in JSON mode")
  func argumentResolution022ReducedMotionRemainsExplicitInJSONMode() throws {
    let options = try SwiftTUIOptions.parse(["--json", "--reduce-motion"])
    #expect(options.runtimeConfiguration(environment: [:], isStdoutTTY: true).motion == .reduced)
  }

  @Test("stress argument resolution 023 accessible mode preserves explicit forced color")
  func argumentResolution023AccessibleModePreservesExplicitForcedColor() throws {
    let options = try SwiftTUIOptions.parse(["--accessible", "--force-color"])
    #expect(options.runtimeConfiguration(environment: [:], isStdoutTTY: false).color == .always)
  }

  @Test("stress argument resolution 024 JSON clears CLI linear policy")
  func argumentResolution024JSONClearsCLILinearPolicy() throws {
    let options = try SwiftTUIOptions.parse(["--linear", "--json"])
    let config = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(config.output == .json)
    #expect(config.linear == false)
  }

  @Test("stress argument resolution 025 plain policy remains explicit in JSON mode")
  func argumentResolution025PlainPolicyRemainsExplicitInJSONMode() throws {
    let options = try SwiftTUIOptions.parse(["--plain", "--json"])
    let config = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(config.color == .never && config.glyphs == .ascii && config.motion == .reduced)
  }
}

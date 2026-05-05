import Testing
import SwiftTUI
@testable import SwiftTUIArguments

struct SwiftTUIOptionsResolutionTests {
  @Test("All defaults, empty env, TTY → auto color, unicode, normal motion")
  func defaultsTTY() throws {
    let options = try SwiftTUIOptions.parse([])
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .auto)
    #expect(configuration.glyphs == .ascii) // No UTF-8 in locale
    #expect(configuration.motion == .normal)
  }

  @Test("--no-color flag wins regardless of env or TTY")
  func cliNoColorWinsOverEnv() throws {
    var options = try SwiftTUIOptions.parse([])
    options.noColor = true
    let configuration = options.runtimeConfiguration(
      environment: ["FORCE_COLOR": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("--force-color flag forces color even on non-TTY")
  func cliForceColorOnNonTTY() throws {
    var options = try SwiftTUIOptions.parse([])
    options.forceColor = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: false)
    #expect(configuration.color == .always)
  }

  @Test("--no-color wins over --force-color")
  func cliNoColorWinsOverForceColor() throws {
    var options = try SwiftTUIOptions.parse([])
    options.noColor = true
    options.forceColor = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("--plain implies no-color, ascii, reduce-motion")
  func cliPlainImpliesAll() throws {
    var options = try SwiftTUIOptions.parse([])
    options.plain = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .never)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
  }

  @Test("--accessible sets output mode to .accessible")
  func cliAccessibleSetsOutput() throws {
    var options = try SwiftTUIOptions.parse([])
    options.accessible = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("--json sets output mode to .json")
  func cliJsonSetsOutput() throws {
    var options = try SwiftTUIOptions.parse([])
    options.json = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .json)
  }

  @Test("--accessible takes priority over --json when both set")
  func cliAccessibleBeatsJson() throws {
    var options = try SwiftTUIOptions.parse([])
    options.accessible = true
    options.json = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("--web --port 9000 --bind 0.0.0.0 produces WebConfig")
  func cliWebProducesWebConfig() throws {
    var options = try SwiftTUIOptions.parse([])
    options.web = true
    options.port = 9000
    options.bind = "0.0.0.0"
    options.noOpen = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.web?.port == 9000)
    #expect(configuration.web?.bind == "0.0.0.0")
    #expect(configuration.web?.openBrowser == false)
  }

  @Test("-vv produces verbosity .verbose(level: 2)")
  func cliVerboseLevelTwo() throws {
    var options = try SwiftTUIOptions.parse([])
    options.verbose = 2
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.verbosity == .verbose(level: 2))
  }

  @Test("--quiet produces verbosity .quiet")
  func cliQuietProducesQuiet() throws {
    var options = try SwiftTUIOptions.parse([])
    options.quiet = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.verbosity == .quiet)
  }

  @Test("--quiet wins over -v")
  func cliQuietBeatsVerbose() throws {
    var options = try SwiftTUIOptions.parse([])
    options.quiet = true
    options.verbose = 2
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.verbosity == .quiet)
  }

  @Test("Env var honored when CLI flag is default")
  func envVarHonoredWhenCLIDefault() throws {
    let options = try SwiftTUIOptions.parse([])
    let configuration = options.runtimeConfiguration(
      environment: ["SWIFTTUI_DEBUG": "1"], isStdoutTTY: true)
    #expect(configuration.debug == true)
  }

  @Test("CLI flag overrides env var")
  func cliOverridesEnv() throws {
    var options = try SwiftTUIOptions.parse([])
    options.debug = true
    let configuration = options.runtimeConfiguration(
      environment: ["SWIFTTUI_DEBUG": "0"], isStdoutTTY: true)
    #expect(configuration.debug == true)
  }

  @Test("--start-in passthrough")
  func cliStartInPassthrough() throws {
    var options = try SwiftTUIOptions.parse([])
    options.startIn = "search"
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.startIn == "search")
  }
}

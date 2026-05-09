import ArgumentParser
import Testing

@testable import SwiftTUIArguments

struct SwiftTUIOptionsParseTests {
  @Test("Parses with no arguments — all defaults")
  func parsesWithNoArguments() throws {
    let options = try SwiftTUIOptions.parse([])
    #expect(options.noColor == false)
    #expect(options.forceColor == false)
    #expect(options.accessible == false)
    #expect(options.ascii == false)
    #expect(options.reduceMotion == false)
    #expect(options.noProgress == false)
    #expect(options.plain == false)
    #expect(options.linear == false)
    #expect(options.cursorFollowsFocus == false)
    #expect(options.json == false)
    #expect(options.web == false)
    #expect(options.port == 0)
    #expect(options.bind == "127.0.0.1")
    #expect(options.open == false)
    #expect(options.verbose == 0)
    #expect(options.quiet == false)
    #expect(options.debug == false)
  }

  @Test("Parses --no-color --ascii --reduce-motion")
  func parsesAccessibilityFlags() throws {
    let options = try SwiftTUIOptions.parse(["--no-color", "--ascii", "--reduce-motion"])
    #expect(options.noColor == true)
    #expect(options.ascii == true)
    #expect(options.reduceMotion == true)
  }

  @Test("Parses --plain")
  func parsesPlain() throws {
    let options = try SwiftTUIOptions.parse(["--plain"])
    #expect(options.plain == true)
  }

  @Test("Parses --cursor-follows-focus")
  func parsesCursorFollowsFocus() throws {
    let options = try SwiftTUIOptions.parse(["--cursor-follows-focus"])
    #expect(options.cursorFollowsFocus == true)
  }

  @Test("Parses --web --port 9000 --bind 0.0.0.0 --open")
  func parsesWebFlags() throws {
    let options = try SwiftTUIOptions.parse([
      "--web", "--port", "9000", "--bind", "0.0.0.0", "--open",
    ])
    #expect(options.web == true)
    #expect(options.port == 9000)
    #expect(options.bind == "0.0.0.0")
    #expect(options.open == true)
  }

  @Test("Parses -v -v -v as verbose level 3")
  func parsesRepeatedVerboseShort() throws {
    let options = try SwiftTUIOptions.parse(["-v", "-v", "-v"])
    #expect(options.verbose == 3)
  }

  @Test("Parses --quiet")
  func parsesQuiet() throws {
    let options = try SwiftTUIOptions.parse(["--quiet"])
    #expect(options.quiet == true)
  }

  @Test("Parses --debug")
  func parsesDebug() throws {
    let options = try SwiftTUIOptions.parse(["--debug"])
    #expect(options.debug == true)
  }

  @Test("Unknown flag throws")
  func unknownFlagThrows() {
    #expect(throws: (any Error).self) {
      _ = try SwiftTUIOptions.parse(["--bogus-flag"])
    }
  }

  @Test("--start-in is not framework-owned")
  func startInIsNotFrameworkOwned() {
    #expect(throws: (any Error).self) {
      _ = try SwiftTUIOptions.parse(["--start-in", "panel-id"])
    }
  }
}

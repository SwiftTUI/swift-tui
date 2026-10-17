import Testing

@testable import SwiftTUIRuntime

// Adversarial set B, configuration parsing and wire budgets (038–040).
// STUI-901 (empty NO_COLOR), STUI-915 (out-of-range companion port) and the
// STUI-303 wire budget work all came from string inputs that were almost, but
// not quite, the expected shape. These cases probe the remaining near-misses:
// whitespace and spelled-out booleans, decorated port digits, and record
// budgets measured exactly at the byte boundary.
@Suite("Adversarial set B: configuration parsing")
struct AdversarialSetBConfigurationTests {
  @Test func setB038ColorPrecedenceFollowsTheCLICOLORAndFORCECOLORConventions() {
    func color(_ environment: [String: String], tty: Bool = true) -> RuntimeConfiguration.ColorMode
    {
      RuntimeConfiguration.detect(environment: environment, isStdoutTTY: tty).color
    }
    #expect(color(["NO_COLOR": " "]) == .never)
    #expect(color(["NO_COLOR": "false"]) == .never)
    #expect(color(["NO_COLOR": "\t"], tty: false) == .never)
    #expect(color(["CLICOLOR": "0", "CLICOLOR_FORCE": "1"], tty: false) == .always)
    #expect(color(["CLICOLOR": "0", "FORCE_COLOR": "1"], tty: false) == .always)
    #expect(color(["FORCE_COLOR": "0"], tty: false) == .never)
    #expect(color(["FORCE_COLOR": "false"], tty: false) == .never)
    #expect(color(["CLICOLOR_FORCE": "0", "NO_COLOR": ""]) == .auto)
    #expect(color(["CLICOLOR_FORCE": "0"], tty: false) == .never)
    #expect(color(["CLICOLOR": "1"], tty: false) == .never)
  }

  @Test func setB039DecoratedPortDigitsFallBackInsteadOfParsingPartially() {
    func ports(_ value: String) -> (companion: Int, web: Int?) {
      let configuration = RuntimeConfiguration.detect(
        environment: [
          "SWIFTTUI_COMPANION_PORT": value, "SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": value,
        ],
        isStdoutTTY: true)
      return (configuration.companionPort, configuration.web?.port)
    }
    for rejected in [" 8080", "8080\n", "0x1F90", "8080.0", "８０８０", "65535 ", "8_080", "٨٠٨٠"] {
      let parsed = ports(rejected)
      #expect(parsed.companion == 0, "\(rejected.debugDescription) → \(parsed.companion)")
      #expect(parsed.web == 0, "\(rejected.debugDescription) → \(String(describing: parsed.web))")
    }
    for (accepted, expected) in [("00065535", 65535), ("0", 0), ("-0", 0), ("1", 1)] {
      let parsed = ports(accepted)
      #expect(parsed.companion == expected, "\(accepted) → \(parsed.companion)")
      #expect(parsed.web == expected, "\(accepted) → \(String(describing: parsed.web))")
    }
  }

  @Test func setB040RecordBudgetsCountEveryByteExactlyOnce() throws {
    let limit = HostWireBudget.recordBytes
    let emoji = String(repeating: "\u{1F600}", count: (limit - 2) / 4)
    #expect(try HostWireBudget.jsonStringBytes(emoji) == 2 + 4 * ((limit - 2) / 4))
    #expect(throws: HostWireBudget.Exceeded.self) {
      try HostWireBudget.jsonStringBytes(emoji + "\u{1F600}")
    }
    let control = String(repeating: "\u{1F}", count: (limit - 2) / 6)
    #expect(try HostWireBudget.jsonStringBytes(control) == 2 + 6 * ((limit - 2) / 6))
    #expect(throws: HostWireBudget.Exceeded.self) {
      try HostWireBudget.jsonStringBytes(control + "\u{1F}")
    }
    let head = String(repeating: "a", count: limit / 2)
    let tail = String(repeating: "b", count: limit - head.utf8.count - 1)
    #expect(try HostWireBudget.collect([head, tail]).count == 2)
    #expect(try HostWireBudget.joined([head, tail]).utf8.count == limit)
    #expect(throws: HostWireBudget.Exceeded.self) {
      try HostWireBudget.collect([head, tail + "b"])
    }
    #expect(try HostWireBudget.collect([]).isEmpty)
    #expect(!HostWireBudget.admits(.init(width: -1, height: 1)))
    #expect(!HostWireBudget.admits(.init(width: 1, height: -1)))
    #expect(HostWireBudget.admits(.init(width: 1024, height: 64)))
    #expect(!HostWireBudget.admits(.init(width: 1024, height: 65)))
    #expect(!HostWireBudget.admits(.init(width: 1025, height: 1)))
    #expect(
      HostWireBudget.initialSize(.init(width: 2000, height: 1)) == .init(width: 80, height: 24))
    #expect(
      HostWireBudget.initialSize(.init(width: 1024, height: 64)) == .init(width: 1024, height: 64))
    let declared = HostWireCapabilities.fromDeclarationJSON("{\"styleAppend\":true}")
    #expect(declared?.styleAppend == true)
    #expect(
      HostWireCapabilities.fromDeclarationJSON("{\"styleAppend\":\"1\"}")?.styleAppend != true)
    #expect(HostWireCapabilities.fromDeclarationJSON("{\"styleAppend\":1}")?.styleAppend != true)
    #expect(HostWireCapabilities.fromDeclarationJSON("{\"styleAppend\":True}") == nil)
  }
}

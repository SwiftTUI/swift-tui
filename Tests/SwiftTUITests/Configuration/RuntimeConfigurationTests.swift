import Testing

@testable import SwiftTUIRuntime

struct RuntimeConfigurationTests {
  @Test("Default configuration uses auto color, unicode glyphs, normal motion")
  func defaultConfiguration() {
    let configuration = RuntimeConfiguration.default
    #expect(configuration.color == .auto)
    #expect(configuration.glyphs == .unicode)
    #expect(configuration.motion == .normal)
    #expect(configuration.output == .tui)
    #expect(configuration.verbosity == .normal)
    #expect(configuration.web == nil)
    #expect(configuration.debug == false)
    #expect(configuration.noProgress == false)
    #expect(configuration.linear == false)
    #expect(configuration.cursorFollowsFocus == false)
  }

  @Test("Configuration is Sendable across actor boundaries")
  func configurationIsSendable() async {
    let configuration = RuntimeConfiguration.default
    let captured: RuntimeConfiguration = await Task.detached { configuration }.value
    #expect(captured.color == .auto)
    #expect(captured == configuration)
  }
}

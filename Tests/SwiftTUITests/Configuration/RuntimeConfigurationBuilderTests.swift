import Testing

@testable import SwiftTUI

struct RuntimeConfigurationBuilderTests {
  @Test("Builder produces customized configuration")
  func builderProducesCustomized() {
    let configuration = RuntimeConfiguration.builder()
      .color(.never)
      .glyphs(.ascii)
      .motion(.reduced)
      .output(.accessible)
      .verbosity(.verbose(level: 2))
      .debug(true)
      .cursorFollowsFocus(true)
      .build()

    #expect(configuration.color == .never)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
    #expect(configuration.output == .accessible)
    #expect(configuration.verbosity == .verbose(level: 2))
    #expect(configuration.debug == true)
    #expect(configuration.cursorFollowsFocus == true)
  }

  @Test("Builder defaults match RuntimeConfiguration.default")
  func builderDefaults() {
    #expect(RuntimeConfiguration.builder().build() == .default)
  }

  @Test("Builder web() sets WebConfig")
  func builderWebConfig() {
    let configuration = RuntimeConfiguration.builder()
      .web(port: 8080, bind: "0.0.0.0", openBrowser: false)
      .build()
    #expect(configuration.web?.port == 8080)
    #expect(configuration.web?.bind == "0.0.0.0")
    #expect(configuration.web?.openBrowser == false)
  }

  @Test("Builder web() defaults browser open to false")
  func builderWebConfigDefaultsBrowserOpenToFalse() {
    let configuration = RuntimeConfiguration.builder()
      .web()
      .build()
    #expect(configuration.web?.openBrowser == false)
  }
}

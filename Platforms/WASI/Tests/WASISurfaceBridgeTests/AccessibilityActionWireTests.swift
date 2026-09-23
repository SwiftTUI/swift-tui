@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite struct AccessibilityActionWireTests {
  @Test func fragmentedRequestsPreserveTypedValuesAndOrder() {
    var parser = WebSurfaceInputParser()
    #expect(parser.feed(Array("\u{1E}accessibility:12%3Aroot:se".utf8)).events.isEmpty)
    let events = parser.feed(
      Array("tValue:text:A%3AB%0A%F0%9F%8C%8D\n\u{1E}accessibility:12%3Aroot:focus\n".utf8)
    ).events
    #expect(
      events == [
        .accessibility(.init(target: "12:root", action: .setValue(.text("A:B\n🌍")))),
        .accessibility(.init(target: "12:root", action: .focus)),
      ])
    #expect(
      parser.feed(Array("\u{1E}accessibility:t:setValue:boolean:false\n".utf8)).events == [
        .accessibility(.init(target: "t", action: .setValue(.boolean(false))))
      ])
    #expect(
      parser.feed(Array("\u{1E}accessibility:t:setValue:number:2.5\n".utf8)).events == [
        .accessibility(.init(target: "t", action: .setValue(.number(2.5))))
      ])
  }

  @Test func correlatedRequestsPreserveTheirIdentifier() {
    var parser = WebSurfaceInputParser()
    #expect(
      parser.feed(Array("\u{1E}accessibility:17:t:setValue:text:hello\n".utf8)).events == [
        .accessibility(.init(target: "t", action: .setValue(.text("hello")), requestID: 17))
      ])
    #expect(
      parser.feed(Array("\u{1E}accessibility:18:t:focus\n".utf8)).events == [
        .accessibility(.init(target: "t", action: .focus, requestID: 18))
      ])
  }

  @Test func malformedRequestsDoNotBecomeKeyboardInput() {
    for command in [
      "accessibility::activate", "accessibility:t:unknown", "accessibility:t:focus:extra",
      "accessibility:t:setValue", "accessibility:t:setValue:number:nan",
      "accessibility:t:setValue:number:inf", "accessibility:t:setValue:boolean:yes",
      "accessibility:%ZZ:activate", "accessibility:t:setValue:text:%ZZ",
    ] {
      var parser = WebSurfaceInputParser()
      #expect(parser.feed(Array("\u{1E}\(command)\n".utf8)).events.isEmpty)
    }
  }
}

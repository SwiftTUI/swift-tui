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

  @Test func namedActionsPreserveUnicodeAndCorrelation() {
    var parser = WebSurfaceInputParser()
    #expect(
      parser.feed(Array("\u{1E}accessibility:19:t:custom:name:Reset%3A%20%E2%98%85\n".utf8)).events
        == [
          .accessibility(.init(target: "t", action: .custom("Reset: ★"), requestID: 19))
        ])
  }

  @Test func assistiveFocusRemainsDistinctFromKeyboardFocus() {
    var parser = WebSurfaceInputParser()
    let events = parser.feed(
      Array(
        "\u{1E}accessibility:20:t:accessibilityFocus\n\u{1E}accessibility:21:t:accessibilityBlur\n"
          .utf8)
    ).events
    #expect(
      events == [
        .accessibility(.init(target: "t", action: .accessibilityFocus, requestID: 20)),
        .accessibility(.init(target: "t", action: .accessibilityBlur, requestID: 21)),
      ])
  }

  @Test func checkedIDsAndEveryFragmentBoundary() {
    for id in ["0", "00042", "18446744073709551615"] {
      for command in [
        "activate", "focus", "accessibilityFocus", "accessibilityBlur",
        "increment", "decrement", "custom:name:A%3AB", "setValue:text:A%0A%1E",
        "setValue:boolean:false", "setValue:number:2.5", "editText:text:a%F0%9F%98%80:1:3",
        "selectText:text:a%F0%9F%98%80:3:1",
      ] {
        let bytes = Array("\u{1E}accessibility:\(id):t:\(command)\n".utf8)
        var whole = WebSurfaceInputParser()
        let expected = whole.feed(bytes).events
        #expect(expected.count == 1)
        if case .accessibility(let request) = expected.first {
          #expect(request.requestID == UInt64(id))
        } else {
          Issue.record("expected exactly one accessibility action")
        }
        for split in 0...bytes.count {
          var parser = WebSurfaceInputParser()
          let actual =
            parser.feed(Array(bytes[..<split])).events
            + parser.feed(Array(bytes[split...])).events
          #expect(actual == expected)
          #expect(parser.flushTerminalInput().isEmpty)
        }
      }
    }
    for id in ["", "+1", "-1", "1_0", "１", "18446744073709551616", "000000000000000000000"] {
      var parser = WebSurfaceInputParser()
      #expect(parser.feed(Array("\u{1E}accessibility:\(id):t:activate\n".utf8)).events.isEmpty)
    }
  }

  @Test func malformedRequestsDoNotBecomeKeyboardInput() {
    for command in [
      "accessibility::activate", "accessibility:t:unknown", "accessibility:t:focus:extra",
      "accessibility:t:setValue", "accessibility:t:setValue:number:nan",
      "accessibility:t:setValue:number:inf", "accessibility:t:setValue:boolean:yes",
      "accessibility:t:custom:name:", "accessibility:t:custom:name:%ZZ",
      "accessibility:t:custom:text:Reset", "accessibility:%ZZ:activate",
      "accessibility:t:setValue:text:%ZZ",
      "accessibility:t:accessibilityFocus:extra", "accessibility:t:accessibilityBlur:extra",
    ] {
      var parser = WebSurfaceInputParser()
      #expect(parser.feed(Array("\u{1E}\(command)\n".utf8)).events.isEmpty)
    }
  }
}

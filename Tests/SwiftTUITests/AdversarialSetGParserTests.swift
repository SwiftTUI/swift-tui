@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite("Campaign F5 parser properties", .serialized)
struct AdversarialSetGParserTests {
  @Test(arguments: Array(1...20))
  func parser(id: Int) {
    setGCheck(id, setGNumbers) { n in
      let count = n[0] % 8 + 1
      let text = String(repeating: "abc", count: count)
      let x = n[0] % 8 + 1
      let y = n[1] % 8 + 1
      let modifier = n[2] % 7 + 2
      let modifiers = EventModifiers(rawValue: UInt8(modifier - 1))
      let esc = "\u{1B}"
      func paste(_ value: String) -> String { "\(esc)[200~\(value)\(esc)[201~" }
      let input: String
      let expected: [InputEvent]
      switch id {
      case 1:
        input = text
        expected = text.map { .key(KeyPress(.character($0))) }
      case 2:
        input = String(repeating: "\u{1}\u{9}\u{7F}", count: count)
        expected = Array(
          repeating: [.key(.character("a"), modifiers: .ctrl), .key(.tab), .key(.backspace)],
          count: count
        ).flatMap { $0 }
      case 3:
        let keys: [KeyEvent] = [.arrowUp, .arrowDown, .arrowRight, .arrowLeft]
        let index = n[0] % 4
        input = "\(esc)[\(Array("ABCD")[index])"
        expected = [.key(keys[index])]
      case 4:
        let index = n[0] % 4
        input = "\(esc)O\(Array("PQRS")[index])"
        expected = [.key(.functionKey(index + 1))]
      case 5:
        let codes = [1, 2, 3, 4, 5, 6]
        let keys: [KeyEvent] = [.home, .insert, .delete, .end, .pageUp, .pageDown]
        let index = n[0] % 6
        input = "\(esc)[\(codes[index])~"
        expected = [.key(keys[index])]
      case 6:
        input = "\(esc)[1;\(modifier)A"
        expected = [.key(.arrowUp, modifiers: modifiers)]
      case 7:
        input = "\(esc)[97;\(modifier)u"
        expected = [.key(.character("a"), modifiers: modifiers)]
      case 8...11:
        let code = id == 10 ? 64 + n[2] % 2 : id == 11 ? 35 : 0
        input = "\(esc)[<\(code);\(x);\(y)\(id == 9 ? "m" : "M")"
        let kind: MouseEvent.Kind =
          id == 8
          ? .down(.primary)
          : id == 9
            ? .up(.primary) : id == 10 ? .scrolled(deltaX: 0, deltaY: code == 64 ? -1 : 1) : .moved
        expected = [
          .mouse(MouseEvent(kind: kind, location: Point(x: Double(x - 1), y: Double(y - 1))))
        ]
      case 12:
        input = "\(esc)[I\(esc)[Oz"
        expected = [.key(.character("z"))]
      case 13...15:
        let payload =
          id == 13 ? text : id == 14 ? String(repeating: "界😀e\u{301}", count: count) : "x\(esc)[Ay"
        input = paste(payload)
        expected = [.paste(.init(content: payload))]
      case 16:
        input = paste(text) + paste("界")
        expected = [.paste(.init(content: text)), .paste(.init(content: "界"))]
      case 17...19:
        input =
          id == 17
          ? "\(esc)]0;\(text)\u{7}z"
          : id == 18 ? "\(esc)]0;\(text)\(esc)\\z" : "\(esc)P\(text)\(esc)\\z"
        expected = [.key(.character("z"))]
      default:
        input = String(repeating: "é界😀", count: count)
        expected = input.unicodeScalars.map { .key(.character(Character($0))) }
      }
      let bytes = Array(input.utf8)
      var whole = TerminalInputParser()
      let reference = whole.feed(bytes) + whole.flush()
      guard reference == expected else { return "whole feed: \(reference), expected \(expected)" }
      var partitioned = TerminalInputParser()
      var actual: [InputEvent] = []
      var offset = 0
      while offset < bytes.count {
        let end = min(bytes.count, offset + 1 + n[offset % n.count] % 4)
        actual += partitioned.feed(Array(bytes[offset..<end]))
        offset = end
      }
      actual += partitioned.flush()
      return actual == expected ? nil : "partitioned: \(actual), expected \(expected)"
    }
  }
}

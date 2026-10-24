@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore

@MainActor
@Suite("Campaign F5 text properties", .serialized)
struct AdversarialSetGTextTests {
  @Test(arguments: Array(21...40))
  func text(id: Int) {
    setGCheck(id, Gen<(String, Int)>.zip(setGText, .int(in: 2...12))) { value in
      let (source, width) = value
      let count = source.count
      let text: String
      switch id {
      case 21: text = String(repeating: "ab", count: count)
      case 22: text = String(repeating: "界", count: count)
      case 23: text = String(repeating: "😀", count: count)
      case 24: text = String(repeating: "e\u{301}", count: count)
      default: text = source
      }
      let unbounded = layoutText(for: text, width: nil)
      switch id {
      case 21...24:
        let expectedWidth = id == 24 ? count : 2 * count
        return unbounded.size.width == expectedWidth
          && unbounded.lines[0].clusters.count == text.count
          ? nil : "width/cluster mismatch: \(unbounded)"
      case 25:
        let widths: [Character: Int] = [
          "a": 1, "Z": 1, "界": 2, "😀": 2, "e\u{301}": 1, "🇨🇦": 2, "👩‍💻": 2, " ": 1, ".": 1,
        ]
        return unbounded.size.width == text.reduce(0, { $0 + (widths[$1] ?? -1000) })
          ? nil : "independent width mismatch"
      case 26:
        return layoutText(for: text, width: width).lines.allSatisfy { $0.cellWidth <= width }
          ? nil : "row exceeds width"
      case 27:
        let allowed = Set(text).union(["–", "…"])
        return layoutText(for: text, width: width).lines.flatMap(\.clusters).allSatisfy {
          allowed.contains($0.character)
        } ? nil : "cluster split or undocumented marker"
      case 28:
        let result = layoutText(for: String(repeating: "界", count: max(1, count)), width: 1)
        return result.lines.allSatisfy { $0.text == "…" } && result.wasTruncated
          ? nil : "oversized cluster replacement: \(result)"
      case 29...31:
        let mode: TextTruncationMode = id == 29 ? .tail : id == 30 ? .head : .middle
        let first = layoutText(for: text, width: width, lineLimit: 1, truncationMode: mode)
        let second = layoutText(
          for: first.lines[0].text, width: width, lineLimit: 1, truncationMode: mode)
        // Re-feeding rendered text gives an inserted ellipsis a source run;
        // provenance changes, while displayed graphemes and widths must not.
        let firstWidths = first.lines.map { $0.clusters.map(\.cellWidth) }
        let secondWidths = second.lines.map { $0.clusters.map(\.cellWidth) }
        return first.lines.map(\.text) == second.lines.map(\.text) && firstWidths == secondWidths
          ? nil : "truncation not idempotent: \(first) -> \(second)"
      case 32:
        let limit = width % 4 + 1
        return layoutText(for: text, width: width, lineLimit: limit).lines.count <= limit
          ? nil : "line limit exceeded"
      case 33: return unbounded.lines.map(\.text) == [text] ? nil : "unbounded text changed"
      case 34:
        return layoutText(for: text, width: 0).lines.allSatisfy { $0.cellWidth == 0 }
          ? nil : "zero width is visible"
      case 35:
        for newline in ["\r", "\n", "\r\n", "\u{85}", "\u{2028}", "\u{2029}"] {
          if layoutText(for: "a\(text)\(newline)\(text)b", width: nil).lines.map(\.text)
            != ["a" + text, text + "b"]
          {
            return "newline \(String(reflecting: newline))"
          }
        }
        return nil
      case 36:
        let clusters = clusterize(text)
        let budget = width % 4 + 1
        let full = wrapTextLineClusters(clusters, width: width, wrappingStrategy: .wordBoundary)
        let limited = wrapTextLineClusters(
          clusters, width: width, wrappingStrategy: .wordBoundary, rowBudget: budget)
        return limited == Array(full.prefix(budget)) ? nil : "row budget changed prefix"
      case 37:
        let content = text + "\r\n界"
        return wrappedTextCursorAnchors(content, width: width).count == content.count + 1
          ? nil : "anchor count"
      case 38:
        let anchors = wrappedTextCursorAnchors(text, width: width)
        return wrappedTextCursorAnchor(text, offset: -3, width: width) == anchors.first
          && wrappedTextCursorAnchor(text, offset: text.count + 8, width: width) == anchors.last
          ? nil : "anchor clamp"
      case 39:
        let options = TextLayoutOptions(width: width, lineLimit: 3)
        let first = layoutText(for: text, options: options)
        _ = layoutText(for: text + "other", options: options)
        let again = layoutText(for: text, options: options)
        return first == again && again == uncachedTextLayout(for: text, options: options)
          ? nil : "cached layout differs"
      default:
        for newline in ["\r", "\n", "\r\n", "\u{85}", "\u{2028}", "\u{2029}"] {
          let content = text + newline
          let anchor = wrappedTextCursorAnchor(content, offset: content.count, width: width)
          let rows = layoutText(for: content, width: width).lines.count
          if anchor != CellPoint(x: 0, y: rows - 1) {
            return "trailing newline anchor \(anchor), rows \(rows)"
          }
        }
        return nil
      }
    }
  }
}

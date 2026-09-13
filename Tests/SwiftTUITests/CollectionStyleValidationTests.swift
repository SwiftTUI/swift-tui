import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Collection presentation validation", .serialized)
struct CollectionStyleValidationTests {
  private func render(_ view: some View) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("CollectionValidation")),
      proposal: .init(width: 30, height: 14))
  }

  private func expectFallback(
    _ actual: RenderSnapshot, _ baseline: RenderSnapshot, family: String, resolves: Int = 1
  ) {
    #expect(actual.rasterSurface.lines == baseline.rasterSurface.lines)
    let issues = actual.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }
    #expect(issues.count == resolves)
    #expect(issues.first?.source == family)
    #expect(issues.first?.message.contains("invalid-test") == true)
    #expect(issues.first?.message.contains("automatic presentation") == true)
  }

  @Test("invalid List geometry falls back before reaching layout")
  func invalidListGeometry() {
    let view = List {
      Text("Alpha")
      Text("Beta")
    }
    let baseline = render(view)
    var invalid: [ListStylePresentation] = []
    for inset in [-1, Int.max] {
      var value = ListStylePresentation.plain
      value.contentInsets.leading = inset
      invalid.append(value)
      var chrome = CollectionContainerChromePresentation.insetGrouped
      chrome.insetAmount = inset
      value = .plain
      value.container = chrome
      invalid.append(value)
      chrome = .insetGrouped
      chrome.fillMode = .interior(strokeWidth: inset)
      value.container = chrome
      invalid.append(value)
      chrome = .insetGrouped
      chrome.geometry = .roundedRectangle(cornerRadius: inset)
      value.container = chrome
      invalid.append(value)
    }
    for width in [0, Int.max] {
      var value = ListStylePresentation.insetGrouped
      value.container?.strokeStyle.lineWidth = width
      invalid.append(value)
    }
    for value in invalid {
      expectFallback(render(view.listStyle(FixedList(value: value))), baseline, family: "ListStyle")
    }
  }

  @Test("all fifteen Table glyphs must occupy one printable cell")
  func invalidTableGlyphsAndInsets() {
    let view = Table(0..<2, id: \.self, columns: [.init("Value", width: 8)]) { Text("Row \($0)") }
    let baseline = render(view)
    let keys: [WritableKeyPath<TableBorderGlyphs, String>] = [
      \.topLeft, \.top, \.topJoin, \.topRight, \.left, \.columnJoin, \.right,
      \.middleLeft, \.middle, \.middleJoin, \.middleRight,
      \.bottomLeft, \.bottom, \.bottomJoin, \.bottomRight,
    ]
    for key in keys {
      for glyph in ["", "ab", "界", "\n", "\u{1B}", "\u{2028}"] {
        var value = TableStylePresentation.bordered
        value.borderGlyphs[keyPath: key] = glyph
        expectFallback(
          render(view.tableStyle(FixedTable(value: value))), baseline, family: "TableStyle")
      }
    }
    for inset in [-1, Int.max] {
      var value = TableStylePresentation.bordered
      value.contentInsets.trailing = inset
      expectFallback(
        render(view.tableStyle(FixedTable(value: value))), baseline, family: "TableStyle")
    }
    var valid = TableStylePresentation.bordered
    valid.borderGlyphs.top = " "
    valid.borderGlyphs.bottom = "e\u{301}"
    let custom = render(view.tableStyle(FixedTable(value: valid)))
    #expect(!custom.diagnostics.runtime.issues.contains { $0.code == "style.invalidPresentation" })
    #expect(custom.rasterSurface.lines != baseline.rasterSurface.lines)
  }

  private struct Item: Sendable {
    var id: Int
    var children: [Item]
  }

  @Test("Outline rejects row-breaking text and preserves custom widths")
  func outlineTextContract() {
    let view = OutlineGroup(
      [Item(id: 1, children: [.init(id: 2, children: [])])],
      id: \.id, children: \.children
    ) { Text("Row \($0.id)") }
    let baseline = render(view)
    let keys: [WritableKeyPath<OutlineStylePresentation, String>] = [
      \.continuingIndenter, \.emptyIndenter, \.branchConnector, \.leafConnector,
    ]
    for key in keys {
      for text in ["\n", "a\tb", "\u{85}", "\u{2029}", "\u{1B}[0m"] {
        var value = OutlineStylePresentation.plain
        value[keyPath: key] = text
        expectFallback(
          render(view.outlineStyle(FixedOutline(value: value))), baseline, family: "OutlineStyle",
          resolves: 2)
      }
    }
    let valid = OutlineStylePresentation(
      continuingIndenter: "界 ", emptyIndenter: "", branchConnector: "-- ", leafConnector: ">")
    let custom = render(view.outlineStyle(FixedOutline(value: valid)))
    #expect(!custom.diagnostics.runtime.issues.contains { $0.code == "style.invalidPresentation" })
    #expect(custom.rasterSurface.lines.joined().contains(">Row 2"))
  }
}

private struct FixedList: ListStyle {
  var value: ListStylePresentation
  var snapshotLabel: String { "invalid-test" }
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    value
  }
}

private struct FixedTable: TableStyle {
  var value: TableStylePresentation
  var snapshotLabel: String { "invalid-test" }
  func resolvePresentation(for configuration: TableStyleConfiguration) -> TableStylePresentation {
    value
  }
}

private struct FixedOutline: OutlineStyle {
  var value: OutlineStylePresentation
  var snapshotLabel: String { "invalid-test" }
  func resolvePresentation(for configuration: OutlineStyleConfiguration) -> OutlineStylePresentation
  { value }
}

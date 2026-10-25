import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct CollectionScrollBoundaryTests {
  @Test(
    "wheel and page scrolling visit the final row before and after a footer-only window",
    arguments: [false, true])
  func wheelVisitsLastRowBeforeFooter(usePageUp: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionBoundaryFooterWheel"), size: .init(width: 32, height: 8)
    ) {
      List {
        Section {
          ForEach(0..<3, id: \.self) { row in
            Text("«\(row)»").padding(.vertical, 1)
          }
        } header: {
          EmptyView()
        } footer: {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { line in Text("footer:\(line)") }
          }
        }
      }.listStyle(BoundaryCurrencyListStyle()).scrollIndicators(.hidden).focusable().frame(
        height: 4)
    }
    defer { harness.shutdown() }
    if usePageUp { _ = try harness.focusText("«0»") }
    let point = try #require(harness.point(forText: "«0»"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    try #require(harness.frame.contains("«1»"), "\(harness.frame)")
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    try #require(harness.frame.contains("«2»"), "\(harness.frame)")
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    try #require(harness.frame.contains("footer:3"), "\(harness.frame)")
    for row in (0..<3).reversed() {
      if usePageUp {
        _ = try harness.pressKey(KeyPress(.pageUp))
      } else {
        _ = try harness.scrollPointer(at: point, deltaY: -1)
      }
      try #require(harness.frame.contains("«\(row)»"), "\(harness.frame)")
    }
  }

  @Test("short tables retain a usable row with and without headers", arguments: [false, true])
  func smallTableSingleLineNavigation(showsHeaders: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionBoundarySmallTable"), size: .init(width: 32, height: 8)
    ) { BoundaryCurrencySmallTable(showsHeaders: showsHeaders) }
    defer { harness.shutdown() }
    _ = try harness.focusText("«0»")
    for row in 1..<10 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try #require(harness.frame.contains("«\(row)»"), "row=\(row)\n\(harness.frame)")
    }
    for row in (0..<9).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try #require(harness.frame.contains("«\(row)»"), "row=\(row)\n\(harness.frame)")
    }
  }

  @Test("identical commands retain the pending correction for an unrealized target")
  func repeatedProxyRequest() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionBoundaryRepeatedProxy"),
      size: .init(width: 32, height: 12)
    ) {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Button("Jump") {
            _ = proxy.scrollTo(50, anchor: .bottom)
            _ = proxy.scrollTo(50, anchor: .bottom)
          }
          List(0..<100, id: \.self) { row in BoundaryCurrencyRow(row: row) }
            .listStyle(BoundaryCurrencyListStyle()).scrollIndicators(.hidden).frame(height: 5)
        }
      }
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Jump")
    try #require(harness.frame.contains("«50»:0"), "\(harness.frame)")
  }

  @Test(arguments: [false, true], 4...12)
  func navigationWithIndicators(table: Bool, height: Int) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionBoundaryIndicators", "\(table)-\(height)"),
      size: .init(width: 32, height: 16)
    ) {
      BoundaryCurrencyRows(table: table, height: height)
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("«0»:0")
    for row in 1..<16 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try #require(
        harness.frame.contains("«\(row)»:0"),
        "down row=\(row), table=\(table), height=\(height)\n\(harness.frame)")
    }
    for row in (0..<15).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try #require(
        harness.frame.contains("«\(row)»:0"),
        "up row=\(row), table=\(table), height=\(height)\n\(harness.frame)")
    }
  }

  @Test(arguments: [false, true], 4...10)
  func proxyThroughTallRows(table: Bool, height: Int) throws {
    for anchor: UnitPoint? in [nil, .top, .center, .bottom] {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity(
          "CollectionBoundaryProxy", "\(table)-\(height)-\(String(describing: anchor))"),
        size: .init(width: 32, height: 16)
      ) {
        ScrollViewReader { proxy in
          VStack(alignment: .leading, spacing: 0) {
            Button("Jump") { _ = proxy.scrollTo(50, anchor: anchor) }
            if table {
              Table(0..<100, id: \.self, columns: [.init("Value", width: 20)]) { row in
                BoundaryCurrencyRow(row: row)
              }.tableHeaders(.hidden).frame(height: height)
            } else {
              List(0..<100, id: \.self) { row in BoundaryCurrencyRow(row: row) }
                .listStyle(BoundaryCurrencyListStyle()).frame(height: height)
            }
          }
        }
      }
      defer { harness.shutdown() }
      _ = try harness.clickText("Jump")
      try #require(
        harness.frame.contains("«50»:0"),
        "table=\(table) height=\(height) anchor=\(String(describing: anchor))\n\(harness.frame)")
    }
  }

  // MARK: - Numeric anchors and deltas (STUI-768, STUI-863)

  @Test("non-finite scroll anchors are ignored as if no anchor were given")
  func nonFiniteScrollAnchorsAreIgnored() async {
    await #expect(processExitsWith: .success) {
      try await MainActor.run {
        for list in [false, true] {
          let revealed = try numericScrollFrame(list: list, anchor: nil, name: "Reveal")
          let anchors = [
            UnitPoint(x: 0, y: .infinity), UnitPoint(x: .nan, y: 1),
            UnitPoint(x: 0, y: -.infinity), UnitPoint(x: .nan, y: .nan),
          ]
          for (index, anchor) in anchors.enumerated() {
            let frame = try numericScrollFrame(list: list, anchor: anchor, name: "Anchor\(index)")
            #expect(frame == revealed, "list=\(list) anchor=\(anchor)\n\(frame)")
          }
        }
      }
    }
  }

  @Test("huge finite scroll anchors clamp to the content edges")
  func hugeFiniteScrollAnchorsClamp() async {
    await #expect(processExitsWith: .success) {
      try await MainActor.run {
        for list in [false, true] {
          let below = try numericScrollFrame(
            list: list, anchor: UnitPoint(x: 0, y: 1e300), name: "Below")
          #expect(below.contains("«0»"), "list=\(list)\n\(below)")
          let above = try numericScrollFrame(
            list: list, anchor: UnitPoint(x: 0, y: -1e300), name: "Above")
          #expect(above.contains("«29»"), "list=\(list)\n\(above)")
        }
      }
    }
  }

  @Test("wheel and proxy scrolls by Int's edge deltas clamp to the content edges")
  func intEdgeScrollDeltasClamp() async {
    await #expect(processExitsWith: .success) {
      try await MainActor.run {
        for list in [false, true] {
          let harness = try StressRuntimeHarness(
            rootIdentity: testIdentity("CollectionBoundaryIntEdgeDelta", "\(list)"),
            size: .init(width: 32, height: 12)
          ) { NumericScrollFixture(list: list, anchor: nil) }
          defer { harness.shutdown() }
          let point = try #require(harness.point(forText: "«1»"))
          _ = try harness.scrollPointer(at: point, deltaY: 2)
          let wheeledDown = try harness.scrollPointer(at: point, deltaY: Int.max)
          #expect(wheeledDown.contains("«29»"), "list=\(list)\n\(wheeledDown)")
          let wheeledUp = try harness.scrollPointer(at: point, deltaY: Int.min)
          #expect(wheeledUp.contains("«0»"), "list=\(list)\n\(wheeledUp)")
          _ = try harness.clickText("Down")
          let far = try harness.clickText("Far")
          #expect(far.contains("«29»"), "list=\(list)\n\(far)")
        }
      }
    }
  }
}

/// Renders a numeric-anchor fixture, presses Jump and returns the frame.
@MainActor
private func numericScrollFrame(list: Bool, anchor: UnitPoint?, name: String) throws -> String {
  let harness = try StressRuntimeHarness(
    rootIdentity: testIdentity("CollectionBoundaryNumericAnchor", "\(list)", name),
    size: .init(width: 32, height: 12)
  ) { NumericScrollFixture(list: list, anchor: anchor) }
  defer { harness.shutdown() }
  return try harness.clickText("Jump")
}

@MainActor
private struct NumericScrollFixture: View {
  let list: Bool
  let anchor: UnitPoint?

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Jump") { _ = proxy.scrollTo(9, anchor: anchor) }
        Button("Down") { _ = proxy.scrollBy(y: 2) }
        Button("Far") { _ = proxy.scrollBy(y: Int.max) }
        if list {
          List(0..<30, id: \.self) { row in Text("«\(row)»") }
            .listStyle(BoundaryCurrencyListStyle()).scrollIndicators(.hidden).frame(height: 5)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<30, id: \.self) { row in Text("«\(row)»").id(row) }
            }
          }
          .scrollIndicators(.hidden).frame(height: 5)
        }
      }
    }
  }
}

@MainActor
private struct BoundaryCurrencySmallTable: View {
  let showsHeaders: Bool
  @State private var selection: Int? = 0
  var body: some View {
    Table(0..<10, id: \.self, selection: $selection, columns: [.init("Value", width: 20)]) { row in
      Text("«\(row)»")
    }.tableHeaders(showsHeaders ? .visible : .hidden).frame(height: showsHeaders ? 6 : 4)
  }
}

@MainActor
private struct BoundaryCurrencyRows: View {
  let table: Bool
  let height: Int
  @State private var selected: Int? = 0
  @State private var checked: Set<Int> = []
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if table {
        Table(0..<16, id: \.self, selection: $checked, columns: [.init("Value", width: 20)]) {
          row in
          BoundaryCurrencyRow(row: row)
        }.tableHeaders(.hidden).frame(height: height)
      } else {
        List(0..<16, id: \.self, selection: $selected) { row in BoundaryCurrencyRow(row: row) }
          .listStyle(BoundaryCurrencyListStyle()).frame(height: height)
      }
      Text("selected=\(selected ?? -1) checked=\(checked.sorted())")
    }
  }
}

@MainActor
private struct BoundaryCurrencyRow: View {
  let row: Int
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<(row % 3 + 1), id: \.self) { line in Text("«\(row)»:\(line)") }
    }
  }
}

private struct BoundaryCurrencyListStyle: ListStyle, Equatable {
  @MainActor
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(
      contentInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
      showsRowSeparators: false, showsSectionSeparators: false)
  }
}

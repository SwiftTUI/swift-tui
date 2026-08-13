import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Byte-exact pins of the list and table treatments the A1 List/Table style
/// split must preserve (control-style plan 2026-08-12-002).
///
/// These surfaces were captured before the split. They must not change when
/// `ListStyle` is rewritten and `Table` stops reading `listStyle`; the table
/// fixture that authored `.listStyle` on an ancestor migrates to the
/// equivalent `tableStyle` per the proposal's mapping while keeping the same
/// pinned output.
@MainActor
@Suite
struct CollectionStyleCharacterizationTests {
  /// Renders at a fixed proposal and normalizes trailing blank space, which
  /// is not part of the styling under pin and would make the literals
  /// fragile to whitespace-trimming tooling.
  private func normalizedSurface(
    _ view: some View,
    identity: String,
    width: Int = 30,
    height: Int = 14
  ) -> String {
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity(identity), applyEnvironmentValues: false),
      proposal: .init(width: .finite(width), height: .finite(height))
    )
    var lines = artifacts.rasterSurface.lines.map { line in
      var trimmed = Substring(line)
      while trimmed.last == " " {
        trimmed.removeLast()
      }
      return String(trimmed)
    }
    while lines.last?.isEmpty == true {
      lines.removeLast()
    }
    return lines.joined(separator: "\n")
  }

  private var listRows: some View {
    List {
      Text("Alpha")
      Text("Beta")
      Text("Gamma")
    }
  }

  private var table: some View {
    Table(0..<2, id: \.self, columns: [.init("Value", width: 8)]) { row in
      Text("Row \(row)")
    }
  }

  private static let roundedList = """
    ╭────────────────────────────╮
    │  Alpha                     │
    │  Beta                      │
    │  Gamma                     │
    ╰────────────────────────────╯
    """

  private static let separatorList = """
      Alpha
    ──────────────────────────────
      Beta
    ──────────────────────────────
      Gamma
    """

  private static let roundedTable = """
    ╭──────────╮
    │ Value    │
    ├──────────┤
    │ Row 0    │
    ├──────────┤
    │ Row 1    │
    ╰──────────╯
    """

  private static let squareTable = """
    ┌──────────┐
    │ Value    │
    ├──────────┤
    │ Row 0    │
    ├──────────┤
    │ Row 1    │
    └──────────┘
    """

  @Test("the automatic list renders the rounded grouped container")
  func automaticListRendersRoundedContainer() {
    #expect(normalizedSurface(listRows, identity: "CharListAutomatic") == Self.roundedList)
  }

  @Test("the plain list renders row separators without container chrome")
  func plainListRendersSeparators() {
    #expect(
      normalizedSurface(listRows.listStyle(.plain), identity: "CharListPlain")
        == Self.separatorList
    )
  }

  @Test("the inset-grouped list matches the automatic treatment")
  func insetGroupedListMatchesAutomatic() {
    #expect(
      normalizedSurface(listRows.listStyle(.insetGrouped), identity: "CharListInset")
        == Self.roundedList
    )
  }

  @Test("the automatic table renders the rounded inset treatment")
  func automaticTableRendersRoundedTreatment() {
    #expect(normalizedSurface(table, identity: "CharTableAutomatic") == Self.roundedTable)
  }

  @Test("the square-bordered table treatment renders plain glyphs")
  func borderedTableRendersSquareGlyphs() {
    #expect(
      normalizedSurface(table.tableStyle(.bordered), identity: "CharTablePlain")
        == Self.squareTable
    )
  }

  @Test("the inset table treatment matches the automatic treatment")
  func insetTableMatchesAutomatic() {
    #expect(
      normalizedSurface(table.tableStyle(.inset), identity: "CharTableInset")
        == Self.roundedTable
    )
  }

  @Test("an ancestor listStyle no longer styles a table")
  func ancestorListStyleDoesNotStyleTable() {
    // The A1 split's deliberate behavior change: `.listStyle` styles lists
    // only, so a table under an ancestor list style renders the automatic
    // table treatment. This is the silent-revert case the migration audit
    // exists for — the compiler cannot flag these sites.
    #expect(
      normalizedSurface(table.listStyle(.plain), identity: "CharTableRevert")
        == Self.roundedTable
    )
  }

  @Test("a nearer tableStyle overrides an ancestor and does not leak to siblings")
  func nearestTableStyleWinsAndStaysScoped() {
    let pair = VStack(spacing: 0) {
      table.tableStyle(.bordered)
      table
    }
    .tableStyle(.inset)
    let rendered = normalizedSurface(
      pair,
      identity: "CharTableScoping",
      width: 30,
      height: 20
    )
    #expect(rendered == Self.squareTable + "\n" + Self.roundedTable)
  }
}

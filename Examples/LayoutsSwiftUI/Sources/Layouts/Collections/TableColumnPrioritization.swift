import SwiftUI

/// A `Table` with four explicit-width columns inside a narrow
/// `.frame(width: 30)` parent. The point is that the table renders
/// all four columns even when the proposed width is tight: each
/// column's width participates in column layout regardless of how
/// the residual space is allocated.
///
/// SwiftUI port: the original used SwiftTUI's
/// `Table(columns:[...]) { TableRow { ... } }`. SwiftUI's `Table`
/// takes a sequence of `Identifiable` rows and `TableColumn` builders
/// that key into them, so this port reshapes the data to fit. The
/// observable layout intent (four width-4 columns honored within a
/// narrow parent) is preserved.
public struct TableColumnPrioritization: View {
  public init() {}

  private struct Row: Identifiable {
    let id: Int
    let a: String
    let b: String
    let c: String
    let d: String
  }

  private static let rows: [Row] = [
    Row(id: 1, a: "[A1]", b: "[B1]", c: "[C1]", d: "[D1]"),
    Row(id: 2, a: "[A2]", b: "[B2]", c: "[C2]", d: "[D2]"),
  ]

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Table column prioritization").foregroundStyle(.secondary)
      Table(Self.rows) {
        TableColumn("A") { Text($0.a) }.width(cell(4))
        TableColumn("B") { Text($0.b) }.width(cell(4))
        TableColumn("C") { Text($0.c) }.width(cell(4))
        TableColumn("D") { Text($0.d) }.width(cell(4))
      }
      .frame(width: cell(30))
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}

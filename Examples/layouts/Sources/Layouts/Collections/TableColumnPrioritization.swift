import SwiftTUIRuntime

/// A `Table` with four explicit-width columns inside a narrow
/// `.frame(width: 30)` parent. The point is that the table renders
/// all four columns even when the proposed width is tight: each
/// column's width participates in column layout regardless of how
/// the residual space is allocated.
///
/// Layout shape:
///
/// ```
/// VStack(alignment: .leading) {
///   Text("Table column prioritization")
///   Table(columns: [
///     .init("A", width: 4),
///     .init("B", width: 4),
///     .init("C", width: 4),
///     .init("D", width: 4),
///   ]) {
///     TableRow { Text("[A1]"); Text("[B1]"); Text("[C1]"); Text("[D1]") }
///     TableRow { Text("[A2]"); Text("[B2]"); Text("[C2]"); Text("[D2]") }
///   }
///   .frame(width: 30)
///   .border(.separator)
/// }
/// ```
///
/// Observable invariant pinned by the behaviour test:
///   - All four cell markers from the first data row (`[A1]`,
///     `[B1]`, `[C1]`, `[D1]`) appear somewhere in the rendered
///     raster. (Specific compression order is library-dependent —
///     this layout pins that the four columns survive narrow
///     proposal, not how residual space is distributed.)
///
/// The catalog marker `"Table column prioritization"` is the first
/// row.
public struct TableColumnPrioritization: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Table column prioritization").foregroundStyle(.muted)
      Table(columns: [
        .init("A", width: 4),
        .init("B", width: 4),
        .init("C", width: 4),
        .init("D", width: 4),
      ]) {
        TableRow {
          Text("[A1]")
          Text("[B1]")
          Text("[C1]")
          Text("[D1]")
        }
        TableRow {
          Text("[A2]")
          Text("[B2]")
          Text("[C2]")
          Text("[D2]")
        }
      }
      .frame(width: 30)
      .border(.separator)
    }
    .padding(1)
  }
}

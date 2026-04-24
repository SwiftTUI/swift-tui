import TerminalUI

/// Pins `Spacer(minLength:)` semantics: when two spacers compete for
/// residual space inside a single `HStack`, the spacer carrying the
/// `minLength` floor claims at least that many cells before the
/// remainder is split equally.
///
/// Layout shape:
///
/// ```
/// HStack {
///   Text("[L]")
///   Spacer()                  // no min — yields freely
///   Text("[M]")
///   Spacer(minLength: 20)     // claims ≥ 20 cells
///   Text("[R]")
/// }
/// ```
///
/// At a 40-cell-wide proposal the residual is `40 - 9 = 31` cells. A
/// plain `Spacer()` / `Spacer()` split would land each at ~15 cells;
/// the `minLength: 20` floor on the trailing spacer instead reserves
/// at least 20 cells for that gap, compressing the leading spacer to
/// the rest. The visible signature is `colR - colM ≥ 20` while
/// `colM - colL` is correspondingly small.
///
/// The header `"Spacer min length respected"` is the catalog marker.
public struct SpacerMinLengthRespected: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Spacer min length respected").foregroundStyle(.muted)
      HStack(spacing: 0) {
        Text("[L]")
        Spacer()
        Text("[M]")
        Spacer(minLength: 20)
        Text("[R]")
      }
    }
  }
}

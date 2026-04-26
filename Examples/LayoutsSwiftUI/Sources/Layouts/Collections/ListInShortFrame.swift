import SwiftUI

/// A 20-row `List` constrained inside a `.frame(height: 5)` viewport.
///
/// The point: a `List` honours the height proposal of its frame
/// modifier — content taller than the viewport scrolls (or is
/// otherwise clipped). With 20 rows of content but only 5 rows of
/// viewport height, only the first handful of rows fit; the tail
/// (e.g. `row 19`) is not painted.
///
/// Layout shape: a `VStack(alignment: .leading)` with the catalog
/// marker header on top of a `List` (`.plain` style, fixed
/// `.frame(height: 5)`, `.border(Color.gray)` for visual viewport
/// boundaries) containing 20 `Text("row \(i)")` children produced
/// by `ForEach(0..<20)`.
///
/// Observable invariants pinned by the behaviour test:
///   - `row 0` is visible inside the viewport.
///   - `row 19` is NOT visible (tail content does not fit in 5
///     rows so it is scrolled or clipped off).
///
/// The catalog marker `"List in short frame"` is the first row.
public struct ListInShortFrame: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("List in short frame").foregroundStyle(.secondary)
      List(selection: .constant(nil as String?)) {
        ForEach(0..<20, id: \.self) { i in
          Text("row \(i)").tag("\(i)")
        }
      }
      .listStyle(.plain)
      .frame(height: 5)
      .border(Color.gray)
    }
    .padding(1)
  }
}

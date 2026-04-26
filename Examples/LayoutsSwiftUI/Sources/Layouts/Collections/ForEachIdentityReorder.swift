import SwiftUI

/// Two `ForEach` blocks rendering the same three identity-tagged
/// items (`[apple]`, `[banana]`, `[cherry]`) in two different
/// orders. The second block reverses the order.
///
/// The visible component of identity correctness is that `ForEach`
/// traverses its data array in declared order regardless of the
/// `id:` value — so reordering the input array reorders the
/// rendered rows. (Full identity preservation under reorder is a
/// stateful concern that needs re-rendering the same view with
/// different state; this static layout pins the observable shape.)
///
/// Layout shape:
///
/// ```
/// VStack(alignment: .leading) {
///   Text("For each identity reorder")
///   Text("order A")
///   VStack { ForEach(["[apple]", "[banana]", "[cherry]"]) { Text($0) } }.border(Color.gray)
///   Text("order B (reversed)")
///   VStack { ForEach(["[cherry]", "[banana]", "[apple]"]) { Text($0) } }.border(Color.gray)
/// }
/// ```
///
/// Observable invariants pinned by the behaviour test:
///   - All three items appear in BOTH ordering blocks.
///   - In order A, `[apple]` paints on a row above `[banana]`,
///     which paints above `[cherry]`.
///   - In order B, the row order is reversed: `[cherry]` is above
///     `[banana]` is above `[apple]`.
///
/// The catalog marker `"For each identity reorder"` is the first row.
public struct ForEachIdentityReorder: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("For each identity reorder").foregroundStyle(.secondary)
      Text("order A").foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(["[apple]", "[banana]", "[cherry]"], id: \.self) { item in
          Text(item)
        }
      }
      .border(Color.gray)
      Text("order B (reversed)").foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(["[cherry]", "[banana]", "[apple]"], id: \.self) { item in
          Text(item)
        }
      }
      .border(Color.gray)
    }
    .padding(1)
  }
}

import TerminalUI

/// Two side-by-side panels that contrast `VStack(spacing:)` with
/// per-child `.padding()` INSIDE a border:
///
/// - Left (`spacing: 2`, each item `.border` only): each label is a
///   tight 3-row ring around a 1-cell-tall content line, and the
///   stack's `spacing: 2` inserts two empty rows BETWEEN adjacent
///   rings.
/// - Right (`spacing: 0`, each item `.padding(1).border`): the stack
///   inserts zero gap between items, but every label first gets a
///   1-cell padding ring, which the border then wraps — producing a
///   5-row ring per item (1 padding + 1 content + 1 padding, plus top
///   and bottom border rows). Adjacent rings sit flush against each
///   other because the gap lives INSIDE each border, not between.
///
/// The distinction the demo lands: spacing lives BETWEEN siblings;
/// padding wraps EACH child. The right panel's rings are visibly
/// taller/wider than the left panel's, and the right panel has no gap
/// rows separating them.
///
/// The header text `"VStack spacing vs padding"` is the catalog
/// marker, appearing exactly once above the two panels.
public struct VStackSpacingVsPadding: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("VStack spacing vs padding").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 4) {
        // Left: VStack(spacing: 2) — gap lives between borders.
        VStack(alignment: .leading, spacing: 2) {
          Text("spacing").foregroundStyle(.muted)
          Text("alpha").border(.separator)
          Text("beta").border(.separator)
          Text("gamma").border(.separator)
        }
        // Right: spacing 0 on the stack; each item has .padding(1)
        // INSIDE its border, widening the ring around the content.
        VStack(alignment: .leading, spacing: 0) {
          Text("padding").foregroundStyle(.muted)
          Text("alpha").padding(1).border(.separator)
          Text("beta").padding(1).border(.separator)
          Text("gamma").padding(1).border(.separator)
        }
      }
    }
    .padding(1)
  }
}

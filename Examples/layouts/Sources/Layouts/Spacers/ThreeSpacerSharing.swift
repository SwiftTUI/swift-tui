import TerminalUI

/// Three `Spacer()` siblings inside an `HStack` split the residual
/// horizontal space equally — the canonical "centered + edge-pinned"
/// pattern used in toolbar and segmented-control layouts.
///
/// Layout shape:
///
/// ```
/// HStack {
///   Spacer()
///   Text("[A]")
///   Spacer()
///   Text("[B]")
///   Spacer()
/// }
/// ```
///
/// At a generous proposed width, the three Spacers each consume one
/// third of `(width - widths_of_text_children)`. The result is two
/// markers placed symmetrically around the horizontal centre so that
/// `[A]` sits in the left-third / right-of-spacer-1 region and `[B]`
/// sits in the right-third / left-of-spacer-3 region.
///
/// The header `"Three spacer sharing"` is the catalog marker, kept on
/// its own row so that the three-spacer assertions below are isolated
/// from the header text.
public struct ThreeSpacerSharing: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Three spacer sharing").foregroundStyle(.muted)
      HStack(spacing: 0) {
        Spacer()
        Text("[A]")
        Spacer()
        Text("[B]")
        Spacer()
      }
    }
  }
}

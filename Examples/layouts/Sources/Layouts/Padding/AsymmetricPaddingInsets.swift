import TerminalUI

/// A bordered `Text` wraps a content string inside
/// `.padding(EdgeInsets(top: 0, leading: 4, bottom: 2, trailing: 0))`.
/// The asymmetric inset values verify that `EdgeInsets` is honoured
/// per-edge: the border ring sits flush with the text on the top and
/// trailing edges, and has visible empty cells only on the leading and
/// bottom edges.
///
/// The header `"Asymmetric padding insets"` is the catalog marker.
public struct AsymmetricPaddingInsets: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Asymmetric padding insets").foregroundStyle(.muted)
      Text("[content]")
        .padding(EdgeInsets(top: 0, leading: 4, bottom: 2, trailing: 0))
        .border(.separator)
    }
    .padding(1)
  }
}

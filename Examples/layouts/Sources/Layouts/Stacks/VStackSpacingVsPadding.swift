import TerminalUI

/// Two side-by-side panels that contrast `VStack(spacing:)` with
/// per-child `.padding()`:
///
/// - Left (`spacing: 2`, no padding): 2-row gaps BETWEEN items only;
///   no ring around individual items.
/// - Right (`spacing: 0`, each child `.padding(1)`): zero gap between
///   the padded children, but every item wears its own 1-cell ring.
///
/// The header text `"VStack spacing vs padding"` is the catalog
/// marker, appearing exactly once above the two panels.
public struct VStackSpacingVsPadding: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("VStack spacing vs padding").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 3) {
        spacingPanel
        paddingPanel
      }
    }
    .padding(1)
  }

  private var spacingPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("spacing: 2").foregroundStyle(.muted)
      VStack(spacing: 2) {
        Text("a").border(.separator)
        Text("b").border(.separator)
        Text("c").border(.separator)
      }
    }
  }

  private var paddingPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("padding: 1 each").foregroundStyle(.muted)
      VStack(spacing: 0) {
        Text("a").border(.separator).padding(1)
        Text("b").border(.separator).padding(1)
        Text("c").border(.separator).padding(1)
      }
    }
  }
}

import SwiftTUIRuntime

/// Classic "GeometryReader eats everything" gotcha.  An unconstrained
/// `GeometryReader` placed in an `HStack` alongside a sibling `Text`
/// claims as much horizontal space as the parent will give it,
/// starving its sibling.
///
/// The behaviour test pins what actually happens to `[SIBLING]` —
/// whether it appears at the right edge, gets pushed off-screen, or
/// is truncated.
///
/// The header `"Geometry reader in HStack hogs"` is the catalog marker.
public struct GeometryReaderInHStackHogs: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Geometry reader in HStack hogs").foregroundStyle(.muted)
      HStack(spacing: 1) {
        GeometryReader { _ in Text("[G]") }
        Text("[SIBLING]")
      }
      .frame(height: 5)
      .border(.separator)
    }
    .padding(1)
  }
}

import SwiftUI

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
      Text("Geometry reader in HStack hogs").foregroundStyle(.secondary)
      HStack(spacing: cell(1)) {
        GeometryReader { _ in Text("[G]") }
        Text("[SIBLING]")
      }
      .frame(height: cell(5))
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}

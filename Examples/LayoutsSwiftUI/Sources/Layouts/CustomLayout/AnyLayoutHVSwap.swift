import SwiftUI

/// Two side-by-side `AnyLayout` containers wrapping the same three
/// children (`[A]`, `[B]`, `[C]`).  The first container erases a
/// `VStackLayout`; the second erases an `HStackLayout`.  The catalog
/// header is rendered above; each container is wrapped in
/// `.border(Color.gray)` so its bounding box is unambiguous in the
/// raster.
///
/// Layout shape:
///
/// ```
/// VStack(alignment: .leading) {
///   Text("Any layout HV swap")
///   Text("VStackLayout")
///   AnyLayout(VStackLayout()) { Text("[A]"); Text("[B]"); Text("[C]") }
///     .border(Color.gray)
///   Text("HStackLayout")
///   AnyLayout(HStackLayout(spacing: 1)) { Text("[A]"); Text("[B]"); Text("[C]") }
///     .border(Color.gray)
/// }
/// ```
///
/// `AnyLayout` is the single demonstrated swap point: the underlying
/// erased layout selects the axis at runtime.  The behaviour test
/// pins that the `VStackLayout` container stacks `[A]/[B]/[C]` on
/// distinct rows while the `HStackLayout` container stacks them on
/// the same row.
///
/// The header `"Any layout HV swap"` is the catalog marker.
public struct AnyLayoutHVSwap: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Any layout HV swap").foregroundStyle(.secondary)

      Text("VStackLayout").foregroundStyle(.secondary)
      AnyLayout(VStackLayout()) {
        Text("[A]")
        Text("[B]")
        Text("[C]")
      }
      .border(Color.gray)

      Text("HStackLayout").foregroundStyle(.secondary)
      AnyLayout(HStackLayout(spacing: 1)) {
        Text("[A]")
        Text("[B]")
        Text("[C]")
      }
      .border(Color.gray)
    }
    .padding(1)
  }
}

import SwiftTUI

/// Smoke-tier layout proving that attaching `.sheet(isPresented:)` to a
/// `ScrollView`-backed view does not break the underlying resolve: the
/// catalog marker still rasterises even when a sheet modifier is wired
/// to a `@State` binding (initially `false`, so the sheet itself is not
/// presented in the smoke render).
///
/// Layout shape: a header marker `Text` over a `ScrollView` of 10 rows
/// constrained to `.frame(height: 8)` and bordered with `.separator`.
/// The whole stack is `.padding(1)`'d and carries a
/// `.sheet(isPresented:)` modifier bound to a `@State Bool`.
///
/// The smoke test (parameterised over `LayoutCatalog.all`) asserts only
/// that the marker `"Sheet over scroll layout"` appears in the raster
/// — the sheet is not toggled in the smoke pass, so what we are pinning
/// is "the modifier wires up cleanly and the underlying content still
/// resolves and paints."
public struct SheetOverScrollLayout: View {
  public init() {}

  @State private var isShowingSheet: Bool = false

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Sheet over scroll layout").foregroundStyle(.muted)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10, id: \.self) { i in
            Text("scroll row \(i)")
          }
        }
      }
      .frame(height: 8)
      .border(.separator)
    }
    .padding(1)
    .sheet(isPresented: $isShowingSheet) {
      Text("[SHEET]")
    }
  }
}

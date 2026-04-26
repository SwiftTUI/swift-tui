import SwiftUI

/// Two equivalent ways to spell a red background:
///
///   - LEFT  (ShapeStyle overload): `.background(Color.red)` resolves
///     through `extension View { func background<S: ShapeStyle>(_:) }`
///     which fills a `Rectangle` with the given style.
///   - RIGHT (content closure):     `.background { Rectangle().fill(Color.red) }`
///     uses the explicit content overload with the same body.
///
/// Both spellings produce the same visual result. This smoke layout
/// exists only to demonstrate that the two entry points coexist in
/// the API and compose the same render. No behaviour assertion is
/// needed beyond the marker being present on the viewport.
///
/// The header `"Background ShapeStyle vs Content overloads"` is the
/// catalog marker.
public struct BackgroundShapeStyleVsContentOverloads: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Background ShapeStyle vs Content overloads").foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 3) {
        VStack(alignment: .leading, spacing: 0) {
          Text(".background(.red):").foregroundStyle(.secondary)
          Text("hello")
            .frame(width: 10, height: 2)
            .background(Color.red)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text(".background { Rectangle } :").foregroundStyle(.secondary)
          Text("hello")
            .frame(width: 10, height: 2)
            .background {
              Rectangle().fill(Color.red)
            }
        }
      }
    }
    .padding(1)
  }
}

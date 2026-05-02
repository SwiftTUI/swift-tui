import SwiftTUI

/// Behaviour-tier layout demonstrating `.matchedGeometryEffect(id:in:)`
/// as a "single logical badge that lives in one of two containers".
///
/// Two `ZStack` containers sit side-by-side, each holding a 10×5 gray
/// `Rectangle`.  A `Text("[BADGE]")` is conditionally rendered into
/// either the left or the right container based on a `@State Bool`.
/// Both rendered branches carry `.matchedGeometryEffect(id:in:)` with
/// the SAME id and namespace, so SwiftUI (and the local matching
/// machinery) treats the two badge instances as a single logical view
/// that moves between the two slots.
///
/// In this static-render context we don't observe an animated
/// translation — `matchedGeometryEffect` is what makes the move a
/// "match" rather than a destroy/create.  The behaviour test pins the
/// observable consequence: the badge's column is LEFT when the boolean
/// chooses the left container, and RIGHT when it chooses the other
/// one.  See ``MatchedGeometryBadgeMoveBehaviourTests``.
public struct MatchedGeometryBadgeMove: View {
  public init() {}

  @State private var isLeft: Bool = true
  @Namespace private var ns

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Matched geometry badge move").foregroundStyle(.muted)
      HStack(spacing: 4) {
        ZStack {
          Rectangle().fill(Color.gray).frame(width: 10, height: 5)
          if isLeft {
            Text("[BADGE]").matchedGeometryEffect(id: "badge", in: ns)
          }
        }
        ZStack {
          Rectangle().fill(Color.gray).frame(width: 10, height: 5)
          if !isLeft {
            Text("[BADGE]").matchedGeometryEffect(id: "badge", in: ns)
          }
        }
      }
      .border(.separator)
    }
    .padding(1)
  }
}

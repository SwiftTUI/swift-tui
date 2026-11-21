public import SwiftTUIViews

// Demonstration 6 of 6: a transition made with
// `AnyTransition.modifier(active:identity:)` (STUI-1546).
//
// What it shows: the view rises into place from a few rows below, inside
// its own frame, while it fades in. It sinks and fades as it leaves.
//
// What it proves: stage 4b through its short form. `Rise` is one view
// modifier that conforms to `Animatable`; the transition is two values of
// it, `progress` 0 and `progress` 1, and `body(content:)` runs for every
// frame with the value between. Stage 3 draws the offset, the opacity and
// the clip round the view as it was last drawn.
//
// Known limits:
// - The offset is a whole number of rows, so the view moves in steps.
// - The modifier cannot learn the height of the view. The caller passes the
//   number of rows to travel.
// - An opacity on a terminal mixes the colours of each cell with what is
//   behind it. The glyphs keep their whole shape at every opacity.

/// The modifier of `AnyTransition.rise(rows:)`: everything it draws is a
/// function of `progress`, from 0 (transparent, `rows` rows down) to 1 (the
/// view in place).
public struct Rise: ViewModifier, Animatable {
  public var progress: Double
  public var rows: Int

  public init(progress: Double, rows: Int = 2) {
    self.progress = progress
    self.rows = rows
  }

  public nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  /// `progress` as the opacity. A spring takes `progress` outside 0...1; an
  /// opacity stays in range.
  public nonisolated var opacity: Double {
    min(1, max(0, progress))
  }

  /// How many rows below its place the view is drawn. A spring takes
  /// `progress` above 1; the view does not rise past its place.
  public nonisolated var shift: Int {
    Int(((1 - opacity) * Double(max(0, rows))).rounded())
  }

  public func body(content: Content) -> some View {
    content
      .offset(y: shift)
      .opacity(opacity)
      .clipped()
  }
}

extension AnyTransition {
  /// The view rises `rows` rows into place and fades in.
  @MainActor
  public static func rise(rows: Int = 2) -> AnyTransition {
    .modifier(active: Rise(progress: 0, rows: rows), identity: Rise(progress: 1, rows: rows))
  }
}

import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Layout-only assertions for the rewritten `.border(...)` view modifier.
///
/// M2.B flips `.border` from the legacy `.overlay(Rectangle().strokeBorder)`
/// inset-and-occlude behavior to a layout-aware outset: the border frame
/// grows by the border set's per-side display widths, and the child's
/// content is never occluded.  These tests pin the frame-growth invariant.
@MainActor
struct BorderModifierLayoutTests {
  @Test("public .border grows its frame by the border set's layout insets")
  func borderGrowsLayout() {
    // "hi" is 2x1.  .single contributes 1 display cell on each side.
    // Total frame is 4x3 after the outset rewrite.
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single),
      context: .init(identity: testIdentity("BorderGrows"))
    )

    #expect(artifacts.rasterSurface.size.width == 4)
    #expect(artifacts.rasterSurface.size.height == 3)
  }

  @Test("public .border(sides: [.top]) only grows in the top direction")
  func borderTopOnly() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single, sides: [.top]),
      context: .init(identity: testIdentity("BorderTopOnly"))
    )

    // "hi" is 2x1.  Only the top edge contributes — left/right/bottom
    // widths are masked out.  Width stays 2, height becomes 2.
    #expect(artifacts.rasterSurface.size.width == 2)
    #expect(artifacts.rasterSurface.size.height == 2)
  }

  @Test("public .border with .innerHalfBlock and explicit inset placement does not grow the frame")
  func borderInsetDoesNotGrow() {
    let artifacts = DefaultRenderer().render(
      Text("hello").border(set: .innerHalfBlock, placement: .inset),
      context: .init(identity: testIdentity("BorderInset"))
    )

    // "hello" is 5x1.  Explicit `.inset` placement means the border
    // glyphs overdraw the outermost child cells rather than reserving
    // new ones.  Frame stays 5x1.
    #expect(artifacts.rasterSurface.size.width == 5)
    #expect(artifacts.rasterSurface.size.height == 1)
  }

  @Test("public .border default uses .rounded")
  func borderDefaultIsRounded() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(),
      context: .init(identity: testIdentity("BorderDefault"))
    )

    // `.rounded` uses 1-cell widths on every side, so the default grows
    // the frame by 1 on each edge: "hi" is 2x1, output is 4x3.
    #expect(artifacts.rasterSurface.size.width == 4)
    #expect(artifacts.rasterSurface.size.height == 3)
  }

  @Test("public .border(set:) with only horizontal sides grows only in the vertical axis")
  func borderHorizontalOnly() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single, sides: [.top, .bottom]),
      context: .init(identity: testIdentity("BorderHorizontalOnly"))
    )

    #expect(artifacts.rasterSurface.size.width == 2)
    #expect(artifacts.rasterSurface.size.height == 3)
  }
}

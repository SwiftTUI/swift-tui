import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// The expected bodies retain the pre-style primitive compositions, including
// row opacity and highlight placement, so a matching consumer implementation
// cannot conceal a shared default-rendering regression.
@MainActor
struct LegacyValueControlCompositionTests {
  @Test(
    "automatic value-control styles preserve prior complete raster output",
    arguments: [false, true], [false, true])
  func automaticEquivalence(_ enabled: Bool, _ focused: Bool) {
    var environment = EnvironmentValues()
    environment.isEnabled = enabled
    let identity = testIdentity("Root")
    if focused { environment.focusedIdentity = identity }
    let snapshot = environment.styleEnvironmentSnapshot
    let row = snapshot.rowChrome(isEnabled: enabled, isFocused: focused)
    let control = snapshot.controlChrome(isEnabled: enabled, isFocused: focused)
    let slider = Slider("Level", value: .constant(5), in: 0...10)
    let stepper = Stepper("Count", value: .constant(0), in: 0...10)
    let oldSlider = controlFocusRow(
      showsRail: focused, railStyle: row.borderStyle, isHighlighted: focused,
      backgroundStyle: row.backgroundStyle, reservesRailSpaceWhenHidden: true
    ) {
      Text("Level").foregroundStyle(.terminalBorder(.accent))
      highlightedControlRow(
        HStack(alignment: .center, spacing: 1) {
          Text("━━━━●───").foregroundStyle(
            focused ? control.borderStyle : AnyShapeStyle(.separator))
          Text("5").foregroundStyle(focused ? control.foregroundStyle : row.foregroundStyle)
        }.drawMetadata(.init(opacity: control.opacity)),
        isHighlighted: focused, backgroundStyle: control.backgroundStyle)
    }.drawMetadata(.init(opacity: row.opacity))
    let oldStepper = controlFocusRow(
      showsRail: focused, railStyle: row.borderStyle, isHighlighted: focused,
      backgroundStyle: row.backgroundStyle, reservesRailSpaceWhenHidden: true
    ) {
      Text("Count").foregroundStyle(.terminalBorder(.accent))
      highlightedControlRow(
        HStack(alignment: .center, spacing: 1) {
          Text("◁").foregroundStyle(.placeholder)
          Text("0").foregroundStyle(focused ? control.foregroundStyle : row.foregroundStyle)
          Text("▶").foregroundStyle(focused ? control.borderStyle : AnyShapeStyle(.separator))
        }.drawMetadata(.init(opacity: control.opacity)),
        isHighlighted: focused, backgroundStyle: control.backgroundStyle)
    }.drawMetadata(.init(opacity: row.opacity))
    let context = ResolveContext(
      identity: identity, environmentValues: environment, applyEnvironmentValues: true)
    same(slider, oldSlider, context: context)
    same(stepper, oldStepper, context: context)
  }

  private func same<A: View, B: View>(_ a: A, _ b: B, context: ResolveContext) {
    let proposal = ProposedSize(width: 40, height: 8)
    let actual = DefaultRenderer().render(a, context: context, proposal: proposal).rasterSurface
    let expected = DefaultRenderer().render(b, context: context, proposal: proposal).rasterSurface
    let matches = actual == expected
    #expect(matches, "actual: \(actual.lines) expected: \(expected.lines)")
  }
}

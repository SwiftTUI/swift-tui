public import SwiftTUICore

package import SwiftTUIRuntime

/// Renders a committed frame's semantic snapshot to the linear
/// accessibility reading-order string (the accessible runtime's output
/// format, including missing-label warnings).
///
/// Lets external packages assert on assistive output for their views —
/// the chart library pins its default-summary and missing-label
/// diagnostics contract through this seam — without the runtime's
/// internal renderer becoming public API.
@_spi(Testing) public func renderLinearAccessibilityOutput(
  _ snapshot: SemanticSnapshot
) -> String {
  LinearAccessibilityRenderer().render(snapshot)
}

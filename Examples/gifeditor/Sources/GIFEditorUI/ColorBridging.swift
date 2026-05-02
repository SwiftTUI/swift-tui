import GIFEditorCore
import SwiftTUI

/// Bridges between `GIFEditorCore`'s platform-neutral `EditorColor` and
/// the SwiftTUI `Color` type. Kept in one place so the view code
/// doesn't sprinkle hex conversions everywhere.
extension EditorColor {
  func toTerminalColor() -> Color {
    Color(
      red: Double(red) / 255.0,
      green: Double(green) / 255.0,
      blue: Double(blue) / 255.0,
      alpha: Double(alpha) / 255.0
    )
  }
}

extension Color {
  /// Converts to the editor's 8-bit-per-channel sRGB representation.
  /// Out-of-gamut components are clamped.
  func toEditorColor() -> EditorColor {
    let r = max(0.0, min(1.0, red))
    let g = max(0.0, min(1.0, green))
    let b = max(0.0, min(1.0, blue))
    let a = max(0.0, min(1.0, alpha))
    return EditorColor(
      red: UInt8((r * 255.0).rounded()),
      green: UInt8((g * 255.0).rounded()),
      blue: UInt8((b * 255.0).rounded()),
      alpha: UInt8((a * 255.0).rounded())
    )
  }
}

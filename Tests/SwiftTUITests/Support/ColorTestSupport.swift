@testable import SwiftTUICore

func hexColor(_ hexValue: String) -> Color {
  try! Color(hex: hexValue)
}

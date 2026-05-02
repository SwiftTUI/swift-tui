@testable import Core

func hexColor(_ hexValue: String) -> Color {
  try! Color(hex: hexValue)
}

import SwiftUI

/// Native SwiftUI layout measurements use 10 points per SwiftTUI cell.
func cell(_ units: CGFloat) -> CGFloat {
  units * 10
}

func cell(_ units: Int) -> CGFloat {
  CGFloat(units * 10)
}

func cellCount(_ points: CGFloat) -> Int {
  Int((points / 10).rounded())
}

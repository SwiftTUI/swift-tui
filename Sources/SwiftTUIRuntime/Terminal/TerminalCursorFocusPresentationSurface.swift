import SwiftTUICore

package protocol TerminalCursorFocusPresentationSurface: PresentationSurface {
  func presentAccessibilityCursorFocus(at point: CellPoint?) throws
}

extension TerminalCursorFocusPresentationSurface {
  package func presentAccessibilityCursorFocus(at point: CellPoint?) throws {
    if let point {
      try moveCursor(to: point)
      try write("\u{001B}[?25h")
    } else {
      try write("\u{001B}[?25l")
    }
  }
}

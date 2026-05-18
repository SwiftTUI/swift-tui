import SwiftTUICore

enum TerminalHostEscapeSequences {
  static let clearScreen = "\u{001B}[2J"
  static let eraseToEndOfLine = "\u{001B}[K"
  static let deleteVisibleKittyPlacements = "\u{001B}_Ga=d,q=2\u{001B}\\"
  static let beginSynchronizedOutput = "\u{001B}[?2026h"
  static let endSynchronizedOutput = "\u{001B}[?2026l"
  static let enterAlternateScreen = "\u{001B}[?1049h"
  static let exitAlternateScreen = "\u{001B}[?1049l"
  static let hideCursor = "\u{001B}[?25l"
  static let showCursor = "\u{001B}[?25h"
  static let enableBracketedPaste = "\u{001B}[?2004h"
  static let disableBracketedPaste = "\u{001B}[?2004l"
  static let disableAllMouseMotion = "\u{001B}[?1003l"
  static let resetStyle = "\u{001B}[0m"

  static func cursor(
    to point: CellPoint
  ) -> String {
    let row = max(1, point.y + 1)
    let column = max(1, point.x + 1)
    return "\u{001B}[\(row);\(column)H"
  }

  static func cursorFocus(
    to point: CellPoint?
  ) -> String {
    guard let point else {
      return hideCursor
    }
    return cursor(to: point) + showCursor
  }

  static func enableMouseReporting(
    mouseCoordinateMode: MouseCoordinateMode,
    hoverEnabled: Bool
  ) -> String {
    var sequence = "\u{001B}[?1006h"
    if mouseCoordinateMode.usesTerminalPixels {
      sequence += "\u{001B}[?1016h"
    }
    sequence += "\u{001B}[?1002h"
    if hoverEnabled {
      sequence += "\u{001B}[?1003h"
    }
    return sequence
  }

  static func disableMouseReporting(
    mouseCoordinateMode: MouseCoordinateMode,
    hoverEnabled: Bool
  ) -> String {
    var sequence = hoverEnabled ? disableAllMouseMotion : ""
    sequence += "\u{001B}[?1002l"
    if mouseCoordinateMode.usesTerminalPixels {
      sequence += "\u{001B}[?1016l\u{001B}[?1006l"
    } else {
      sequence += "\u{001B}[?1006l"
    }
    return sequence
  }

  static func processExitReset(
    mouseCoordinateMode: MouseCoordinateMode,
    hoverEnabled: Bool
  ) -> String {
    var reset = ""
    if mouseCoordinateMode.reportsMouseInput {
      reset += disableMouseReporting(
        mouseCoordinateMode: mouseCoordinateMode,
        hoverEnabled: hoverEnabled
      )
    }
    reset += disableBracketedPaste
    reset += showCursor
    reset += resetStyle
    reset += exitAlternateScreen
    return reset
  }

  static func wrappedSynchronizedOutput(
    _ output: String,
    strategy: TerminalPresentationPlan.Strategy,
    capabilityProfile: TerminalCapabilityProfile
  ) -> String {
    guard
      usesSynchronizedOutput(
        for: output,
        strategy: strategy,
        capabilityProfile: capabilityProfile
      )
    else {
      return output
    }

    return beginSynchronizedOutput
      + output
      + endSynchronizedOutput
  }

  static func usesSynchronizedOutput(
    for output: String,
    strategy: TerminalPresentationPlan.Strategy,
    capabilityProfile: TerminalCapabilityProfile
  ) -> Bool {
    !output.isEmpty
      && strategy == .fullRepaint
      && capabilityProfile.supportsSynchronizedOutput
  }
}

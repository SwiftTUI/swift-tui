import SwiftTUICore

enum TerminalHostEscapeSequences {
  static let clearScreen = "\u{001B}[2J"
  static let eraseToEndOfLine = "\u{001B}[K"
  static let deleteVisibleKittyPlacements = "\u{001B}_Ga=d,q=2\u{001B}\\"

  /// Frees a specific kitty image's stored data (and any placements) from the
  /// terminal's image store. `d=I` (uppercase) deletes by image id *and*
  /// releases the pixel buffer, unlike `deleteVisibleKittyPlacements` (`d=a`)
  /// which only removes on-screen placements and leaves the data resident. Used
  /// to reclaim superseded blend variants that would otherwise accumulate one
  /// image per frame under animation.
  static func freeKittyImageData(
    id: UInt32
  ) -> String {
    "\u{001B}_Ga=d,d=I,i=\(id),q=2\u{001B}\\"
  }
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
  // Kitty keyboard protocol: push flag 1 (disambiguate escape codes) onto
  // the enhancement stack / pop one entry back off. The stack is
  // per-screen, so pushing after entering the alternate screen and popping
  // before leaving it means even an unclean exit cannot leave the user's
  // shell (main screen) in enhanced mode on a compliant terminal.
  static let pushKittyKeyboardEnhancements = "\u{001B}[>1u"
  static let popKittyKeyboardEnhancements = "\u{001B}[<u"

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
    hoverEnabled: Bool,
    kittyKeyboardPushed: Bool
  ) -> String {
    var reset = ""
    if mouseCoordinateMode.reportsMouseInput {
      reset += disableMouseReporting(
        mouseCoordinateMode: mouseCoordinateMode,
        hoverEnabled: hoverEnabled
      )
    }
    if kittyKeyboardPushed {
      // Must precede exitAlternateScreen: the enhancement stack is
      // per-screen, so the pop only reaches our pushed entry while the
      // alternate screen is still active.
      reset += popKittyKeyboardEnhancements
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

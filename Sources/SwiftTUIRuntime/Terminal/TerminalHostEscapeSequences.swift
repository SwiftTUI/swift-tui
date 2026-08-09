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

  /// DECSTBM — set the vertical scroll region to rows `top...bottom`,
  /// 1-based inclusive. Side effect on a conforming terminal: the cursor
  /// homes, which is why the emission re-homes explicitly after the region
  /// ops instead of trusting terminal variance.
  static func setScrollRegion(
    top: Int,
    bottom: Int
  ) -> String {
    "\u{001B}[\(max(1, top));\(max(1, bottom))r"
  }

  /// DECSTBM reset — the scroll region becomes the full screen.
  static let resetScrollRegion = "\u{001B}[r"

  /// SU — scroll the active region UP by `rows`: content moves toward the
  /// top, blank rows appear at the region bottom. With a DECSTBM region set,
  /// only rows inside the region move.
  static func scrollUp(
    _ rows: Int
  ) -> String {
    "\u{001B}[\(max(1, rows))S"
  }

  /// SD — scroll the active region DOWN by `rows`: content moves toward the
  /// bottom, blank rows appear at the region top.
  static func scrollDown(
    _ rows: Int
  ) -> String {
    "\u{001B}[\(max(1, rows))T"
  }

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

  /// Minimum incremental row-batch count that gets a synchronized-output wrap.
  ///
  /// A single row batch is one cursor move plus one rendered run — the
  /// terminal applies it atomically enough that a refresh cannot show a torn
  /// intermediate. From two row batches up (the shape of a scroll repaint),
  /// the terminal can paint between the per-row cursor moves and a refresh
  /// can catch the band half-moved — exactly the tearing CSI ?2026 exists to
  /// hide. The wrap also gives frame-delimiting consumers (the org PTY rig's
  /// `--mode sync`) a begin/end marker per multi-row frame.
  static let incrementalSynchronizedOutputRowBatchThreshold = 2

  static func wrappedSynchronizedOutput(
    _ output: String,
    plan: TerminalPresentationPlan,
    capabilityProfile: TerminalCapabilityProfile
  ) -> String {
    guard
      usesSynchronizedOutput(
        for: output,
        plan: plan,
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
    plan: TerminalPresentationPlan,
    capabilityProfile: TerminalCapabilityProfile
  ) -> Bool {
    guard !output.isEmpty, capabilityProfile.supportsSynchronizedOutput else {
      return false
    }
    switch plan.strategy {
    case .fullRepaint:
      return true
    case .incremental:
      // A scroll-region frame always wraps: the region ops move a whole band
      // of rows and any refresh between the SU/SD and the exposed-row
      // repaints would show the band torn — the exact artifact CSI ?2026
      // exists to hide.
      return plan.scrollRegion != nil
        || plan.rowBatches.count >= incrementalSynchronizedOutputRowBatchThreshold
    }
  }
}

/// Draw-time glyph selection for a rolling `Text` run.
///
/// The controller applies a ``TextRollValue`` to the node's draw metadata
/// each tick; draw extraction turns it into a rich-text command whose runs
/// are the roll's columns grouped by opacity, styled with the node's own
/// text style. The run's characters lay out exactly like the new string
/// (every column is the new string's character or a same-width substitute),
/// so the roll never re-wraps and damages only its own cells.
package enum TextRollRendering {
  package static func payload(
    for roll: TextRollValue,
    style: TextStyle
  ) -> RichTextPayload {
    var runs: [RichTextRun] = []
    var pendingText = ""
    var pendingOpacity: Double?
    func flush() {
      guard let opacity = pendingOpacity, !pendingText.isEmpty else { return }
      var runStyle = style
      runStyle.opacity = style.opacity * opacity
      runs.append(RichTextRun(text: pendingText, style: runStyle))
      pendingText = ""
    }
    for column in roll.renderedColumns() {
      let opacity = min(max(column.opacity, 0), 1)
      if pendingOpacity != opacity {
        flush()
        pendingOpacity = opacity
      }
      pendingText.append(column.character)
    }
    flush()
    return RichTextPayload(runs: runs)
  }
}

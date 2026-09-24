/// Converts primitive selection and placed text geometry into native UTF-16 ranges.
package func accessibilityTextInput(
  _ source: TextInputAccessibilityText, bounds: CellRect, wraps: Bool
) -> AccessibilityTextInput {
  let characters = Array(source.text)
  let display = Array(source.displayText ?? source.text)
  let headIndex = min(max(0, source.head), characters.count)
  // A synthetic caret at a newline or end occupies a rendered cell, but
  // never becomes part of the native text or its UTF-16 offsets.
  let hasSyntheticCaret =
    display.count == characters.count + 1
    && display[headIndex] == "_"
    && Array(display.prefix(headIndex)) + Array(display.dropFirst(headIndex + 1)) == characters
  let anchors = wrappedTextCursorAnchors(
    hasSyntheticCaret ? String(display) : source.text,
    width: wraps ? bounds.size.width : Int.max)
  var offsets = [0]
  var clusters: [AccessibilityTextInput.Cluster] = []
  for (index, character) in characters.enumerated() {
    let displayIndex = index + (hasSyntheticCaret && index > headIndex ? 1 : 0)
    let start = offsets.last!
    let end = start + String(character).utf16.count
    offsets.append(end)
    clusters.append(
      .init(
        range: start..<end,
        rect: CellRect(
          origin: CellPoint(
            x: bounds.origin.x + anchors[displayIndex].x,
            y: bounds.origin.y + anchors[displayIndex].y),
          size: CellSize(width: max(1, cellWidth(of: character)), height: 1))))
  }
  let anchor = offsets[min(max(0, source.anchor), characters.count)]
  let head = offsets[min(max(0, source.head), characters.count)]
  let end = anchors[characters.count + (hasSyntheticCaret && headIndex < characters.count ? 1 : 0)]
  return AccessibilityTextInput(
    selection: min(anchor, head)..<max(anchor, head), insertionOffset: head,
    clusters: clusters,
    endAnchor: CellPoint(x: bounds.origin.x + end.x, y: bounds.origin.y + end.y))
}

/// Maps a grapheme offset through the same wrapping operation as rendered Text.
/// Synthesized wrap markers consume cells but never acquire a source offset.
package func wrappedTextCursorAnchor(_ text: String, offset: Int, width: Int) -> CellPoint {
  let target = min(max(0, offset), text.count)
  var logicalLines: [[SourceIndexedCluster]] = [[]]
  var lineStarts = [0]
  for (index, character) in text.enumerated() {
    if character.unicodeScalars.allSatisfy({ $0.value == 10 || $0.value == 13 }) {
      logicalLines.append([])
      lineStarts.append(index + 1)
    } else {
      logicalLines[logicalLines.count - 1].append(
        SourceIndexedCluster(
          sourceIndex: index,
          cluster: TextCluster(character: character, cellWidth: cellWidth(of: character))))
    }
  }
  var y = 0
  var previous = CellPoint(x: 0, y: 0)
  for (lineIndex, line) in logicalLines.enumerated() {
    if line.isEmpty, target == lineStarts[lineIndex] { return CellPoint(x: 0, y: y) }
    let rows = wrapTextLineClusters(
      line, width: max(1, width), wrappingStrategy: .wordBoundary)
    for row in rows {
      var x = 0
      for cluster in row {
        if let index = cluster.sourceIndex {
          if index == target { return CellPoint(x: x, y: y) }
          if index > target { return previous }
          previous = CellPoint(x: x + cluster.cellWidth, y: y)
        }
        x += cluster.cellWidth
      }
      y += 1
    }
  }
  if target == text.count, text.last?.isNewline == true {
    return CellPoint(x: 0, y: max(0, y - 1))
  }
  return previous
}

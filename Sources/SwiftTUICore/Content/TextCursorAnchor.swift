/// Maps a grapheme offset through the same wrapping operation as rendered Text.
/// Synthesized wrap markers consume cells but never acquire a source offset.
package func wrappedTextCursorAnchor(_ text: String, offset: Int, width: Int) -> CellPoint {
  let anchors = wrappedTextCursorAnchors(text, width: width)
  return anchors[min(max(0, offset), anchors.count - 1)]
}

package func wrappedTextCursorAnchors(_ text: String, width: Int) -> [CellPoint] {
  var anchors = Array(repeating: CellPoint(x: 0, y: 0), count: text.count + 1)
  var nextOffset = 0
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
    if line.isEmpty {
      while nextOffset < lineStarts[lineIndex] {
        anchors[nextOffset] = previous
        nextOffset += 1
      }
      anchors[lineStarts[lineIndex]] = CellPoint(x: 0, y: y)
      nextOffset = lineStarts[lineIndex] + 1
    }
    let rows = wrapTextLineClusters(
      line, width: max(1, width), wrappingStrategy: .wordBoundary)
    for row in rows {
      var x = 0
      for cluster in row {
        if let index = cluster.sourceIndex {
          while nextOffset < index {
            anchors[nextOffset] = previous
            nextOffset += 1
          }
          anchors[index] = CellPoint(x: x, y: y)
          nextOffset = index + 1
          previous = CellPoint(x: x + cluster.cellWidth, y: y)
        }
        x += cluster.cellWidth
      }
      y += 1
    }
  }
  while nextOffset < anchors.count {
    anchors[nextOffset] = previous
    nextOffset += 1
  }
  if text.last?.isNewline == true {
    anchors[text.count] = CellPoint(x: 0, y: max(0, y - 1))
  }
  return anchors
}

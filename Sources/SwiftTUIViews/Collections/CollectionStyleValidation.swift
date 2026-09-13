import SwiftTUICore

extension ListStylePresentation {
  package var validationProblems: [String] {
    var problems = collectionInsetProblems(contentInsets)
    if let container {
      let maximum = AnchoredSurfaceStylePresentation.representableCellCount
      if !(0...maximum).contains(container.insetAmount) {
        problems.append("container.insetAmount must be a nonnegative, representable cell count")
      }
      if !(1...maximum).contains(container.strokeStyle.lineWidth) {
        problems.append("container.strokeStyle.lineWidth must be positive and representable")
      }
      if case .interior(let width) = container.fillMode, !(0...maximum).contains(width) {
        problems.append("container.fillMode strokeWidth must be nonnegative and representable")
      }
      if case .roundedRectangle(let radius) = container.geometry,
        !(0...maximum).contains(radius)
      {
        problems.append("container cornerRadius must be nonnegative and representable")
      }
    }
    return problems
  }
}

extension TableStylePresentation {
  package var validationProblems: [String] {
    var problems = collectionInsetProblems(contentInsets)
    let glyphs = borderGlyphs
    let fields: [(String, String)] = [
      ("topLeft", glyphs.topLeft), ("top", glyphs.top), ("topJoin", glyphs.topJoin),
      ("topRight", glyphs.topRight), ("left", glyphs.left), ("columnJoin", glyphs.columnJoin),
      ("right", glyphs.right), ("middleLeft", glyphs.middleLeft), ("middle", glyphs.middle),
      ("middleJoin", glyphs.middleJoin), ("middleRight", glyphs.middleRight),
      ("bottomLeft", glyphs.bottomLeft), ("bottom", glyphs.bottom),
      ("bottomJoin", glyphs.bottomJoin), ("bottomRight", glyphs.bottomRight),
    ]
    for (name, glyph) in fields {
      if glyph.count != 1 || glyph.first.map({ cellWidth(of: $0) }) != 1
        || !collectionSingleLineText(glyph)
      {
        problems.append("borderGlyphs.\(name) must be one printable terminal cell")
      }
    }
    return problems
  }
}

extension OutlineStylePresentation {
  package var validationProblems: [String] {
    let fields = [
      ("continuingIndenter", continuingIndenter), ("emptyIndenter", emptyIndenter),
      ("branchConnector", branchConnector), ("leafConnector", leafConnector),
    ]
    return fields.compactMap { name, text in
      collectionSingleLineText(text) ? nil : "\(name) must contain only printable single-line text"
    }
  }
}

private func collectionInsetProblems(_ insets: EdgeInsets) -> [String] {
  let maximum = AnchoredSurfaceStylePresentation.representableCellCount
  let values = [insets.top, insets.leading, insets.bottom, insets.trailing]
  return values.allSatisfy { (0...maximum).contains($0) }
    ? [] : ["contentInsets must be nonnegative, representable cell counts"]
}

private func collectionSingleLineText(_ text: String) -> Bool {
  text.allSatisfy { (1...2).contains(cellWidth(of: $0)) }
    && text.unicodeScalars.allSatisfy {
      let category = $0.properties.generalCategory
      return category != .control && category != .lineSeparator && category != .paragraphSeparator
    }
}

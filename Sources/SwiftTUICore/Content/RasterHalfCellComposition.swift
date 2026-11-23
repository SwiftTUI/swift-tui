/// Composes vertical block glyphs by their pixel coverage. A missing channel
/// is transparent, so the opposite half may come from the underlay's foreground
/// rather than its background. Shared by Canvas/text raster and image fallback.
package func compositeVerticalBlockCell(
  _ source: RasterCell, over underlay: RasterCell, blendMode: BlendMode? = nil
) -> RasterCell? {
  guard source.spanWidth == 1, source.character == "▀" || source.character == "▄" else {
    return nil
  }
  typealias Half = (color: Color?, index: UInt8?)
  func halves(_ cell: RasterCell) -> (Half, Half) {
    let foreground: Half = (cell.style?.foregroundColor, cell.style?.foregroundPaletteIndex)
    let background: Half = (cell.style?.backgroundColor, cell.style?.backgroundPaletteIndex)
    switch cell.character {
    case "▀": return (foreground, background)
    case "▄": return (background, foreground)
    case "█": return (foreground, foreground)
    default: return (background, background)
    }
  }
  func composed(_ source: Half, over under: Half) -> Half {
    var top = ResolvedTextStyle(backgroundColor: source.color)
    top.backgroundPaletteIndex = source.index
    var lower = ResolvedTextStyle(backgroundColor: under.color)
    lower.backgroundPaletteIndex = under.index
    let blended = top.composited(over: lower, blendMode: blendMode)
    return (blended.backgroundColor, blended.backgroundPaletteIndex)
  }
  let (sourceTop, sourceBottom) = halves(source)
  let (underTop, underBottom) = halves(underlay)
  let top = composed(sourceTop, over: underTop)
  let bottom = composed(sourceBottom, over: underBottom)
  var style = source.style ?? .init()
  let character: Character
  if source.character == "▄", bottom.color != nil {
    // Preserve the authored glyph orientation. Both channel assignments encode
    // the same coverage, but controls and copied text still carry this glyph.
    character = "▄"
    style.foregroundColor = bottom.color
    style.foregroundPaletteIndex = bottom.index
    style.backgroundColor = top.color
    style.backgroundPaletteIndex = top.index
  } else if top.color != nil {
    character = "▀"
    style.foregroundColor = top.color
    style.foregroundPaletteIndex = top.index
    style.backgroundColor = bottom.color
    style.backgroundPaletteIndex = bottom.index
  } else if bottom.color != nil {
    character = "▄"
    style.foregroundColor = bottom.color
    style.foregroundPaletteIndex = bottom.index
    style.backgroundColor = nil
  } else {
    return underlay
  }
  return RasterCell(character: character, style: style, hyperlink: source.hyperlink)
}

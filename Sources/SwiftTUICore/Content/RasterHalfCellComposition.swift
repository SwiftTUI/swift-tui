/// Composes vertical block glyphs by their pixel coverage. A missing channel
/// is transparent, so the opposite half may come from the underlay's foreground
/// rather than its background. Shared by Canvas/text raster and image fallback.
package func compositeVerticalBlockCell(
  _ source: RasterCell, over underlay: RasterCell, blendMode: BlendMode? = nil
) -> RasterCell? {
  guard source.spanWidth == 1, source.character == "▀" || source.character == "▄" else {
    return nil
  }
  func halves(_ cell: RasterCell) -> (Color?, Color?) {
    let foreground = cell.style?.foregroundColor
    let background = cell.style?.backgroundColor
    switch cell.character {
    case "▀": return (foreground, background)
    case "▄": return (background, foreground)
    case "█": return (foreground, foreground)
    default: return (background, background)
    }
  }
  func composed(_ color: Color?, over backdrop: Color?) -> Color? {
    ResolvedTextStyle(backgroundColor: color).composited(
      over: .init(backgroundColor: backdrop), blendMode: blendMode
    ).backgroundColor
  }
  let (sourceTop, sourceBottom) = halves(source)
  let (underTop, underBottom) = halves(underlay)
  let top = composed(sourceTop, over: underTop)
  let bottom = composed(sourceBottom, over: underBottom)
  var style = source.style ?? .init()
  let character: Character
  if let top {
    character = "▀"
    style.foregroundColor = top
    style.backgroundColor = bottom
  } else if let bottom {
    character = "▄"
    style.foregroundColor = bottom
    style.backgroundColor = nil
  } else {
    return underlay
  }
  return RasterCell(character: character, style: style, hyperlink: source.hyperlink)
}

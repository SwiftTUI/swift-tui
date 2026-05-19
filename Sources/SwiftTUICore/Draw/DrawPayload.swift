/// The payload attached to a draw node.
@_spi(Testing) public indirect enum DrawPayload: Equatable, Sendable {
  case none
  case text(String)
  case textFigure(TextFigurePayload)
  case richText(RichTextPayload)
  case image(ImagePayload)
  case shape(ShapePayload)
  case rule(StrokeStyle?)
  case list(ListPayload)
  case table(TablePayload)
  case canvas(CanvasPayload)
  case foreignSurface(any ForeignSurfacePayload)
}

extension DrawPayload {
  public static func == (lhs: DrawPayload, rhs: DrawPayload) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
      return true
    case (.text(let lhsContent), .text(let rhsContent)):
      return lhsContent == rhsContent
    case (.textFigure(let lhsPayload), .textFigure(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.richText(let lhsPayload), .richText(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.image(let lhsPayload), .image(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.shape(let lhsPayload), .shape(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.rule(let lhsStyle), .rule(let rhsStyle)):
      return lhsStyle == rhsStyle
    case (.list(let lhsPayload), .list(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.table(let lhsPayload), .table(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.canvas(let lhsPayload), .canvas(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.foreignSurface, .foreignSurface):
      return true
    default:
      return false
    }
  }
}

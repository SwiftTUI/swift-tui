extension SnapshotRenderer {
  func describe(_ style: TextStyle) -> String {
    var parts: [String] = []
    if let foregroundStyle = style.foregroundStyle {
      parts.append("fg=\(describe(foregroundStyle))")
    }
    if let backgroundStyle = style.backgroundStyle {
      parts.append("bg=\(describe(backgroundStyle))")
    }
    if !style.emphasis.isEmpty {
      parts.append("emphasis=\(style.emphasis.debugNames.joined(separator: "+"))")
    }
    if let underlineStyle = style.underlineStyle {
      parts.append("underline=\(describe(underlineStyle))")
    }
    if let strikethroughStyle = style.strikethroughStyle {
      parts.append("strikethrough=\(describe(strikethroughStyle))")
    }
    if style.opacity != 1 {
      parts.append("opacity=\(style.opacity)")
    }
    return parts.joined(separator: ",")
  }

  func describe(_ style: ResolvedTextStyle) -> String {
    var parts: [String] = []
    if let foregroundColor = style.foregroundColor {
      parts.append("fg=\(foregroundColor.hexString(format: .rrggbbaa))")
    }
    if let backgroundColor = style.backgroundColor {
      parts.append("bg=\(backgroundColor.hexString(format: .rrggbbaa))")
    }
    if !style.emphasis.isEmpty {
      parts.append("emphasis=\(style.emphasis.debugNames.joined(separator: "+"))")
    }
    if let underlineStyle = style.underlineStyle {
      parts.append("underline=\(describe(underlineStyle))")
    }
    if let strikethroughStyle = style.strikethroughStyle {
      parts.append("strikethrough=\(describe(strikethroughStyle))")
    }
    if style.opacity != 1 {
      parts.append("opacity=\(style.opacity)")
    }
    return parts.joined(separator: ",")
  }

  func describe(_ style: AnyShapeStyle) -> String {
    switch style {
    case .semantic(let role):
      return role.rawValue
    case .color(let color):
      return color.hexString(format: .rrggbbaa)
    case .linearGradient(let gradient):
      return "linearGradient(\(describe(gradient)))"
    case .radialGradient(let gradient):
      return "radialGradient(\(describe(gradient)))"
    case .meshGradient(let gradient):
      return "meshGradient(\(describe(gradient)))"
    case .tileStyle(let tile):
      return "tileStyle(\(describe(tile)))"
    case .terminalChrome(let chromeStyle):
      return describe(chromeStyle)
    case .opacity(let inner, let amount):
      return "\(describe(inner)).opacity(\(amount))"
    }
  }

  private func describe(_ tile: TileStyle) -> String {
    let rows = tile.pattern.rows.map { row in
      String(row)
    }.joined(separator: "/")
    let fg = describe(tile.foreground.style)
    if let background = tile.background {
      return "rows=\(rows),fg=\(fg),bg=\(describe(background.style))"
    }
    return "rows=\(rows),fg=\(fg)"
  }

  private func describe(_ style: TerminalChromeStyle) -> String {
    switch style.kind {
    case .accent(let tone):
      return "terminalAccent(\(tone.rawValue))"
    case .surface(let tone):
      return "terminalSurface(\(tone.rawValue))"
    case .surfaceBackground:
      return "terminalSurfaceBackground"
    case .border(let tone):
      return "terminalBorder(\(tone.rawValue))"
    case .tile(let tone):
      return "terminalTile(\(tone.rawValue))"
    case .row(let tone, let isSelected, let isOdd):
      return "terminalRow(\(tone.rawValue),selected:\(isSelected),odd:\(isOdd))"
    case .badge(let tone, let emphasized):
      return "terminalBadge(\(tone.rawValue),emphasized:\(emphasized))"
    case .keycap(let tone):
      return "terminalKeycap(\(tone.rawValue))"
    case .tab(let tone, let isSelected):
      return "terminalTab(\(tone.rawValue),selected:\(isSelected))"
    }
  }

  private func describe(_ gradient: LinearGradient) -> String {
    let stops = gradient.gradient.stops.map { stop in
      "\(stop.color.hexString(format: .rrggbbaa))@\(stop.location)"
    }.joined(separator: ",")
    return
      "start=(\(gradient.startPoint.x),\(gradient.startPoint.y))"
      + "->end=(\(gradient.endPoint.x),\(gradient.endPoint.y)):[\(stops)]"
  }

  private func describe(_ gradient: RadialGradient) -> String {
    let stops = gradient.gradient.stops.map { stop in
      "\(stop.color.hexString(format: .rrggbbaa))@\(stop.location)"
    }.joined(separator: ",")
    return
      "center=(\(gradient.center.x),\(gradient.center.y)),"
      + "startRadius=\(gradient.startRadius),endRadius=\(gradient.endRadius):[\(stops)]"
  }

  private func describe(_ gradient: MeshGradient) -> String {
    let points = gradient.points.map { "(\($0.x),\($0.y))" }.joined(separator: ",")
    let colors = gradient.colors.map(describeMeshColor).joined(separator: ",")
    return
      "size=\(gradient.width)x\(gradient.height),points=[\(points)],colors=[\(colors)],"
      + "background=\(describeMeshColor(gradient.background)),"
      + "smoothsColors=\(gradient.smoothsColors),colorSpace=\(gradient.colorSpace)"
  }

  private func describeMeshColor(_ color: Color) -> String {
    "\(color.red),\(color.green),\(color.blue),\(color.alpha)@\(String(reflecting: color.profile))"
  }

  private func describe(_ lineStyle: TextLineStyle) -> String {
    if let color = lineStyle.color {
      return "\(lineStyle.pattern.rawValue):\(color.hexString(format: .rrggbbaa))"
    }
    return lineStyle.pattern.rawValue
  }

  func describe(
    _ geometry: ShapeGeometry,
    insetAmount: Int = 0
  ) -> String {
    let base =
      switch geometry {
      case .rectangle:
        "rectangle"
      case .roundedRectangle(let cornerRadius):
        "roundedRectangle(\(cornerRadius))"
      case .circle:
        "circle"
      case .ellipse:
        "ellipse"
      case .capsule:
        "capsule"
      case .path(let boxed, let fillRule):
        "path(elements: \(boxed.path.elements.count), fill: \(fillRule))"
      }
    if insetAmount > 0 {
      return "\(base).inset(\(insetAmount))"
    }
    return base
  }

  func describe(_ payload: ShapePayload) -> String {
    "\(describe(payload.geometry, insetAmount: payload.insetAmount)),\(describe(payload.operation))"
  }

  private func describe(_ operation: ShapeOperation) -> String {
    switch operation {
    case .fill(let style, let mode):
      return "fill(\(style.map(describe) ?? "foreground"),mode=\(describe(mode)))"
    case .stroke(let style, let strokeStyle, let strokeBorder, let backgroundStyle):
      return
        "stroke(\(style.map(describe) ?? "foreground"),\(describe(strokeStyle)),border=\(strokeBorder),bg=\(backgroundStyle.map(describe) ?? "nil"))"
    }
  }

  func describe(_ mode: ShapeFillMode) -> String {
    switch mode {
    case .full:
      return "full"
    case .interior(let strokeWidth):
      return "interior(\(strokeWidth))"
    }
  }

  func describe(_ style: BorderBackgroundStyle) -> String {
    [
      "top=\(style.top.map(describe) ?? "nil")",
      "right=\(style.right.map(describe) ?? "nil")",
      "bottom=\(style.bottom.map(describe) ?? "nil")",
      "left=\(style.left.map(describe) ?? "nil")",
    ].joined(separator: ",")
  }

  func describe(_ strokeStyle: StrokeStyle) -> String {
    "width:\(strokeStyle.lineWidth),set:\(describeBorderSetName(strokeStyle.borderSet))"
  }

  private func describeBorderSetName(_ set: BorderSet) -> String {
    switch set {
    case .single: return "single"
    case .rounded: return "rounded"
    case .double: return "double"
    case .heavy: return "heavy"
    case .block: return "block"
    case .outerHalfBlock: return "outerHalfBlock"
    case .innerHalfBlock: return "innerHalfBlock"
    case .singleDouble: return "singleDouble"
    case .doubleSingle: return "doubleSingle"
    case .ascii: return "ascii"
    case .hidden: return "hidden"
    case .none: return "none"
    case .dashed: return "dashed"
    case .dashedHeavy: return "dashedHeavy"
    case .markdown: return "markdown"
    default:
      return
        "custom(top:\(set.top),bottom:\(set.bottom),left:\(set.left),right:\(set.right))"
    }
  }
}

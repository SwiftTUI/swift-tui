/// Renders internal frame artifacts into readable text fixtures.
public struct SnapshotRenderer {
  public init() {}

  public func frameDiagnostics(_ diagnostics: FrameDiagnostics) -> String {
    var lines: [String] = []
    lines.append("proposal=\(describe(diagnostics.proposal))")
    lines.append(
      "invalidatedIdentities=\(describe(diagnostics.invalidatedIdentities))"
    )
    lines.append("resolvedNodes=\(diagnostics.resolvedNodeCount)")
    lines.append("measuredNodes=\(diagnostics.measuredNodeCount)")
    lines.append("placedNodes=\(diagnostics.placedNodeCount)")
    lines.append(
      "resolvedWork=computed:\(diagnostics.resolvedNodesComputed) reused:\(diagnostics.resolvedNodesReused)"
    )
    lines.append(
      "measuredWork=computed:\(diagnostics.measuredNodesComputed) reused:\(diagnostics.measuredNodesReused)"
    )
    lines.append(
      "placedWork=computed:\(diagnostics.placedNodesComputed) reused:\(diagnostics.placedNodesReused)"
    )
    lines.append("drawNodes=\(diagnostics.drawNodeCount)")
    lines.append("interactionRegions=\(diagnostics.interactionRegionCount)")
    lines.append("focusRegions=\(diagnostics.focusRegionCount)")
    lines.append("scrollRoutes=\(diagnostics.scrollRouteCount)")
    lines.append("selectionRoutes=\(diagnostics.selectionRouteCount)")
    if let phaseTimings = diagnostics.phaseTimings {
      lines.append(
        "phaseTimings=resolve:\(describe(phaseTimings.resolve)) measure:\(describe(phaseTimings.measure)) place:\(describe(phaseTimings.place)) semantics:\(describe(phaseTimings.semantics)) draw:\(describe(phaseTimings.draw)) raster:\(describe(phaseTimings.raster)) commit:\(describe(phaseTimings.commit)) total:\(describe(phaseTimings.total))"
      )
    } else {
      lines.append("phaseTimings=nil")
    }

    if let cache = diagnostics.measurementCache {
      lines.append(
        "measurementCache=generation:\(cache.generation) entries:\(cache.entries) lookups:\(cache.lookups) hits:\(cache.hits) misses:\(cache.misses) stores:\(cache.stores)"
      )
    } else {
      lines.append("measurementCache=nil")
    }

    return lines.joined(separator: "\n")
  }

  public func resolvedTree(_ node: ResolvedNode) -> String {
    renderResolved(node, depth: 0).joined(separator: "\n")
  }

  public func measuredTree(_ node: MeasuredNode) -> String {
    renderMeasured(node, depth: 0).joined(separator: "\n")
  }

  public func placedTree(_ node: PlacedNode) -> String {
    renderPlaced(node, depth: 0).joined(separator: "\n")
  }

  public func semanticSnapshot(_ snapshot: SemanticSnapshot) -> String {
    var lines: [String] = []
    lines.append("interactionRegions: \(snapshot.interactionRegions.count)")
    for region in snapshot.interactionRegions {
      lines.append(
        "  \(region.identity.path) rect=\(describe(region.rect)) route=\(region.routeID)")
    }
    lines.append("focusRegions: \(snapshot.focusRegions.count)")
    for region in snapshot.focusRegions {
      lines.append("  \(region.identity.path) rect=\(describe(region.rect))")
    }
    lines.append("scrollRoutes: \(snapshot.scrollRoutes.count)")
    for route in snapshot.scrollRoutes {
      lines.append(
        "  \(route.identity.path) viewport=\(describe(route.viewportRect)) content=\(describe(route.contentBounds))"
      )
    }
    lines.append("selectionRoutes: \(snapshot.selectionRoutes.count)")
    for route in snapshot.selectionRoutes {
      lines.append("  \(route.identity.path) role=\(route.role)")
    }
    return lines.joined(separator: "\n")
  }

  public func drawTree(_ node: DrawNode) -> String {
    renderDraw(node, depth: 0).joined(separator: "\n")
  }

  public func rasterSurface(_ surface: RasterSurface) -> String {
    let header = "size=\(surface.size.width)x\(surface.size.height)"
    var lines = [header]
    if !surface.styleRuns.isEmpty {
      lines.append("styles=\(surface.styleRuns.map(describe).joined(separator: ", "))")
    }
    if !surface.imageAttachments.isEmpty {
      lines.append(
        "images=\(surface.imageAttachments.map(describe).joined(separator: ", "))"
      )
    }
    if surface.lines.isEmpty {
      return lines.joined(separator: "\n")
    }
    return (lines + surface.lines.map { "  \($0)" }).joined(separator: "\n")
  }

  public func scheduledFrame(_ frame: ScheduledFrame) -> String {
    [
      "causes=\(frame.causes.map(\.rawValue).sorted().joined(separator: ","))",
      "invalidatedIdentities=\(frame.invalidatedIdentities.map(\.path).sorted().joined(separator: ","))",
      "signalNames=\(frame.signalNames.joined(separator: ","))",
      "externalReasons=\(frame.externalReasons.joined(separator: ","))",
      "triggeredDeadline=\(describe(frame.triggeredDeadline))",
      "nextDeadline=\(describe(frame.nextDeadline))",
    ].joined(separator: "\n")
  }

  public func frameArtifacts(_ artifacts: FrameArtifacts) -> String {
    [
      "[Resolved]",
      resolvedTree(artifacts.resolvedTree),
      "[Measured]",
      measuredTree(artifacts.measuredTree),
      "[Placed]",
      placedTree(artifacts.placedTree),
      "[Semantics]",
      semanticSnapshot(artifacts.semanticSnapshot),
      "[Draw]",
      drawTree(artifacts.drawTree),
      "[Raster]",
      rasterSurface(artifacts.rasterSurface),
      "[Diagnostics]",
      frameDiagnostics(artifacts.diagnostics),
    ].joined(separator: "\n")
  }
}

extension SnapshotRenderer {
  private func describe(
    _ identities: Set<Identity>
  ) -> String {
    let paths = identities.map(\.path).sorted()
    return paths.isEmpty ? "none" : paths.joined(separator: ",")
  }

  private func describe(
    _ duration: Duration
  ) -> String {
    let components = duration.components
    let milliseconds =
      Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
    let rounded = (milliseconds * 100).rounded() / 100
    return "\(rounded)ms"
  }

  private func renderResolved(
    _ node: ResolvedNode,
    depth: Int
  ) -> [String] {
    let line =
      "\(indent(depth))\(node.identity.path) kind=\(describe(node.kind)) layout=\(describe(node.layoutBehavior)) size=\(describe(node.intrinsicSize)) payload=\(describe(node.drawPayload))"
    return [line] + node.children.flatMap { renderResolved($0, depth: depth + 1) }
  }

  private func renderMeasured(
    _ node: MeasuredNode,
    depth: Int
  ) -> [String] {
    let line =
      "\(indent(depth))\(node.identity.path) proposal=\(describe(node.proposal)) size=\(node.measuredSize.width)x\(node.measuredSize.height)"
    return [line] + node.childMeasurements.flatMap { renderMeasured($0, depth: depth + 1) }
  }

  private func renderPlaced(
    _ node: PlacedNode,
    depth: Int
  ) -> [String] {
    let line =
      "\(indent(depth))\(node.identity.path) kind=\(describe(node.kind)) bounds=\(describe(node.bounds)) role=\(node.semanticRole.rawValue) payload=\(describe(node.drawPayload))"
    return [line] + node.children.flatMap { renderPlaced($0, depth: depth + 1) }
  }

  private func renderDraw(
    _ node: DrawNode,
    depth: Int
  ) -> [String] {
    let clipDescription = node.clipBounds.map { " clip=\(describe($0))" } ?? ""
    let line =
      "\(indent(depth))\(node.identity.path) bounds=\(describe(node.bounds))\(clipDescription) commands=\(node.commands.map(describe).joined(separator: ", "))"
    return [line] + node.children.flatMap { renderDraw($0, depth: depth + 1) }
  }

  private func indent(_ depth: Int) -> String {
    String(repeating: "  ", count: depth)
  }

  private func describe(_ kind: NodeKind) -> String {
    switch kind {
    case .root:
      return "root"
    case .scene(let name):
      return "scene(\(name))"
    case .view(let name):
      return "view(\(name))"
    }
  }

  private func describe(_ behavior: LayoutBehavior) -> String {
    switch behavior {
    case .intrinsic:
      return "intrinsic"
    case .overlay(let alignment):
      return "overlay(\(alignment.rawValue))"
    case .stack(
      let axis, let spacing, let horizontalAlignment, let verticalAlignment
    ):
      let alignmentDescription =
        switch axis {
        case .horizontal:
          verticalAlignment.debugName
        case .vertical:
          horizontalAlignment.debugName
        }
      if let spacing, alignmentDescription == "center" {
        return "stack(\(axis.rawValue),\(spacing))"
      }
      let spacingDescription = spacing.map { String($0) } ?? "default"
      return "stack(\(axis.rawValue),\(spacingDescription),\(alignmentDescription))"
    case .lazyStack(
      let axis, let spacing, let horizontalAlignment, let verticalAlignment
    ):
      let alignmentDescription =
        switch axis {
        case .horizontal:
          verticalAlignment.debugName
        case .vertical:
          horizontalAlignment.debugName
        }
      if let spacing, alignmentDescription == "center" {
        return "lazyStack(\(axis.rawValue),\(spacing))"
      }
      let spacingDescription = spacing.map { String($0) } ?? "default"
      return "lazyStack(\(axis.rawValue),\(spacingDescription),\(alignmentDescription))"
    case .padding(let insets):
      return "padding(\(insets.top),\(insets.leading),\(insets.bottom),\(insets.trailing))"
    case .frame(let width, let height, let alignment):
      let widthDescription = width.map { String($0) } ?? "nil"
      let heightDescription = height.map { String($0) } ?? "nil"
      return "frame(\(widthDescription),\(heightDescription),\(alignment.rawValue))"
    case .flexibleFrame(
      let minW, let idealW, let maxW, let minH, let idealH, let maxH, let alignment):
      func desc(_ d: ProposedDimension?) -> String {
        guard let d else { return "nil" }
        switch d {
        case .unspecified: return "unspecified"
        case .finite(let v): return String(v)
        case .infinity: return "infinity"
        }
      }
      return
        "flexibleFrame(min:\(desc(minW)),ideal:\(desc(idealW)),max:\(desc(maxW)),min:\(desc(minH)),ideal:\(desc(idealH)),max:\(desc(maxH)),\(alignment.rawValue))"
    case .decoration(let primaryIndex, let alignment):
      return "decoration(primary:\(primaryIndex),\(alignment.rawValue))"
    case .viewThatFits(let axes):
      var names: [String] = []
      if axes.contains(.horizontal) {
        names.append("horizontal")
      }
      if axes.contains(.vertical) {
        names.append("vertical")
      }
      return "viewThatFits(\(names.joined(separator: "+")))"
    case .custom(let handle):
      return "custom(\(handle.debugName))"
    }
  }

  private func describe(_ payload: DrawPayload) -> String {
    switch payload {
    case .none:
      return "none"
    case .text(let content):
      return "text(\(content))"
    case .textFigure(let payload):
      return "textFigure(text=\(payload.content),font=\(payload.font))"
    case .richText(let payload):
      return "richText(text=\(payload.visibleText),links=\(payload.linkCount))"
    case .image(let payload):
      return "image(source=\(describe(payload.source)),asset=\(describe(payload.resolvedAsset)))"
    case .shape(let payload):
      return "shape(\(describe(payload)))"
    case .rule(let strokeStyle):
      return "rule(\(describe(strokeStyle ?? .init())))"
    case .list(let payload):
      return
        "list(style=\(payload.style),items=\(payload.items.count),selected=\(payload.selectedRowIndex.map { String($0) } ?? "nil"))"
    case .table(let payload):
      return
        "table(style=\(payload.style),rows=\(payload.rows.count),selected=\(payload.selectedRowIndex.map { String($0) } ?? "nil"))"
    }
  }

  private func describe(_ size: Size?) -> String {
    guard let size else {
      return "nil"
    }
    return "\(size.width)x\(size.height)"
  }

  private func describe(_ rect: Rect) -> String {
    "@(\(rect.origin.x),\(rect.origin.y)) \(rect.size.width)x\(rect.size.height)"
  }

  private func describe(_ proposal: ProposedSize) -> String {
    "(\(describe(proposal.width)),\(describe(proposal.height)))"
  }

  private func describe(_ dimension: ProposedDimension) -> String {
    switch dimension {
    case .unspecified:
      return "unspecified"
    case .infinity:
      return "infinity"
    case .finite(let value):
      return String(value)
    }
  }

  private func describe(
    _ instant: MonotonicInstant?
  ) -> String {
    guard let instant else {
      return "nil"
    }
    let totalSeconds =
      Double(instant.offset.components.seconds)
      + (Double(instant.offset.components.attoseconds) / 1_000_000_000_000_000_000)
    let roundedMilliseconds = Int((totalSeconds * 1000).rounded())
    let wholeSeconds = roundedMilliseconds / 1000
    let fractionalMilliseconds = abs(roundedMilliseconds % 1000)
    let fractionalString = String(fractionalMilliseconds)
    let paddedFractional =
      String(repeating: "0", count: max(0, 3 - fractionalString.count))
      + fractionalString
    return "\(wholeSeconds).\(paddedFractional)"
  }

  private func describe(_ command: DrawCommand) -> String {
    switch command {
    case .group(let bounds, _):
      return "group[\(describe(bounds))]"
    case .text(
      let bounds,
      let content,
      let style,
      let lineLimit,
      let truncationMode,
      let wrappingStrategy
    ):
      var details = "text[\(describe(bounds))=\"\(content)\""
      if lineLimit != nil {
        details += " lines=\(lineLimit!)"
      }
      if truncationMode != .tail || !style.isDefault {
        details += " truncation=\(truncationMode.rawValue)"
      }
      if wrappingStrategy != .wordBoundary {
        details += " wrapping=\(wrappingStrategy.rawValue)"
      }
      if !style.isDefault {
        details += " style=\(describe(style))"
      }
      details += "]"
      return details
    case .preformattedText(
      let bounds,
      let lines,
      let style
    ):
      var details = "preformattedText[\(describe(bounds)) lines=\(lines.count)"
      if let firstLine = lines.first {
        details += " firstLine=\"\(firstLine)\""
      }
      if !style.isDefault {
        details += " style=\(describe(style))"
      }
      details += "]"
      return details
    case .richText(
      let bounds,
      let payload,
      let lineLimit,
      let truncationMode,
      let wrappingStrategy
    ):
      var details = "richText[\(describe(bounds))=\"\(payload.visibleText)\""
      if lineLimit != nil {
        details += " lines=\(lineLimit!)"
      }
      if truncationMode != .tail {
        details += " truncation=\(truncationMode.rawValue)"
      }
      if wrappingStrategy != .wordBoundary {
        details += " wrapping=\(wrappingStrategy.rawValue)"
      }
      if payload.linkCount > 0 {
        details += " links=\(payload.linkCount)"
      }
      details += "]"
      return details
    case .image(let bounds, let identity, let payload):
      return
        "image[\(describe(bounds)) id=\(identity.path) source=\(describe(payload.source)) asset=\(describe(payload.resolvedAsset))]"
    case .fill(let bounds, let geometry, let insetAmount, let style, let mode):
      return
        "fill[\(describe(bounds)) \(describe(geometry, insetAmount: insetAmount)) mode=\(describe(mode)) style=\(describe(style))]"
    case .stroke(
      let bounds, let geometry, let insetAmount, let style, let strokeStyle, let strokeBorder,
      let backgroundStyle):
      return
        "stroke[\(describe(bounds)) \(describe(geometry, insetAmount: insetAmount)) \(describe(strokeStyle)) border=\(strokeBorder) style=\(describe(style)) bg=\(backgroundStyle.map(describe) ?? "nil")]"
    case .rule(let bounds, let style, let strokeStyle, let stackAxis):
      return
        "rule[\(describe(bounds)) \(describe(strokeStyle)) style=\(describe(style)) stackAxis=\(stackAxis?.rawValue ?? "nil")]"
    case .clip(let bounds, _):
      return "clip[\(describe(bounds))]"
    }
  }

  private func describe(_ style: TextStyle) -> String {
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

  private func describe(_ source: ImageSource) -> String {
    switch source {
    case .named(let name):
      return "named(\(name))"
    case .fileURL(let value):
      return "fileURL(\(value))"
    case .pngData(let bytes):
      return "pngData(\(bytes.count)b)"
    }
  }

  private func describe(_ asset: ResolvedImageAsset?) -> String {
    guard let asset else {
      return "nil"
    }
    return
      "\(describe(asset.reference)) px=\(asset.pixelSize.width)x\(asset.pixelSize.height) cells=\(asset.intrinsicCellSize.width)x\(asset.intrinsicCellSize.height)"
  }

  private func describe(_ reference: ImageAssetReference) -> String {
    switch reference {
    case .namedResource(let name):
      return "namedResource(\(name))"
    case .filePath(let path):
      return "filePath(\(path))"
    case .embeddedPNG(let bytes):
      return "embeddedPNG(\(bytes.count)b)"
    }
  }

  private func describe(_ attachment: RasterImageAttachment) -> String {
    "attachment[id=\(attachment.identity.path) \(describe(attachment.bounds)) source=\(describe(attachment.source)) ref=\(attachment.resolvedReference.map(describe) ?? "nil")]"
  }

  private func describe(_ styleRun: RasterStyleRun) -> String {
    "@(\(styleRun.x),\(styleRun.y))+\(styleRun.length){\(describe(styleRun.style))}"
  }

  private func describe(_ style: ResolvedTextStyle) -> String {
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

  private func describe(_ style: AnyShapeStyle) -> String {
    switch style {
    case .semantic(let role):
      return role.rawValue
    case .color(let color):
      return color.hexString(format: .rrggbbaa)
    case .linearGradient(let gradient):
      return "linearGradient(\(describe(gradient)))"
    case .terminalChrome(let chromeStyle):
      return describe(chromeStyle)
    case .opacity(let inner, let amount):
      return "\(describe(inner)).opacity(\(amount))"
    }
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
    return "\(gradient.startPoint.rawValue)->\(gradient.endPoint.rawValue):[\(stops)]"
  }

  private func describe(_ lineStyle: TextLineStyle) -> String {
    if let color = lineStyle.color {
      return "\(lineStyle.pattern.rawValue):\(color.hexString(format: .rrggbbaa))"
    }
    return lineStyle.pattern.rawValue
  }

  private func describe(
    _ geometry: ShapeGeometry,
    insetAmount: Int = 0
  ) -> String {
    let base =
      switch geometry {
      case .rectangle:
        "rectangle"
      case .roundedRectangle(let cornerRadius):
        "roundedRectangle(\(cornerRadius))"
      }
    if insetAmount > 0 {
      return "\(base).inset(\(insetAmount))"
    }
    return base
  }

  private func describe(_ payload: ShapePayload) -> String {
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

  private func describe(_ mode: ShapeFillMode) -> String {
    switch mode {
    case .full:
      return "full"
    case .interior(let strokeWidth):
      return "interior(\(strokeWidth))"
    }
  }

  private func describe(_ style: BorderBackgroundStyle) -> String {
    [
      "top=\(style.top.map(describe) ?? "nil")",
      "right=\(style.right.map(describe) ?? "nil")",
      "bottom=\(style.bottom.map(describe) ?? "nil")",
      "left=\(style.left.map(describe) ?? "nil")",
    ].joined(separator: ",")
  }

  private func describe(_ strokeStyle: StrokeStyle) -> String {
    "width:\(strokeStyle.lineWidth),variant:\(strokeStyle.lineVariant.rawValue)"
  }

  private func hexadecimal(_ component: Int) -> String {
    let digits = Array("0123456789ABCDEF")
    let value = min(255, max(0, component))
    return String([digits[value / 16], digits[value % 16]])
  }
}

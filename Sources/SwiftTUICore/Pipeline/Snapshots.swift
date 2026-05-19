/// Renders internal frame artifacts into readable text fixtures.
public struct SnapshotRenderer {
  public init() {}

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
    lines.append("scrollTargets: \(snapshot.scrollTargets.count)")
    for target in snapshot.scrollTargets {
      lines.append(
        "  \(target.identity.path) scroll=\(target.scrollIdentity.path) rect=\(describe(target.rect))"
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
    case .safeAreaIgnoring(let insets):
      return
        "safeAreaIgnoring(\(insets.top),\(insets.leading),\(insets.bottom),\(insets.trailing))"
    case .safeAreaInset(let edge, let alignment, let spacing, let safeArea):
      return
        "safeAreaInset(\(edge),\(alignment.rawValue),spacing:\(spacing),safeArea:\(safeArea.top),\(safeArea.leading),\(safeArea.bottom),\(safeArea.trailing))"
    case .border(_, _, _, _, _, _, let sides):
      var names: [String] = []
      if sides.contains(.top) { names.append("top") }
      if sides.contains(.leading) { names.append("leading") }
      if sides.contains(.bottom) { names.append("bottom") }
      if sides.contains(.trailing) { names.append("trailing") }
      let sidesDescription = names.isEmpty ? "none" : names.joined(separator: "+")
      return "border(sides:\(sidesDescription))"
    case .frame(let width, let height, let alignment):
      let widthDescription = width.map { String($0) } ?? "nil"
      let heightDescription = height.map { String($0) } ?? "nil"
      return "frame(\(widthDescription),\(heightDescription),\(alignment.rawValue))"
    case .offset(let x, let y):
      return "offset(\(x),\(y))"
    case .position(let x, let y):
      return "position(\(x),\(y))"
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
    case .canvas(let payload):
      return "canvas(drawing=\(type(of: payload.drawing)))"
    case .foreignSurface(let payload):
      let grid = payload.grid
      return "foreignSurface(grid=\(grid.size.width)x\(grid.size.height))"
    }
  }

  private func describe(_ size: CellSize?) -> String {
    guard let size else {
      return "nil"
    }
    return "\(size.width)x\(size.height)"
  }

  private func describe(_ rect: CellRect) -> String {
    "@(\(rect.origin.x),\(rect.origin.y)) \(rect.size.width)x\(rect.size.height)"
  }

  func describe(_ proposal: ProposedSize) -> String {
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
    case .styledPreformattedText(
      let bounds,
      let lines,
      let style
    ):
      var details = "styledPreformattedText[\(describe(bounds)) lines=\(lines.count)"
      if let firstLine = lines.first {
        details += " firstLine=\"\(firstLine.content)\""
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
    case .border(let bounds, _, _, _, _, _, let sides):
      var sideNames: [String] = []
      if sides.contains(.top) { sideNames.append("top") }
      if sides.contains(.leading) { sideNames.append("leading") }
      if sides.contains(.bottom) { sideNames.append("bottom") }
      if sides.contains(.trailing) { sideNames.append("trailing") }
      let sidesDescription = sideNames.isEmpty ? "none" : sideNames.joined(separator: "+")
      return "border[\(describe(bounds)) sides=\(sidesDescription)]"
    case .canvas(let bounds, let payload, let foregroundStyle):
      return
        "canvas[\(describe(bounds)) drawing=\(type(of: payload.drawing)) style=\(describe(foregroundStyle))]"
    case .foreignSurface(let bounds, let payload):
      let grid = payload.grid
      return
        "foreignSurface[\(describe(bounds)) grid=\(grid.size.width)x\(grid.size.height)]"
    case .clip(let bounds, _):
      return "clip[\(describe(bounds))]"
    }
  }

  private func describe(_ source: ImageSource) -> String {
    switch source {
    case .path(let name):
      return "path(\(name))"
    case .fileURL(let value):
      return "fileURL(\(value))"
    case .data(let bytes):
      return "data(\(bytes.count)b)"
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
    case .embeddedImage(let bytes):
      return "embeddedImage(\(bytes.count)b)"
    }
  }

  private func describe(_ attachment: RasterImageAttachment) -> String {
    "attachment[id=\(attachment.identity.path) \(describe(attachment.bounds)) source=\(describe(attachment.source)) ref=\(attachment.resolvedReference.map(describe) ?? "nil")]"
  }

  private func describe(_ styleRun: RasterStyleRun) -> String {
    "@(\(styleRun.x),\(styleRun.y))+\(styleRun.length){\(describe(styleRun.style))}"
  }

}

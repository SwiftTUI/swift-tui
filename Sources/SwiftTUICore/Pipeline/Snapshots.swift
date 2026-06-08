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
    if !surface.presentationLayers.isEmpty {
      lines.append(
        "layers=\(surface.presentationLayers.map(describe).joined(separator: ", "))"
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
}

// Tree-structural `describe(_:)` value formatters live in
// `SnapshotRenderer+TreeDescriptions.swift`; style formatters live in
// `SnapshotRenderer+StyleDescriptions.swift`.

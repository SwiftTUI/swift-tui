@_spi(Testing) import SwiftTUIPrimitives

// Value-formatting helpers for resolved/measured/placed/draw tree snapshots.
//
// `SnapshotRenderer` walks each pipeline tree (see `Snapshots.swift`) and
// formats every node into a stable one-line description for text fixtures.
// This file owns the `describe(_:)` overloads for tree-structural values —
// node kinds, layout behaviors, draw payloads, geometry, and draw commands.
// Style-specific `describe` overloads live in
// `SnapshotRenderer+StyleDescriptions.swift`.
//
// These are file-internal rather than `private` so the tree walkers in
// `Snapshots.swift` can reach them, matching the cross-file convention already
// used by the style-description overloads.
extension SnapshotRenderer {
  func describe(_ kind: NodeKind) -> String {
    switch kind {
    case .root:
      return "root"
    case .scene(let name):
      return "scene(\(name))"
    case .view(let name):
      return "view(\(name))"
    }
  }

  func describe(_ behavior: LayoutBehavior) -> String {
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

  func describe(_ payload: DrawPayload) -> String {
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

  func describe(_ size: CellSize?) -> String {
    guard let size else {
      return "nil"
    }
    return "\(size.width)x\(size.height)"
  }

  func describe(_ rect: CellRect) -> String {
    "@(\(rect.origin.x),\(rect.origin.y)) \(rect.size.width)x\(rect.size.height)"
  }

  func describe(_ proposal: ProposedSize) -> String {
    "(\(describe(proposal.width)),\(describe(proposal.height)))"
  }

  func describe(_ dimension: ProposedDimension) -> String {
    switch dimension {
    case .unspecified:
      return "unspecified"
    case .infinity:
      return "infinity"
    case .finite(let value):
      return String(value)
    }
  }

  func describe(_ command: DrawCommand) -> String {
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

  func describe(_ source: ImageSource) -> String {
    switch source {
    case .path(let name):
      return "path(\(name))"
    case .fileURL(let value):
      return "fileURL(\(value))"
    case .data(let bytes):
      return "data(\(bytes.count)b)"
    }
  }

  func describe(_ asset: ResolvedImageAsset?) -> String {
    guard let asset else {
      return "nil"
    }
    return
      "\(describe(asset.reference)) px=\(asset.pixelSize.width)x\(asset.pixelSize.height) cells=\(asset.intrinsicCellSize.width)x\(asset.intrinsicCellSize.height)"
  }

  func describe(_ reference: ImageAssetReference) -> String {
    switch reference {
    case .namedResource(let name):
      return "namedResource(\(name))"
    case .filePath(let path):
      return "filePath(\(path))"
    case .embeddedImage(let bytes):
      return "embeddedImage(\(bytes.count)b)"
    }
  }

  func describe(_ attachment: RasterImageAttachment) -> String {
    let compositing =
      if let imageCompositing = attachment.compositing {
        " blend=\(imageCompositing.blendMode.rawValue) backdrop=\(imageCompositing.backdropSignature)"
      } else {
        ""
      }
    return
      "attachment[id=\(attachment.identity.path) \(describe(attachment.bounds)) source=\(describe(attachment.source)) ref=\(attachment.resolvedReference.map(describe) ?? "nil")\(compositing)]"
  }

  func describe(_ layer: RasterPresentationLayer) -> String {
    let effectDescription =
      layer.effects.isEmpty
      ? ""
      : " effects=\(layer.effects.map(describe).joined(separator: "+"))"
    switch layer.content {
    case .cells(let fragment):
      return "#\(layer.order) cells[\(describe(fragment.bounds))]\(effectDescription)"
    case .image(let attachment):
      return
        "#\(layer.order) image[\(describe(attachment.visibleBounds)) id=\(attachment.identity.path)]\(effectDescription)"
    }
  }

  func describe(_ effect: DrawEffect) -> String {
    switch effect {
    case .blendMode(let blendMode):
      return "blendMode(\(blendMode.rawValue))"
    case .compositingGroup:
      return "compositingGroup"
    }
  }

  func describe(_ styleRun: RasterStyleRun) -> String {
    "@(\(styleRun.x),\(styleRun.y))+\(styleRun.length){\(describe(styleRun.style))}"
  }
}

/// Converts draw commands into a terminal cell surface.
public struct Rasterizer {
  private static let emptyCompositingStyle = ResolvedTextStyle()
  private enum ResolvedShapeColorMode {
    case constant(Color?)
    case sampled(LinearGradient)
  }

  public init() {}

  /// Rasterizes a draw tree into a ``RasterSurface``.
  public func rasterize(_ draw: DrawNode) -> RasterSurface {
    rasterize(draw, minimumSize: .zero)
  }

  package func rasterize(
    _ draw: DrawNode,
    minimumSize: Size
  ) -> RasterSurface {
    rasterize(draw, minimumSize: minimumSize, previousSurface: nil, damage: nil)
  }

  package func rasterize(
    _ draw: DrawNode,
    minimumSize: Size,
    previousSurface: RasterSurface?,
    damage: PresentationDamage?
  ) -> RasterSurface {
    let extent = maximumExtent(for: draw, clip: nil)
    let surfaceSize = Size(
      width: max(extent.x, max(0, minimumSize.width)),
      height: max(extent.y, max(0, minimumSize.height))
    )
    guard surfaceSize.width > 0, surfaceSize.height > 0 else {
      return RasterSurface()
    }

    let dirtyRows: Set<Int>?
    var cells: [[RasterCell]]
    var imageAttachments: [RasterImageAttachment]

    if let previousSurface, let damage,
      previousSurface.size == surfaceSize,
      !damage.dirtyRows.isEmpty
    {
      cells = previousSurface.cells
      imageAttachments = []
      dirtyRows = damage.dirtyRows
      let emptyRow = Array(repeating: RasterCell.empty, count: surfaceSize.width)
      for row in damage.dirtyRows where row >= 0 && row < cells.count {
        cells[row] = emptyRow
      }
    } else {
      cells = Array(
        repeating: Array(repeating: RasterCell.empty, count: surfaceSize.width),
        count: surfaceSize.height
      )
      imageAttachments = []
      dirtyRows = nil
    }

    paint(
      node: draw,
      cells: &cells,
      imageAttachments: &imageAttachments,
      clip: nil,
      dirtyRows: dirtyRows
    )

    return RasterSurface(
      size: surfaceSize,
      cells: cells,
      imageAttachments: imageAttachments
    )
  }
}

extension Rasterizer {
  private func maximumExtent(
    for node: DrawNode,
    clip: Rect?
  ) -> (x: Int, y: Int) {
    struct Frame {
      let node: DrawNode
      let clip: Rect?
    }

    var maxX = 0
    var maxY = 0
    var hasVisibleExtent = false
    var stack: [Frame] = [Frame(node: node, clip: clip)]

    while let frame = stack.popLast() {
      let effectiveClip = intersect(frame.clip, frame.node.clipBounds)
      let visibleBounds: Rect
      if let effectiveClip {
        guard let clippedBounds = intersect(frame.node.bounds, effectiveClip) else {
          continue
        }
        visibleBounds = clippedBounds
      } else {
        visibleBounds = frame.node.bounds
      }

      let nodeMaxX = visibleBounds.origin.x + visibleBounds.size.width
      let nodeMaxY = visibleBounds.origin.y + visibleBounds.size.height
      if hasVisibleExtent {
        maxX = max(maxX, nodeMaxX)
        maxY = max(maxY, nodeMaxY)
      } else {
        maxX = nodeMaxX
        maxY = nodeMaxY
        hasVisibleExtent = true
      }

      for child in frame.node.children.reversed() {
        stack.append(Frame(node: child, clip: effectiveClip))
      }
    }

    return (x: maxX, y: maxY)
  }

  private func paint(
    node: DrawNode,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: Rect?,
    dirtyRows: Set<Int>?
  ) {
    // Two frame kinds.  A `.visit` frame paints the node's `commands`
    // (pre-child commands) and then pushes its children plus, if the
    // node has any `postCommands`, a `.post` frame on top of those
    // children.  Because the stack is LIFO, the children pop first and
    // the `.post` frame pops only after every descendant has been
    // painted — giving us the "paint after children" semantics that
    // inset-placement borders need to correctly overdraw the outermost
    // cells of their subtree.
    enum Frame {
      case visit(node: DrawNode, clip: Rect?)
      case post(
        commands: [DrawCommand],
        environment: StyleEnvironmentSnapshot,
        clip: Rect?)
    }

    var stack: [Frame] = [.visit(node: node, clip: clip)]

    while let frame = stack.popLast() {
      switch frame {
      case .post(let commands, let environment, let clip):
        paint(
          commands: commands,
          environment: environment,
          cells: &cells,
          imageAttachments: &imageAttachments,
          clip: clip,
          dirtyRows: dirtyRows
        )
      case .visit(let node, let frameClip):
        let effectiveClip = intersect(frameClip, node.clipBounds)
        let visibleBounds: Rect
        if let effectiveClip {
          guard let clipped = intersect(node.bounds, effectiveClip) else {
            continue
          }
          visibleBounds = clipped
        } else {
          visibleBounds = node.bounds
        }

        if let dirtyRows {
          let nodeTop = max(0, visibleBounds.origin.y)
          let nodeBottom = nodeTop + max(0, visibleBounds.size.height)
          if nodeBottom > nodeTop {
            var intersects = false
            for row in dirtyRows {
              if row >= nodeTop, row < nodeBottom {
                intersects = true
                break
              }
            }
            if !intersects {
              continue
            }
          }
        }

        paint(
          commands: node.commands,
          environment: node.environmentSnapshot.style,
          cells: &cells,
          imageAttachments: &imageAttachments,
          clip: effectiveClip,
          dirtyRows: dirtyRows
        )

        // Schedule post-children commands first so they pop LAST
        // (after all descendants of this node have been processed),
        // then push children in reverse so they pop in declared
        // order.  Skip the post frame entirely when there are no
        // post commands to keep the common path allocation-free.
        if !node.postCommands.isEmpty {
          stack.append(
            .post(
              commands: node.postCommands,
              environment: node.environmentSnapshot.style,
              clip: effectiveClip
            )
          )
        }
        for child in node.children.reversed() {
          stack.append(.visit(node: child, clip: effectiveClip))
        }
      }
    }
  }

  private func paint(
    commands: [DrawCommand],
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: Rect?,
    dirtyRows: Set<Int>? = nil
  ) {
    struct Frame {
      let command: DrawCommand
      let clip: Rect?
    }

    var stack: [Frame] = []
    stack.reserveCapacity(commands.count)
    for command in commands.reversed() {
      stack.append(Frame(command: command, clip: clip))
    }

    while let frame = stack.popLast() {
      switch frame.command {
      case .group(_, let children):
        for child in children.reversed() {
          stack.append(Frame(command: child, clip: frame.clip))
        }
      case .clip(let bounds, let child):
        stack.append(Frame(command: child, clip: bounds))
      case .text(
        let bounds,
        let content,
        let style,
        let lineLimit,
        let truncationMode,
        let wrappingStrategy
      ):
        guard bounds.size.height > 0, bounds.size.width > 0 else {
          continue
        }

        let layout = layoutText(
          for: content,
          width: bounds.size.width,
          lineLimit: lineLimit,
          truncationMode: truncationMode,
          wrappingStrategy: wrappingStrategy
        )

        for (lineIndex, line) in layout.lines.prefix(bounds.size.height).enumerated() {
          var x = bounds.origin.x
          for cluster in line.clusters {
            guard x + cluster.cellWidth <= bounds.origin.x + bounds.size.width else {
              break
            }

            let resolvedStyle = resolveTextStyle(
              style,
              environment: environment,
              bounds: bounds,
              sampleX: x,
              sampleY: bounds.origin.y + lineIndex,
              width: cluster.cellWidth,
              currentCellBackground: currentCellBackground(
                cells: cells,
                x: x,
                y: bounds.origin.y + lineIndex
              )
            )

            write(
              cluster.character,
              width: cluster.cellWidth,
              style: resolvedStyle.isDefault ? nil : resolvedStyle,
              atX: x,
              y: bounds.origin.y + lineIndex,
              cells: &cells,
              clip: frame.clip
            )
            x += cluster.cellWidth
            if x >= bounds.origin.x + bounds.size.width {
              break
            }
          }
        }
      case .preformattedText(
        let bounds,
        let lines,
        let style
      ):
        guard bounds.size.height > 0, bounds.size.width > 0 else {
          continue
        }

        for (lineIndex, line) in lines.prefix(bounds.size.height).enumerated() {
          let clusters = layoutText(for: line, width: nil).lines.first?.clusters ?? []
          var x = bounds.origin.x
          for cluster in clusters {
            guard x + cluster.cellWidth <= bounds.origin.x + bounds.size.width else {
              break
            }

            let resolvedStyle = resolveTextStyle(
              style,
              environment: environment,
              bounds: bounds,
              sampleX: x,
              sampleY: bounds.origin.y + lineIndex,
              width: cluster.cellWidth,
              currentCellBackground: currentCellBackground(
                cells: cells,
                x: x,
                y: bounds.origin.y + lineIndex
              )
            )

            write(
              cluster.character,
              width: cluster.cellWidth,
              style: resolvedStyle.isDefault ? nil : resolvedStyle,
              atX: x,
              y: bounds.origin.y + lineIndex,
              cells: &cells,
              clip: frame.clip
            )
            x += cluster.cellWidth
          }
        }
      case .richText(
        let bounds,
        let payload,
        let lineLimit,
        let truncationMode,
        let wrappingStrategy
      ):
        guard bounds.size.height > 0, bounds.size.width > 0 else {
          continue
        }

        let layout = layoutRichText(
          for: payload,
          options: .init(
            width: bounds.size.width,
            lineLimit: lineLimit,
            truncationMode: truncationMode,
            wrappingStrategy: wrappingStrategy
          )
        )

        for (lineIndex, line) in layout.lines.prefix(bounds.size.height).enumerated() {
          var x = bounds.origin.x
          for cluster in line.clusters {
            guard x + cluster.cellWidth <= bounds.origin.x + bounds.size.width else {
              break
            }

            let run = cluster.runIndex.flatMap { runIndex in
              payload.runs.indices.contains(runIndex) ? payload.runs[runIndex] : nil
            }
            let resolvedStyle = resolveTextStyle(
              run?.style ?? .init(),
              environment: environment,
              bounds: bounds,
              sampleX: x,
              sampleY: bounds.origin.y + lineIndex,
              width: cluster.cellWidth,
              currentCellBackground: currentCellBackground(
                cells: cells,
                x: x,
                y: bounds.origin.y + lineIndex
              )
            )

            write(
              cluster.character,
              width: cluster.cellWidth,
              style: resolvedStyle.isDefault ? nil : resolvedStyle,
              hyperlink: run?.destination?.rawValue,
              atX: x,
              y: bounds.origin.y + lineIndex,
              cells: &cells,
              clip: frame.clip
            )
            x += cluster.cellWidth
            if x >= bounds.origin.x + bounds.size.width {
              break
            }
          }
        }
      case .image(let bounds, let identity, let payload):
        imageAttachments.append(
          RasterImageAttachment(
            identity: identity,
            bounds: bounds,
            source: payload.source,
            resolvedReference: payload.resolvedAsset?.reference,
            pixelSize: payload.resolvedAsset?.pixelSize,
            isResizable: payload.isResizable,
            scalingMode: payload.scalingMode
          )
        )
      case .fill(let bounds, let geometry, let insetAmount, let style, let mode):
        paintFill(
          in: bounds,
          geometry: geometry,
          insetAmount: insetAmount,
          style: style,
          mode: mode,
          environment: environment,
          cells: &cells,
          clip: frame.clip
        )
      case .stroke(
        let bounds, let geometry, let insetAmount, let style, let strokeStyle, let strokeBorder,
        let backgroundStyle):
        paintStroke(
          in: bounds,
          geometry: geometry,
          insetAmount: insetAmount,
          style: style,
          strokeStyle: strokeStyle,
          strokeBorder: strokeBorder,
          backgroundStyle: backgroundStyle,
          environment: environment,
          cells: &cells,
          clip: frame.clip
        )
      case .rule(let bounds, let style, let strokeStyle, let stackAxis):
        paintRule(
          in: bounds,
          style: style,
          strokeStyle: strokeStyle,
          stackAxis: stackAxis,
          environment: environment,
          cells: &cells,
          clip: frame.clip
        )
      case .border(let bounds, let set, let foreground, let background, let sides):
        drawLayoutBorder(
          in: bounds,
          set: set,
          foreground: foreground,
          background: background,
          sides: sides,
          environment: environment,
          cells: &cells,
          clip: frame.clip
        )
      }
    }
  }

  private func paintFill(
    in bounds: Rect,
    geometry: ShapeGeometry,
    insetAmount: Int,
    style: AnyShapeStyle,
    mode: ShapeFillMode,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let shapeBounds = insetBounds(bounds, by: max(0, insetAmount), strokeBorder: true)
    guard shapeBounds.size.width > 0, shapeBounds.size.height > 0 else {
      return
    }
    let colorMode = resolvedColorMode(
      from: style,
      environment: environment
    )

    // A nil constant color means the fill is fully transparent — skip painting.
    if case .constant(nil) = colorMode {
      return
    }

    // Detect whether this fill carries alpha for the tint path.
    let constantColor: Color?
    let isTranslucent: Bool
    switch colorMode {
    case .constant(let color):
      constantColor = color
      isTranslucent = (color?.alpha ?? 0) < 1
    case .sampled:
      constantColor = nil
      // Sampled (gradient) fills may have per-stop alpha.
      isTranslucent = false
    }

    for y in shapeBounds.origin.y..<(shapeBounds.origin.y + shapeBounds.size.height) {
      for x in shapeBounds.origin.x..<(shapeBounds.origin.x + shapeBounds.size.width) {
        guard
          shapeContains(
            pointX: x,
            pointY: y,
            in: shapeBounds,
            geometry: geometry,
            fillMode: mode
          )
        else {
          continue
        }

        if isTranslucent {
          // Translucent constant fill: tint existing cell in-place.
          if let color = constantColor, color.alpha > 0 {
            tintCell(atX: x, y: y, with: color, cells: &cells, clip: clip)
          }
        } else if let constantColor {
          // Opaque constant fill: overwrite cell.
          let resolvedStyle = ResolvedTextStyle(backgroundColor: constantColor)
          write(
            " ",
            style: resolvedStyle.isDefault ? nil : resolvedStyle,
            atX: x,
            y: y,
            cells: &cells,
            clip: clip
          )
        } else {
          // Sampled (gradient) fill: resolve per-cell.
          let fillColor = resolveColor(
            from: colorMode,
            bounds: shapeBounds,
            sampleX: x,
            sampleY: y
          )
          if let fillColor, fillColor.alpha < 1 {
            if fillColor.alpha > 0 {
              tintCell(atX: x, y: y, with: fillColor, cells: &cells, clip: clip)
            }
          } else {
            write(
              " ",
              style: resolvedBackgroundTextStyle(
                colorMode: colorMode,
                bounds: shapeBounds,
                x: x,
                y: y
              ),
              atX: x,
              y: y,
              cells: &cells,
              clip: clip
            )
          }
        }
      }
    }
  }

  private func tintCell(
    atX x: Int,
    y: Int,
    with overlay: Color,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    if let clip {
      guard
        x >= clip.origin.x,
        x < clip.origin.x + clip.size.width,
        y >= clip.origin.y,
        y < clip.origin.y + clip.size.height
      else {
        return
      }
    }
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }
    var cell = cells[y][x]
    cell.style = (cell.style ?? .init()).tinted(with: overlay)
    cells[y][x] = cell
  }

  private func paintStroke(
    in bounds: Rect,
    geometry: ShapeGeometry,
    insetAmount: Int,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool,
    backgroundStyle: BorderBackgroundStyle?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let shapeBounds = insetBounds(bounds, by: max(0, insetAmount), strokeBorder: true)
    guard shapeBounds.size.width > 0, shapeBounds.size.height > 0 else {
      return
    }
    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment
    )
    let lineWidth = max(1, strokeStyle.lineWidth)
    for inset in 0..<lineWidth {
      let insetRect = insetBounds(shapeBounds, by: inset, strokeBorder: strokeBorder)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        continue
      }

      let glyphs = borderGlyphs(
        for: geometry,
        variant: strokeStyle.lineVariant
      )

      let minX = insetRect.origin.x
      let maxX = insetRect.origin.x + insetRect.size.width - 1
      let minY = insetRect.origin.y
      let maxY = insetRect.origin.y + insetRect.size.height - 1

      for x in minX...maxX {
        writeStrokeGlyph(
          glyphs.top,
          lineVariant: strokeStyle.lineVariant,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
          fallbackBackgroundSides: [.top],
          environment: environment,
          bounds: shapeBounds,
          x: x,
          y: minY,
          cells: &cells,
          clip: clip
        )
        if maxY != minY {
          writeStrokeGlyph(
            glyphs.bottom,
            lineVariant: strokeStyle.lineVariant,
            foregroundColorMode: foregroundColorMode,
            backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
            fallbackBackgroundSides: [.bottom],
            environment: environment,
            bounds: shapeBounds,
            x: x,
            y: maxY,
            cells: &cells,
            clip: clip
          )
        }
      }

      if maxY - minY > 1 {
        for y in (minY + 1)..<maxY {
          writeStrokeGlyph(
            glyphs.left,
            lineVariant: strokeStyle.lineVariant,
            foregroundColorMode: foregroundColorMode,
            backgroundStyle: backgroundStyle?.backgroundStyle(for: .left),
            fallbackBackgroundSides: [.left],
            environment: environment,
            bounds: shapeBounds,
            x: minX,
            y: y,
            cells: &cells,
            clip: clip
          )
          if maxX != minX {
            writeStrokeGlyph(
              glyphs.right,
              lineVariant: strokeStyle.lineVariant,
              foregroundColorMode: foregroundColorMode,
              backgroundStyle: backgroundStyle?.backgroundStyle(for: .right),
              fallbackBackgroundSides: [.right],
              environment: environment,
              bounds: shapeBounds,
              x: maxX,
              y: y,
              cells: &cells,
              clip: clip
            )
          }
        }
      }

      writeStrokeGlyph(
        glyphs.topLeading,
        lineVariant: strokeStyle.lineVariant,
        foregroundColorMode: foregroundColorMode,
        backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
        fallbackBackgroundSides: [.top, .left],
        environment: environment,
        bounds: shapeBounds,
        x: minX,
        y: minY,
        cells: &cells,
        clip: clip
      )
      if maxX != minX {
        writeStrokeGlyph(
          glyphs.topTrailing,
          lineVariant: strokeStyle.lineVariant,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
          fallbackBackgroundSides: [.top, .right],
          environment: environment,
          bounds: shapeBounds,
          x: maxX,
          y: minY,
          cells: &cells,
          clip: clip
        )
      }
      if maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomLeading,
          lineVariant: strokeStyle.lineVariant,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          fallbackBackgroundSides: [.bottom, .left],
          environment: environment,
          bounds: shapeBounds,
          x: minX,
          y: maxY,
          cells: &cells,
          clip: clip
        )
      }
      if maxX != minX, maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomTrailing,
          lineVariant: strokeStyle.lineVariant,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          fallbackBackgroundSides: [.bottom, .right],
          environment: environment,
          bounds: shapeBounds,
          x: maxX,
          y: maxY,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  /// Paints a layout-reserved border into the cells that
  /// ``LayoutBehavior/border(_:foreground:background:blend:blendPhase:sides:)``
  /// reserved during the layout pass.
  ///
  /// The entry point for the new layout-aware `.border(...)` view
  /// modifier.  For `.outset` and `.decorative` border sets the frame
  /// grew by the per-side display widths and the glyphs are written
  /// into those reserved outer cells without ever touching the child's
  /// interior.  For `.inset` sets no frame insets were reserved and
  /// the glyphs overdraw the view's outermost rows / cols.
  private func drawLayoutBorder(
    in outer: Rect,
    set: BorderSet,
    foreground: BorderEdgeStyle?,
    background: BorderBackgroundStyle?,
    sides: Edge.Set,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard outer.size.width > 0, outer.size.height > 0 else {
      return
    }

    // Resolved side widths, masked by the requested `sides` set.
    // These match the layout insets reserved during the layout pass
    // by `LayoutEngine.borderLayoutInsets(set:sides:)`.
    let topWidth = sides.contains(.top) ? set.topDisplayWidth : 0
    let bottomWidth = sides.contains(.bottom) ? set.bottomDisplayWidth : 0
    let leftWidth = sides.contains(.leading) ? set.leftDisplayWidth : 0
    let rightWidth = sides.contains(.trailing) ? set.rightDisplayWidth : 0

    guard topWidth > 0 || bottomWidth > 0 || leftWidth > 0 || rightWidth > 0 else {
      return
    }

    // Pre-resolve per-side foreground colors so we don't re-run the
    // shape-style resolver once per cell.  A nil per-side color falls
    // back to the theme foreground at draw time.
    let topForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .top),
      environment: environment,
      bounds: outer
    )
    let bottomForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .bottom),
      environment: environment,
      bounds: outer
    )
    let leftForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .left),
      environment: environment,
      bounds: outer
    )
    let rightForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .right),
      environment: environment,
      bounds: outer
    )

    let topBackground = resolvedBorderSideColor(
      background?.backgroundStyle(for: .top),
      environment: environment,
      bounds: outer
    )
    let bottomBackground = resolvedBorderSideColor(
      background?.backgroundStyle(for: .bottom),
      environment: environment,
      bounds: outer
    )
    let leftBackground = resolvedBorderSideColor(
      background?.backgroundStyle(for: .left),
      environment: environment,
      bounds: outer
    )
    let rightBackground = resolvedBorderSideColor(
      background?.backgroundStyle(for: .right),
      environment: environment,
      bounds: outer
    )

    // For `.inset` placements the border draws into the view's
    // outermost rows and columns (so the `inner` region equals the
    // outer minus zero — the border overdraws the outer frame).  For
    // `.outset` and `.decorative` placements the outer frame already
    // grew by the per-side display widths, so the top/bottom/left/right
    // sides lie entirely within the reserved inset and the content
    // sits in the interior rectangle `[leftWidth..width-rightWidth,
    // topWidth..height-bottomWidth]`.

    // Top edge cells: the non-corner region is
    // [outer.origin.x + leftWidth, outer.origin.x + width - rightWidth).
    // The glyph index starts at 0 at the leftmost non-corner cell and
    // cycles through the border set's top edge string for dashed
    // patterns.
    if topWidth > 0 {
      let y = outer.origin.y
      let startX = outer.origin.x + leftWidth
      let endX = outer.origin.x + outer.size.width - rightWidth
      var x = startX
      var glyphIndex = 0
      while x < endX {
        guard let character = set.topGlyph(at: glyphIndex) else {
          break
        }
        let glyphWidth = max(1, cellWidth(of: character))
        guard x + glyphWidth <= endX else {
          break
        }
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: topForeground ?? environment.theme.foreground,
          background: topBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip
        )
        x += glyphWidth
        glyphIndex += 1
      }
    }

    // Bottom edge cells: draw along y = outer bottom - 1.
    if bottomWidth > 0 {
      let y = outer.origin.y + outer.size.height - 1
      let startX = outer.origin.x + leftWidth
      let endX = outer.origin.x + outer.size.width - rightWidth
      var x = startX
      var glyphIndex = 0
      while x < endX {
        guard let character = set.bottomGlyph(at: glyphIndex) else {
          break
        }
        let glyphWidth = max(1, cellWidth(of: character))
        guard x + glyphWidth <= endX else {
          break
        }
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: bottomForeground ?? environment.theme.foreground,
          background: bottomBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip
        )
        x += glyphWidth
        glyphIndex += 1
      }
    }

    // Left edge cells: draw along x = outer.origin.x, between the top
    // and bottom edges (inclusive if those edges are not drawn).
    if leftWidth > 0 {
      let x = outer.origin.x
      let topExclusive = topWidth > 0 ? outer.origin.y + topWidth : outer.origin.y
      let bottomExclusive =
        bottomWidth > 0
        ? outer.origin.y + outer.size.height - bottomWidth
        : outer.origin.y + outer.size.height
      var y = topExclusive
      var glyphIndex = 0
      while y < bottomExclusive {
        guard let character = set.leftGlyph(at: glyphIndex) else {
          break
        }
        writeBorderGlyph(
          character,
          width: leftWidth,
          foreground: leftForeground ?? environment.theme.foreground,
          background: leftBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip
        )
        y += 1
        glyphIndex += 1
      }
    }

    // Right edge cells: draw along x = outer right - rightWidth.
    if rightWidth > 0 {
      let x = outer.origin.x + outer.size.width - rightWidth
      let topExclusive = topWidth > 0 ? outer.origin.y + topWidth : outer.origin.y
      let bottomExclusive =
        bottomWidth > 0
        ? outer.origin.y + outer.size.height - bottomWidth
        : outer.origin.y + outer.size.height
      var y = topExclusive
      var glyphIndex = 0
      while y < bottomExclusive {
        guard let character = set.rightGlyph(at: glyphIndex) else {
          break
        }
        writeBorderGlyph(
          character,
          width: rightWidth,
          foreground: rightForeground ?? environment.theme.foreground,
          background: rightBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip
        )
        y += 1
        glyphIndex += 1
      }
    }

    // Corner glyphs.  Lipgloss semantics: corners inherit the adjacent
    // horizontal edge's color (top for top corners, bottom for bottom
    // corners).
    if topWidth > 0 && leftWidth > 0 {
      writeBorderGlyphs(
        set.topLeading,
        atX: outer.origin.x,
        y: outer.origin.y,
        foreground: topForeground ?? environment.theme.foreground,
        background: topBackground,
        cells: &cells,
        clip: clip
      )
    }
    if topWidth > 0 && rightWidth > 0 {
      writeBorderGlyphs(
        set.topTrailing,
        atX: outer.origin.x + outer.size.width - rightWidth,
        y: outer.origin.y,
        foreground: topForeground ?? environment.theme.foreground,
        background: topBackground,
        cells: &cells,
        clip: clip
      )
    }
    if bottomWidth > 0 && leftWidth > 0 {
      writeBorderGlyphs(
        set.bottomLeading,
        atX: outer.origin.x,
        y: outer.origin.y + outer.size.height - 1,
        foreground: bottomForeground ?? environment.theme.foreground,
        background: bottomBackground,
        cells: &cells,
        clip: clip
      )
    }
    if bottomWidth > 0 && rightWidth > 0 {
      writeBorderGlyphs(
        set.bottomTrailing,
        atX: outer.origin.x + outer.size.width - rightWidth,
        y: outer.origin.y + outer.size.height - 1,
        foreground: bottomForeground ?? environment.theme.foreground,
        background: bottomBackground,
        cells: &cells,
        clip: clip
      )
    }

  }

  /// Eagerly resolves a border side's foreground/background style into a
  /// constant color.  Returns nil for gradient fills (which are not
  /// supported on borders in M2.B) or for nil styles; callers fall back
  /// to the theme defaults in that case.
  private func resolvedBorderSideColor(
    _ style: AnyShapeStyle?,
    environment: StyleEnvironmentSnapshot,
    bounds: Rect
  ) -> Color? {
    guard let style else {
      return nil
    }
    return resolveColor(
      from: style,
      environment: environment,
      bounds: bounds,
      sampleX: bounds.origin.x,
      sampleY: bounds.origin.y
    )
  }

  /// Writes a single border glyph at the given cell coordinates,
  /// applying the resolved foreground and optional background color.
  private func writeBorderGlyph(
    _ character: Character,
    width: Int,
    foreground: Color?,
    background: Color?,
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    var resolved = ResolvedTextStyle()
    resolved.foregroundColor = foreground
    resolved.backgroundColor = background
    write(
      character,
      width: max(1, width),
      style: resolved.isDefault ? nil : resolved,
      atX: x,
      y: y,
      cells: &cells,
      clip: clip
    )
  }

  /// Writes a multi-character glyph string (used for corners, which are
  /// stored as strings so they can be empty or multi-rune).  Advances
  /// by each glyph's display width.
  private func writeBorderGlyphs(
    _ text: String,
    atX x: Int,
    y: Int,
    foreground: Color?,
    background: Color?,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard !text.isEmpty else {
      return
    }
    var cursor = x
    for character in text {
      let glyphWidth = max(1, cellWidth(of: character))
      writeBorderGlyph(
        character,
        width: glyphWidth,
        foreground: foreground,
        background: background,
        atX: cursor,
        y: y,
        cells: &cells,
        clip: clip
      )
      cursor += glyphWidth
    }
  }

  private func paintRule(
    in bounds: Rect,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    stackAxis: Axis?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment
    )
    let glyphs = borderGlyphs(for: .rectangle, variant: strokeStyle.lineVariant)
    let drawsHorizontal =
      switch stackAxis {
      case .vertical?:
        true
      case .horizontal?:
        false
      case nil:
        bounds.size.width >= bounds.size.height
      }
    if drawsHorizontal {
      let y = bounds.origin.y + (bounds.size.height / 2)
      for x in bounds.origin.x..<(bounds.origin.x + bounds.size.width) {
        writeStrokeGlyph(
          glyphs.horizontal,
          lineVariant: strokeStyle.lineVariant,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: nil,
          fallbackBackgroundSides: [],
          environment: environment,
          bounds: bounds,
          x: x,
          y: y,
          cells: &cells,
          clip: clip
        )
      }
    } else {
      let x = bounds.origin.x + (bounds.size.width / 2)
      for y in bounds.origin.y..<(bounds.origin.y + bounds.size.height) {
        writeStrokeGlyph(
          glyphs.vertical,
          lineVariant: strokeStyle.lineVariant,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: nil,
          fallbackBackgroundSides: [],
          environment: environment,
          bounds: bounds,
          x: x,
          y: y,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  private func writeStrokeGlyph(
    _ character: Character,
    lineVariant: LineVariant,
    foregroundColorMode: ResolvedShapeColorMode,
    backgroundStyle: AnyShapeStyle?,
    fallbackBackgroundSides: [BorderSide],
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
    x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    let resolvedStyle = ResolvedTextStyle(
      foregroundColor: resolveColor(
        from: foregroundColorMode,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      ),
      backgroundColor: resolvedStrokeBackgroundColor(
        lineVariant: lineVariant,
        explicitBackgroundStyle: backgroundStyle,
        fallbackSides: fallbackBackgroundSides,
        environment: environment,
        bounds: bounds,
        x: x,
        y: y,
        cells: cells
      )
    )
    write(
      character,
      style: resolvedStyle.isDefault ? nil : resolvedStyle,
      atX: x,
      y: y,
      cells: &cells,
      clip: clip
    )
  }

  private func resolvedStrokeBackgroundColor(
    lineVariant: LineVariant,
    explicitBackgroundStyle: AnyShapeStyle?,
    fallbackSides: [BorderSide],
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
    x: Int,
    y: Int,
    cells: [[RasterCell]]
  ) -> Color? {
    if let explicitBackgroundStyle {
      return resolveColor(
        from: explicitBackgroundStyle,
        environment: environment,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      )
    }

    if lineVariant == .presentationChrome {
      for side in fallbackSides {
        if let inferred = sampledBackgroundColor(
          inside: side,
          fromX: x,
          y: y,
          cells: cells
        ) {
          return inferred
        }
      }
    }

    for side in fallbackSides {
      if let inferred = sampledBackgroundColor(
        outside: side,
        fromX: x,
        y: y,
        cells: cells
      ) {
        return inferred
      }
    }

    return nil
  }

  private func shapeContains(
    pointX x: Int,
    pointY y: Int,
    in bounds: Rect,
    geometry: ShapeGeometry,
    fillMode: ShapeFillMode = .full
  ) -> Bool {
    let targetBounds: Rect
    switch fillMode {
    case .full:
      targetBounds = bounds
    case .interior(let strokeWidth):
      let insetRect = insetBounds(bounds, by: strokeWidth, strokeBorder: true)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        return false
      }
      targetBounds = insetRect
    }

    switch geometry {
    case .rectangle, .circle, .ellipse, .capsule:
      // Rectangle is a trivial bounding-box test. `.circle`, `.ellipse`,
      // and `.capsule` are rendered via the Braille subpixel path and
      // never actually reach `shapeContains` for their own hit-testing —
      // they dispatch earlier in `paintFill`/`paintStroke`. We still
      // return the bounding-box test here so the switch is exhaustive
      // and any future cell-level sampling falls back gracefully.
      return x >= targetBounds.origin.x
        && x < targetBounds.origin.x + targetBounds.size.width
        && y >= targetBounds.origin.y
        && y < targetBounds.origin.y + targetBounds.size.height
    case .roundedRectangle(let cornerRadius):
      if case .interior = fillMode {
        return x >= targetBounds.origin.x
          && x < targetBounds.origin.x + targetBounds.size.width
          && y >= targetBounds.origin.y
          && y < targetBounds.origin.y + targetBounds.size.height
      }
      guard targetBounds.origin.x <= x,
        x < targetBounds.origin.x + targetBounds.size.width,
        targetBounds.origin.y <= y,
        y < targetBounds.origin.y + targetBounds.size.height
      else {
        return false
      }
      guard cornerRadius > 0, targetBounds.size.width > 1, targetBounds.size.height > 1 else {
        return true
      }
      let minX = targetBounds.origin.x
      let maxX = targetBounds.origin.x + targetBounds.size.width - 1
      let minY = targetBounds.origin.y
      let maxY = targetBounds.origin.y + targetBounds.size.height - 1
      let isCorner =
        (x == minX || x == maxX) && (y == minY || y == maxY)
      return !isCorner
    }
  }

  private func insetBounds(
    _ bounds: Rect,
    by inset: Int,
    strokeBorder _: Bool
  ) -> Rect {
    Rect(
      origin: Point(
        x: bounds.origin.x + inset,
        y: bounds.origin.y + inset
      ),
      size: Size(
        width: max(0, bounds.size.width - (inset * 2)),
        height: max(0, bounds.size.height - (inset * 2))
      )
    )
  }

  /// Returns the background color currently on the raster surface at
  /// the given cell coordinates, or nil if the cell is unstyled or
  /// out of bounds.  Used by ``resolveTextStyle`` to bake fractional
  /// opacity against the actual underlying background (gap item 3).
  private func currentCellBackground(
    cells: [[RasterCell]],
    x: Int,
    y: Int
  ) -> Color? {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return nil
    }
    return cells[y][x].style?.backgroundColor
  }

  private func resolveTextStyle(
    _ style: TextStyle,
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
    sampleX: Int,
    sampleY: Int,
    width: Int,
    currentCellBackground: Color? = nil
  ) -> ResolvedTextStyle {
    var foregroundColor = resolveColor(
      from: style.foregroundStyle ?? environment.foregroundStyle ?? .semantic(.foreground),
      environment: environment,
      bounds: bounds,
      sampleX: sampleX + max(0, width - 1) / 2,
      sampleY: sampleY
    )
    let backgroundColor = style.backgroundStyle.flatMap {
      resolveColor(
        from: $0,
        environment: environment,
        bounds: bounds,
        sampleX: sampleX + max(0, width - 1) / 2,
        sampleY: sampleY
      )
    }

    // Bake fractional opacity into the foreground color so animations and
    // `.opacity()` modifiers produce continuously different rendered
    // colors.  Without this, the presentation layer only sees the binary
    // SGR "faint" attribute (`TerminalPresentation.swift`), which gives
    // a single visible "dimmed" step regardless of progress.
    //
    // Blend target priority:
    // 1. Explicit backgroundColor if set — overrides everything.
    // 2. currentCellBackground — whatever is on the raster surface
    //    at this cell right now (typically the background of whatever
    //    container was drawn first at this position).
    // 3. Theme background — ultimate fallback when nothing has been
    //    drawn at this cell yet.
    //
    // The per-cell path closes a gap where fading text rendered over
    // an opaque colored container silently blended toward the theme
    // background instead of the actual background beneath the cell.
    let opacity = style.opacity
    let bakeOpacityIntoForeground = opacity < 1 && opacity >= 0
    if bakeOpacityIntoForeground, let fg = foregroundColor {
      let blendTarget =
        backgroundColor
        ?? currentCellBackground
        ?? environment.theme.background
      foregroundColor = fg.mixed(with: blendTarget, amount: 1 - opacity)
    }

    return ResolvedTextStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      emphasis: style.emphasis,
      underlineStyle: style.underlineStyle,
      strikethroughStyle: style.strikethroughStyle,
      // Reset opacity to 1 after baking so presentation doesn't also
      // emit the SGR "faint" attribute on top of the blended color.
      opacity: bakeOpacityIntoForeground ? 1.0 : opacity
    )
  }

  private func resolveColor(
    from style: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
    sampleX: Int,
    sampleY: Int,
    depth: Int = 0
  ) -> Color? {
    resolveColor(
      from: resolvedColorMode(
        from: style,
        environment: environment,
        depth: depth
      ),
      bounds: bounds,
      sampleX: sampleX,
      sampleY: sampleY
    )
  }

  private func resolvedColorMode(
    from style: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    depth: Int = 0
  ) -> ResolvedShapeColorMode {
    guard depth < 8 else {
      return .constant(nil)
    }

    switch style {
    case .color(let color):
      return .constant(color)
    case .linearGradient(let gradient):
      return .sampled(gradient)
    case .terminalChrome(let chromeStyle):
      return resolvedColorMode(
        from: environment.theme.resolvedStyle(
          for: chromeStyle,
          appearance: environment.appearance
        ),
        environment: environment,
        depth: depth + 1
      )
    case .semantic(let role):
      let candidate = semanticStyleCandidate(
        for: role,
        environment: environment
      )
      let fallback = semanticStyleFallback(
        for: role,
        environment: environment
      )
      let resolvedStyle = candidate == style ? fallback : candidate
      guard resolvedStyle != style else {
        return .constant(nil)
      }
      return resolvedColorMode(
        from: resolvedStyle,
        environment: environment,
        depth: depth + 1
      )
    case .opacity(let inner, let amount):
      guard amount > 0 else {
        return .constant(nil)
      }
      let innerMode = resolvedColorMode(
        from: inner,
        environment: environment,
        depth: depth + 1
      )
      switch innerMode {
      case .constant(let color):
        guard let color else { return .constant(nil) }
        return .constant(color.opacity(amount))
      case .sampled(let gradient):
        let faded = LinearGradient(
          gradient: Gradient(
            stops: gradient.gradient.stops.map {
              .init(color: $0.color.opacity(amount), location: $0.location)
            }),
          startPoint: gradient.startPoint,
          endPoint: gradient.endPoint
        )
        return .sampled(faded)
      }
    }
  }

  private func resolveColor(
    from mode: ResolvedShapeColorMode,
    bounds: Rect,
    sampleX: Int,
    sampleY: Int
  ) -> Color? {
    switch mode {
    case .constant(let color):
      return color
    case .sampled(let gradient):
      return sample(
        gradient,
        in: bounds,
        x: sampleX,
        y: sampleY
      )
    }
  }

  private func resolvedBackgroundTextStyle(
    colorMode: ResolvedShapeColorMode,
    bounds: Rect,
    x: Int,
    y: Int
  ) -> ResolvedTextStyle? {
    let resolvedStyle = ResolvedTextStyle(
      backgroundColor: resolveColor(
        from: colorMode,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      )
    )
    return resolvedStyle.isDefault ? nil : resolvedStyle
  }

  private func semanticStyleCandidate(
    for role: SemanticStyleRole,
    environment: StyleEnvironmentSnapshot
  ) -> AnyShapeStyle {
    environment.resolvedStyle(for: role)
  }

  private func semanticStyleFallback(
    for role: SemanticStyleRole,
    environment: StyleEnvironmentSnapshot
  ) -> AnyShapeStyle {
    environment.themeStyle(for: role)
  }

  private func sample(
    _ gradient: LinearGradient,
    in bounds: Rect,
    x: Int,
    y: Int
  ) -> Color? {
    let stops = gradient.gradient.stops
    guard let first = stops.first else {
      return nil
    }
    guard stops.count > 1, bounds.size.width > 0, bounds.size.height > 0 else {
      return first.color
    }

    let start = unitCoordinates(for: gradient.startPoint)
    let end = unitCoordinates(for: gradient.endPoint)
    let point = (
      x: Double(x - bounds.origin.x) + 0.5,
      y: Double(y - bounds.origin.y) + 0.5
    )
    let normalizedPoint = (
      x: point.x / Double(max(1, bounds.size.width)),
      y: point.y / Double(max(1, bounds.size.height))
    )

    let axis = (x: end.x - start.x, y: end.y - start.y)
    let axisLengthSquared = (axis.x * axis.x) + (axis.y * axis.y)
    let t: Double
    if axisLengthSquared == 0 {
      t = 0
    } else {
      let offset = (x: normalizedPoint.x - start.x, y: normalizedPoint.y - start.y)
      t = min(
        1,
        max(
          0,
          ((offset.x * axis.x) + (offset.y * axis.y)) / axisLengthSquared
        )
      )
    }

    if t <= first.location {
      return first.color
    }
    if let last = stops.last, t >= last.location {
      return last.color
    }

    for index in 0..<(stops.count - 1) {
      let lower = stops[index]
      let upper = stops[index + 1]
      guard t >= lower.location, t <= upper.location else {
        continue
      }

      let range = max(0.0001, upper.location - lower.location)
      let localT = (t - lower.location) / range
      return lower.color.interpolated(to: upper.color, progress: localT)
    }

    return stops.last?.color
  }

  private func unitCoordinates(
    for alignment: Alignment
  ) -> (x: Double, y: Double) {
    let x: Double =
      switch alignment.horizontal {
      case .leading:
        0
      case .center:
        0.5
      case .trailing:
        1
      default:
        0.5
      }

    let y: Double =
      switch alignment.vertical {
      case .top:
        0
      case .center:
        0.5
      case .bottom, .firstTextBaseline, .lastTextBaseline:
        1
      default:
        0.5
      }

    return (x, y)
  }

  private func intersect(
    _ lhs: Rect?,
    _ rhs: Rect?
  ) -> Rect? {
    switch (lhs, rhs) {
    case (nil, nil):
      return nil
    case (let rect?, nil), (nil, let rect?):
      return rect
    case (let lhsRect?, let rhsRect?):
      return intersect(lhsRect, rhsRect)
    }
  }

  private func intersect(
    _ lhs: Rect,
    _ rhs: Rect
  ) -> Rect? {
    let minX = max(lhs.origin.x, rhs.origin.x)
    let minY = max(lhs.origin.y, rhs.origin.y)
    let maxX = min(lhs.origin.x + lhs.size.width, rhs.origin.x + rhs.size.width)
    let maxY = min(lhs.origin.y + lhs.size.height, rhs.origin.y + rhs.size.height)

    guard maxX > minX, maxY > minY else {
      return nil
    }

    return Rect(
      origin: Point(x: minX, y: minY),
      size: Size(width: maxX - minX, height: maxY - minY)
    )
  }

  private func borderGlyphs(
    for geometry: ShapeGeometry,
    variant: LineVariant
  ) -> BorderGlyphSet {
    switch variant {
    case .ascii:
      return .ascii
    case .single:
      switch geometry {
      case .roundedRectangle(let cornerRadius) where cornerRadius > 0:
        return .rounded
      default:
        return .singleLine
      }
    case .rounded:
      return .rounded
    case .double:
      return .doubleLine
    case .heavy:
      return .heavy
    case .block:
      return .block
    case .outerHalfBlock:
      return .outerHalfBlock
    case .innerHalfBlock:
      return .innerHalfBlock
    case .presentationChrome:
      return .presentationChrome
    case .hidden:
      return .hidden
    case .markdown:
      return .markdown
    case .automatic:
      switch geometry {
      case .roundedRectangle(let cornerRadius) where cornerRadius > 0:
        return .rounded
      default:
        return .singleLine
      }
    }
  }

  private struct BorderGlyphSet {
    let top: Character
    let bottom: Character
    let left: Character
    let right: Character
    let topLeading: Character
    let topTrailing: Character
    let bottomLeading: Character
    let bottomTrailing: Character

    var horizontal: Character { top }
    var vertical: Character { left }

    static let ascii = Self(
      top: "-",
      bottom: "-",
      left: "|",
      right: "|",
      topLeading: "+",
      topTrailing: "+",
      bottomLeading: "+",
      bottomTrailing: "+"
    )

    static let singleLine = Self(
      top: "─",
      bottom: "─",
      left: "│",
      right: "│",
      topLeading: "┌",
      topTrailing: "┐",
      bottomLeading: "└",
      bottomTrailing: "┘"
    )

    static let rounded = Self(
      top: "─",
      bottom: "─",
      left: "│",
      right: "│",
      topLeading: "╭",
      topTrailing: "╮",
      bottomLeading: "╰",
      bottomTrailing: "╯"
    )

    static let doubleLine = Self(
      top: "═",
      bottom: "═",
      left: "║",
      right: "║",
      topLeading: "╔",
      topTrailing: "╗",
      bottomLeading: "╚",
      bottomTrailing: "╝"
    )

    static let heavy = Self(
      top: "━",
      bottom: "━",
      left: "┃",
      right: "┃",
      topLeading: "┏",
      topTrailing: "┓",
      bottomLeading: "┗",
      bottomTrailing: "┛"
    )

    static let block = Self(
      top: "█",
      bottom: "█",
      left: "█",
      right: "█",
      topLeading: "█",
      topTrailing: "█",
      bottomLeading: "█",
      bottomTrailing: "█"
    )

    static let outerHalfBlock = Self(
      top: "▀",
      bottom: "▄",
      left: "▌",
      right: "▐",
      topLeading: "▛",
      topTrailing: "▜",
      bottomLeading: "▙",
      bottomTrailing: "▟"
    )

    static let innerHalfBlock = Self(
      top: "▄",
      bottom: "▀",
      left: "▐",
      right: "▌",
      topLeading: "▗",
      topTrailing: "▖",
      bottomLeading: "▝",
      bottomTrailing: "▘"
    )

    static let presentationChrome = Self(
      top: "▄",
      bottom: "▀",
      left: "▐",
      right: "▌",
      topLeading: "▗",
      topTrailing: "▖",
      bottomLeading: "▝",
      bottomTrailing: "▘"
    )

    static let hidden = Self(
      top: " ",
      bottom: " ",
      left: " ",
      right: " ",
      topLeading: " ",
      topTrailing: " ",
      bottomLeading: " ",
      bottomTrailing: " "
    )

    static let markdown = Self(
      top: "-",
      bottom: "-",
      left: "|",
      right: "|",
      topLeading: "|",
      topTrailing: "|",
      bottomLeading: "|",
      bottomTrailing: "|"
    )
  }

  private func write(
    _ character: Character,
    width: Int = 1,
    style: ResolvedTextStyle? = nil,
    hyperlink: String? = nil,
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    let glyphWidth = max(1, width)
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }
    if let clip {
      guard x >= clip.origin.x,
        x + glyphWidth <= clip.origin.x + clip.size.width,
        y >= clip.origin.y,
        y < clip.origin.y + clip.size.height
      else {
        return
      }
    }

    let underlayStyle = cells[y][x].style
    let finalStyle: ResolvedTextStyle?
    switch (style, underlayStyle) {
    case (nil, nil):
      finalStyle = nil
    case (let overlayStyle?, nil):
      finalStyle = overlayStyle.isDefault ? nil : overlayStyle
    case (nil, let underlayStyle?):
      let compositedStyle = Self.emptyCompositingStyle.composited(over: underlayStyle)
      finalStyle = compositedStyle.isDefault ? nil : compositedStyle
    case (let overlayStyle?, let underlayStyle?):
      let compositedStyle = overlayStyle.composited(over: underlayStyle)
      finalStyle = compositedStyle.isDefault ? nil : compositedStyle
    }

    for offset in 0..<glyphWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      clearExistingGlyph(atX: targetX, y: y, cells: &cells)
    }

    cells[y][x] = RasterCell(
      character: character,
      spanWidth: glyphWidth,
      style: finalStyle,
      hyperlink: hyperlink
    )

    guard glyphWidth > 1 else {
      return
    }

    for offset in 1..<glyphWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      cells[y][targetX] = RasterCell(
        character: " ",
        spanWidth: 0,
        continuationLeadX: x,
        style: finalStyle,
        hyperlink: hyperlink
      )
    }
  }

  private func clearExistingGlyph(
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]]
  ) {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }

    let cell = cells[y][x]
    if let leadX = cell.continuationLeadX {
      clearLeadGlyph(atX: leadX, y: y, cells: &cells)
      return
    }

    if cell.spanWidth > 1 {
      clearLeadGlyph(atX: x, y: y, cells: &cells)
      return
    }

    cells[y][x] = .empty
  }

  private func clearLeadGlyph(
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]]
  ) {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }

    let spanWidth = max(1, cells[y][x].spanWidth)
    for offset in 0..<spanWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      cells[y][targetX] = .empty
    }
  }
}

/// Converts draw commands into a terminal cell surface.
public struct Rasterizer {
  private static let emptyCompositingStyle = ResolvedTextStyle()
  private enum ResolvedShapeColorMode {
    case constant(Color?)
    case sampled(LinearGradient)
    case sampledRadial(RadialGradient)
    case pattern(PatternFill)
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
    rasterizeCollectingVisibleIdentities(
      draw,
      minimumSize: minimumSize,
      previousSurface: previousSurface,
      damage: damage
    ).surface
  }

  /// Rasterizes ``draw`` and returns both the rendered ``RasterSurface``
  /// and the set of identities whose draw nodes had non-empty visible
  /// bounds after clipping.
  ///
  /// The identity set is the "drawn-set" the run loop uses to gate
  /// animation tick scheduling on viewport visibility: if none of the
  /// identities affected by an animation tick appear in this set, the
  /// animation is painting into a clipped subtree and scheduling another
  /// deadline burns CPU for no visible effect.
  ///
  /// Note: identities are recorded *before* the dirty-rows culling step,
  /// so the set captures "would have painted cells if drawn from
  /// scratch" rather than "actually repainted cells this frame."  The
  /// distinction matters because dirty-rows is an incremental-repaint
  /// optimization, while the visibility check we gate animations on is
  /// a geometric predicate on the placed tree.
  package func rasterizeCollectingVisibleIdentities(
    _ draw: DrawNode,
    minimumSize: Size,
    previousSurface: RasterSurface?,
    damage: PresentationDamage?
  ) -> (
    surface: RasterSurface,
    visibleIdentities: Set<Identity>,
    presentationDamage: PresentationDamage?
  ) {
    let extent = maximumExtent(for: draw, clip: nil)
    let surfaceSize = Size(
      width: max(extent.x, max(0, minimumSize.width)),
      height: max(extent.y, max(0, minimumSize.height))
    )
    guard surfaceSize.width > 0, surfaceSize.height > 0 else {
      return (RasterSurface(), [], damage)
    }

    let dirtyRows: Set<Int>?
    let damageToRefine: PresentationDamage?
    var cells: [[RasterCell]]
    var imageAttachments: [RasterImageAttachment]

    if let previousSurface, let damage,
      previousSurface.size == surfaceSize,
      !damage.dirtyRows.isEmpty
    {
      cells = previousSurface.cells
      imageAttachments = []
      dirtyRows = damage.dirtyRows
      damageToRefine = damage
      clear(cells: &cells, for: damage, surfaceWidth: surfaceSize.width)
    } else {
      cells = Array(
        repeating: Array(repeating: RasterCell.empty, count: surfaceSize.width),
        count: surfaceSize.height
      )
      imageAttachments = []
      dirtyRows = nil
      damageToRefine = nil
    }

    var visibleIdentities: Set<Identity> = []

    // Pre-compute the dirty-row range once so the per-node culling check
    // in `paint(node:...)` is O(1) instead of O(|dirtyRows|).
    let dirtyRowRange: (min: Int, max: Int)?
    if let dirtyRows, let lo = dirtyRows.min(), let hi = dirtyRows.max() {
      dirtyRowRange = (min: lo, max: hi)
    } else {
      dirtyRowRange = nil
    }

    paint(
      node: draw,
      cells: &cells,
      imageAttachments: &imageAttachments,
      clip: nil,
      dirtyRows: dirtyRows,
      dirtyRowRange: dirtyRowRange,
      visibleIdentities: &visibleIdentities
    )

    let surface = RasterSurface(
      size: surfaceSize,
      cells: cells,
      imageAttachments: imageAttachments
    )

    let refinedDamage =
      if let previousSurface, let damageToRefine {
        refinedPresentationDamage(
          from: damageToRefine,
          previousSurface: previousSurface,
          currentSurface: surface
        )
      } else {
        damage
      }

    return (
      surface,
      visibleIdentities,
      refinedDamage
    )
  }
}

extension Rasterizer {
  private func clear(
    cells: inout [[RasterCell]],
    for damage: PresentationDamage,
    surfaceWidth: Int
  ) {
    let emptyRow = Array(repeating: RasterCell.empty, count: surfaceWidth)
    for textRow in damage.textRows {
      guard textRow.row >= 0, textRow.row < cells.count else {
        continue
      }
      if textRow.columnRanges.isEmpty {
        cells[textRow.row] = emptyRow
        continue
      }
      clear(
        columns: textRow.columnRanges,
        inRow: textRow.row,
        cells: &cells
      )
    }
  }

  private func clear(
    columns ranges: [Range<Int>],
    inRow row: Int,
    cells: inout [[RasterCell]]
  ) {
    guard row >= 0, row < cells.count else {
      return
    }
    let rowWidth = cells[row].count
    for range in ranges {
      let lowerBound = max(0, range.lowerBound)
      let upperBound = min(rowWidth, max(lowerBound, range.upperBound))
      guard lowerBound < upperBound else {
        continue
      }
      for column in lowerBound..<upperBound {
        clearExistingGlyph(atX: column, y: row, cells: &cells)
      }
    }
  }

  private func refinedPresentationDamage(
    from damage: PresentationDamage,
    previousSurface: RasterSurface,
    currentSurface: RasterSurface
  ) -> PresentationDamage {
    let rowCount = max(
      max(previousSurface.cells.count, currentSurface.cells.count),
      max(previousSurface.size.height, currentSurface.size.height)
    )
    let width = max(previousSurface.size.width, currentSurface.size.width)
    let refinedRows = damage.dirtyRows
      .filter { $0 >= 0 && $0 < rowCount }
      .sorted()
      .compactMap { row -> PresentationDamage.TextRow? in
        let previousRow = row < previousSurface.cells.count ? previousSurface.cells[row] : []
        let currentRow = row < currentSurface.cells.count ? currentSurface.cells[row] : []
        let changedRanges = changedRanges(
          previousRow: previousRow,
          currentRow: currentRow,
          width: max(width, previousRow.count, currentRow.count)
        )
        guard !changedRanges.isEmpty else {
          return nil
        }
        return .init(row: row, columnRanges: changedRanges)
      }

    return PresentationDamage(
      textRows: refinedRows,
      graphicsInvalidation: damage.graphicsInvalidation,
      requiresFullTextRepaint: damage.requiresFullTextRepaint,
      requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay
    )
  }

  private func changedRanges(
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> [Range<Int>] {
    guard width > 0 else {
      return []
    }

    var changed: [Range<Int>] = []
    var index = 0
    while index < width {
      guard cell(at: index, in: previousRow) != cell(at: index, in: currentRow) else {
        index += 1
        continue
      }

      let start = index
      index += 1
      while index < width,
        cell(at: index, in: previousRow) != cell(at: index, in: currentRow)
      {
        index += 1
      }

      let normalized = normalizeChangedSpan(
        start..<index,
        previousRow: previousRow,
        currentRow: currentRow,
        width: width
      )
      if let last = changed.last,
        last.upperBound >= normalized.lowerBound
      {
        changed[changed.count - 1] = last.lowerBound..<max(last.upperBound, normalized.upperBound)
      } else {
        changed.append(normalized)
      }
    }

    return changed
  }

  private func normalizeChangedSpan(
    _ span: Range<Int>,
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> Range<Int> {
    guard !span.isEmpty else {
      return span
    }

    var start = max(0, min(span.lowerBound, width))
    var end = max(start, min(span.upperBound, width))

    while start > 0 {
      let candidate = min(
        leadIndexIfContinuation(at: start, in: currentRow),
        leadIndexIfContinuation(at: start, in: previousRow)
      )
      guard candidate < start else {
        break
      }
      start = candidate
    }

    while end < width {
      if cell(at: end, in: currentRow).isContinuation
        || cell(at: end, in: previousRow).isContinuation
      {
        end += 1
        continue
      }
      break
    }

    return start..<end
  }

  private func leadIndexIfContinuation(
    at index: Int,
    in row: [RasterCell]
  ) -> Int {
    guard cell(at: index, in: row).isContinuation else {
      return index
    }
    return max(0, min(index, cell(at: index, in: row).continuationLeadX ?? index))
  }

  private func cell(
    at index: Int,
    in row: [RasterCell]
  ) -> RasterCell {
    row.indices.contains(index) ? row[index] : .empty
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
    dirtyRows: Set<Int>?,
    dirtyRowRange: (min: Int, max: Int)?,
    visibleIdentities: inout Set<Identity>
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

        // Record visibility BEFORE the dirty-rows cull.  The animation
        // tick-gating check treats this set as a geometric predicate
        // ("would the identity paint cells given the current clip"),
        // not as an observation of the incremental repaint behavior.
        // If a node is currently clipped out entirely by a ScrollView
        // viewport, it will `continue` above and never be recorded.
        // If a node is inside an incremental-repaint skip window its
        // subtree will not be walked (see below), matching the
        // previous behavior; that's fine because every frame on which
        // an animation ticks invalidates the animated identity which
        // forces that subtree's bounds into dirtyRows, so the paint
        // walk will still descend into it.
        if visibleBounds.size.width > 0, visibleBounds.size.height > 0 {
          visibleIdentities.insert(node.identity)
        }

        if let dirtyRowRange {
          let nodeTop = max(0, visibleBounds.origin.y)
          let nodeBottom = nodeTop + max(0, visibleBounds.size.height)
          // O(1) range-overlap check: skip subtree when its row span
          // is entirely outside the dirty-row range.
          if nodeBottom > nodeTop,
            nodeBottom <= dirtyRowRange.min || nodeTop > dirtyRowRange.max
          {
            continue
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
          let clusters = clusterize(line)
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
        let visibleBounds: Rect
        if let clip = frame.clip {
          guard let clippedBounds = intersect(bounds, clip) else {
            continue
          }
          visibleBounds = clippedBounds
        } else {
          visibleBounds = bounds
        }
        imageAttachments.append(
          RasterImageAttachment(
            identity: identity,
            bounds: bounds,
            visibleBounds: visibleBounds,
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
      case .border(
        let bounds,
        let set,
        let foreground,
        let background,
        let blend,
        let blendPhase,
        let sides
      ):
        drawLayoutBorder(
          in: bounds,
          set: set,
          foreground: foreground,
          background: background,
          blend: blend,
          blendPhase: blendPhase,
          sides: sides,
          environment: environment,
          cells: &cells,
          clip: frame.clip
        )
      case .canvas(let bounds, let payload, let foregroundStyle):
        paintCanvasDrawing(
          in: bounds,
          payload: payload,
          foregroundStyle: foregroundStyle,
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

    // Curved shapes normally use a Braille subpixel canvas so their
    // edges antialias onto the 2x4 dot grid. Pattern fills are the
    // exception: they need per-cell glyph writes, so they fall through
    // to the general cell-walking loop below (which calls
    // `shapeContains`, and that now knows about curved geometry).
    switch geometry {
    case .circle, .ellipse, .capsule:
      if case .pattern = colorMode {
        break
      }
      paintBrailleShape(
        geometry: geometry,
        shapeBounds: shapeBounds,
        colorMode: colorMode,
        stroke: false,
        environment: environment,
        cells: &cells,
        clip: clip
      )
      return
    case .rectangle, .roundedRectangle:
      break
    }

    // Detect whether this fill carries alpha for the tint path.
    let constantColor: Color?
    let isTranslucent: Bool
    let patternFill: PatternFill?
    switch colorMode {
    case .constant(let color):
      constantColor = color
      isTranslucent = (color?.alpha ?? 0) < 1
      patternFill = nil
    case .sampled, .sampledRadial:
      constantColor = nil
      // Sampled (gradient) fills may have per-stop alpha.
      isTranslucent = false
      patternFill = nil
    case .pattern(let pattern):
      constantColor = nil
      isTranslucent = false
      patternFill = pattern
    }

    // Pre-compute the glyph cell width for pattern fills once so we
    // handle wide characters (e.g. emoji) correctly inside the inner
    // loop without paying the cost per cell.
    let patternGlyphWidth: Int = {
      guard let patternFill else { return 1 }
      return max(1, cellWidth(of: patternFill.glyph))
    }()

    for y in shapeBounds.origin.y..<(shapeBounds.origin.y + shapeBounds.size.height) {
      var x = shapeBounds.origin.x
      let rowEnd = shapeBounds.origin.x + shapeBounds.size.width
      while x < rowEnd {
        guard
          shapeContains(
            pointX: x,
            pointY: y,
            in: shapeBounds,
            geometry: geometry,
            fillMode: mode
          )
        else {
          x += 1
          continue
        }

        if let patternFill {
          // Pattern fill: overwrite the cell with the glyph using the
          // pattern's foreground and optional background, resolved
          // per cell so gradient paints sample at the current point.
          if x + patternGlyphWidth > rowEnd {
            // Not enough horizontal room for a wide glyph (e.g. an
            // emoji at the very right edge) — skip this cell rather
            // than clipping the glyph in half.
            x += 1
            continue
          }
          write(
            patternFill.glyph,
            width: patternGlyphWidth,
            style: resolvedPatternCellStyle(
              patternFill,
              bounds: shapeBounds,
              sampleX: x,
              sampleY: y
            ),
            atX: x,
            y: y,
            cells: &cells,
            clip: clip
          )
          x += patternGlyphWidth
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
        x += 1
      }
    }
  }

  /// Paints a ``Canvas`` view's drawing into the raster buffer.
  ///
  /// Canvas is the Braille-subpixel escape hatch that sits alongside
  /// the shape pipeline: the layout engine reserves the cell frame,
  /// and here we build a ``BrailleCanvas`` sized to those cells, hand
  /// it to the user via a ``CanvasContext``, and copy the resulting
  /// lit cells out. The context's final foreground/background values
  /// are used for every lit cell — per-primitive colour tracking is
  /// not part of M6.
  private func paintCanvasDrawing(
    in bounds: Rect,
    payload: CanvasPayload,
    foregroundStyle: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    let cellW = bounds.size.width
    let cellH = bounds.size.height
    guard cellW > 0, cellH > 0 else {
      return
    }

    let initialForeground =
      resolveColor(
        from: foregroundStyle,
        environment: environment,
        bounds: bounds,
        sampleX: bounds.origin.x,
        sampleY: bounds.origin.y
      )
      ?? environment.theme.foreground

    var context = CanvasContext(
      canvas: BrailleCanvas(width: cellW, height: cellH),
      foreground: initialForeground,
      background: nil
    )
    guard context.width > 0, context.height > 0 else {
      return
    }
    payload.drawing.draw(into: &context)

    // Walk the Braille canvas and emit a glyph for every cell the
    // drawing touched.  The rasterizer uses the context's *final*
    // foreground/background values for every lit cell — mutating
    // `context.foreground` during drawing changes the terminal colour
    // for the whole canvas, not per-primitive.  This keeps M6 simple
    // and lets the drawing focus on "what dots to light up".
    let finalForeground = context.foreground
    let finalBackground = context.background
    let resolvedStyle = ResolvedTextStyle(
      foregroundColor: finalForeground,
      backgroundColor: finalBackground
    )
    let styleToWrite: ResolvedTextStyle? =
      resolvedStyle.isDefault ? nil : resolvedStyle

    let originX = bounds.origin.x
    let originY = bounds.origin.y
    for cellY in 0..<cellH {
      for cellX in 0..<cellW {
        let cell = context.canvas.cell(x: cellX, y: cellY)
        guard cell.mask != 0 else {
          continue
        }
        write(
          cell.glyph,
          style: styleToWrite,
          atX: originX + cellX,
          y: originY + cellY,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  /// Rasterizes a curved shape (`.circle`, `.ellipse`, `.capsule`)
  /// into the Braille subpixel canvas and writes each non-blank cell
  /// into the raster buffer with the resolved foreground color.
  ///
  /// - Parameter stroke: When `true` draws the outline only; otherwise
  ///   fills the interior.
  private func paintBrailleShape(
    geometry: ShapeGeometry,
    shapeBounds: Rect,
    colorMode: ResolvedShapeColorMode,
    stroke: Bool,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?,
    backgroundStyle: BorderBackgroundStyle? = nil
  ) {
    let cellW = shapeBounds.size.width
    let cellH = shapeBounds.size.height
    guard cellW > 0, cellH > 0 else {
      return
    }

    var canvas = BrailleCanvas(width: cellW, height: cellH)
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    // Center the shape in the subpixel grid.  `(subW - 1) / 2` keeps
    // the anchor on an integer subpixel even for odd/even widths.
    let cx = (subW - 1) / 2
    let cy = (subH - 1) / 2

    switch geometry {
    case .circle:
      // The largest circle fits inside the short axis.  Use (min-1)/2
      // so the outline stays within the inclusive (0...sub-1) range.
      let radius = max(0, (min(subW, subH) - 1) / 2)
      if stroke {
        canvas.strokeCircle(centerX: cx, centerY: cy, radius: radius)
      } else {
        canvas.fillCircle(centerX: cx, centerY: cy, radius: radius)
      }
    case .ellipse:
      let rx = max(0, (subW - 1) / 2)
      let ry = max(0, (subH - 1) / 2)
      if stroke {
        canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      } else {
        canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      }
    case .capsule:
      drawCapsule(into: &canvas, stroke: stroke)
    case .rectangle, .roundedRectangle:
      // Not reachable: the caller dispatches these to the cell-aligned
      // paint path.  We still need the case for exhaustiveness.
      return
    }

    // Walk each Braille cell and emit the glyph with the shape's
    // resolved foreground color.  Empty cells (mask == 0) are skipped
    // so we don't overwrite anything already on the surface.
    let originX = shapeBounds.origin.x
    let originY = shapeBounds.origin.y
    let backgroundColor: Color? =
      backgroundStyle
      .flatMap { $0.backgroundStyle(for: .top) }
      .flatMap { style in
        resolveColor(
          from: resolvedColorMode(from: style, environment: environment),
          bounds: shapeBounds,
          sampleX: originX,
          sampleY: originY
        )
      }

    for cellY in 0..<cellH {
      for cellX in 0..<cellW {
        let cell = canvas.cell(x: cellX, y: cellY)
        guard cell.mask != 0 else {
          continue
        }
        let targetX = originX + cellX
        let targetY = originY + cellY
        let foregroundColor = resolveColor(
          from: colorMode,
          bounds: shapeBounds,
          sampleX: targetX,
          sampleY: targetY
        )
        let resolved = ResolvedTextStyle(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor
        )
        write(
          cell.glyph,
          style: resolved.isDefault ? nil : resolved,
          atX: targetX,
          y: targetY,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  /// Draws a capsule into the Braille canvas. A wide capsule (subW >=
  /// subH) has a rectangular body flanked by two half-circles at the
  /// left and right short-axis ends; a tall capsule has its semicircles
  /// at the top and bottom.
  private func drawCapsule(
    into canvas: inout BrailleCanvas,
    stroke: Bool
  ) {
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    if subW == 1 || subH == 1 {
      // Degenerate: just fill/stroke the whole strip.
      canvas.fillRect(x: 0, y: 0, width: subW, height: subH)
      return
    }

    if subW >= subH {
      // Wide capsule: radius = short axis / 2.
      let radius = max(0, (subH - 1) / 2)
      let cy = (subH - 1) / 2
      let leftCx = radius
      let rightCx = subW - 1 - radius
      if stroke {
        // Two half-circles plus the two horizontal body edges.
        canvas.strokeCircle(centerX: leftCx, centerY: cy, radius: radius)
        canvas.strokeCircle(centerX: rightCx, centerY: cy, radius: radius)
        // Top and bottom body edges between the two centers.
        if rightCx > leftCx {
          for x in leftCx...rightCx {
            canvas.setPixel(x: x, y: cy - radius)
            canvas.setPixel(x: x, y: cy + radius)
          }
        }
      } else {
        canvas.fillCircle(centerX: leftCx, centerY: cy, radius: radius)
        canvas.fillCircle(centerX: rightCx, centerY: cy, radius: radius)
        if rightCx > leftCx {
          let bodyWidth = rightCx - leftCx + 1
          canvas.fillRect(
            x: leftCx,
            y: max(0, cy - radius),
            width: bodyWidth,
            height: min(subH, 2 * radius + 1)
          )
        }
      }
    } else {
      // Tall capsule: radius = short axis (subW) / 2.
      let radius = max(0, (subW - 1) / 2)
      let cx = (subW - 1) / 2
      let topCy = radius
      let bottomCy = subH - 1 - radius
      if stroke {
        canvas.strokeCircle(centerX: cx, centerY: topCy, radius: radius)
        canvas.strokeCircle(centerX: cx, centerY: bottomCy, radius: radius)
        if bottomCy > topCy {
          for y in topCy...bottomCy {
            canvas.setPixel(x: cx - radius, y: y)
            canvas.setPixel(x: cx + radius, y: y)
          }
        }
      } else {
        canvas.fillCircle(centerX: cx, centerY: topCy, radius: radius)
        canvas.fillCircle(centerX: cx, centerY: bottomCy, radius: radius)
        if bottomCy > topCy {
          let bodyHeight = bottomCy - topCy + 1
          canvas.fillRect(
            x: max(0, cx - radius),
            y: topCy,
            width: min(subW, 2 * radius + 1),
            height: bodyHeight
          )
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

    // Curved shapes draw their outline onto a Braille canvas so the
    // stroke resolves to sub-cell precision.
    switch geometry {
    case .circle, .ellipse, .capsule:
      paintBrailleShape(
        geometry: geometry,
        shapeBounds: shapeBounds,
        colorMode: foregroundColorMode,
        stroke: true,
        environment: environment,
        cells: &cells,
        clip: clip,
        backgroundStyle: backgroundStyle
      )
      return
    case .rectangle, .roundedRectangle:
      break
    }

    let lineWidth = max(1, strokeStyle.lineWidth)
    for inset in 0..<lineWidth {
      let insetRect = insetBounds(shapeBounds, by: inset, strokeBorder: strokeBorder)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        continue
      }

      let resolvedSet = resolvedStrokeBorderSet(
        for: geometry,
        strokeStyle: strokeStyle
      )
      let glyphs = BorderGlyphSet(borderSet: resolvedSet)

      let minX = insetRect.origin.x
      let maxX = insetRect.origin.x + insetRect.size.width - 1
      let minY = insetRect.origin.y
      let maxY = insetRect.origin.y + insetRect.size.height - 1

      for x in minX...maxX {
        writeStrokeGlyph(
          glyphs.top,
          borderSet: resolvedSet,
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
            borderSet: resolvedSet,
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
            borderSet: resolvedSet,
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
              borderSet: resolvedSet,
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
        borderSet: resolvedSet,
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
          borderSet: resolvedSet,
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
          borderSet: resolvedSet,
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
          borderSet: resolvedSet,
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
    blend: BorderBlend?,
    blendPhase: Double,
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

    // Perimeter-sampled colors override per-side foregrounds when a
    // ``BorderBlend`` is attached.  We sample once for the whole outer
    // rect and look up by clockwise perimeter index per cell below.
    let perimeterColors: [Color]?
    if let blend {
      let samples = blend.samplePerimeter(
        width: outer.size.width,
        height: outer.size.height,
        phase: blendPhase
      )
      perimeterColors = samples.isEmpty ? nil : samples
    } else {
      perimeterColors = nil
    }

    // Pre-resolve per-side foreground colors so we don't re-run the
    // shape-style resolver once per cell.  A nil per-side color falls
    // back to the theme foreground at draw time.  When a perimeter
    // blend is active these are unused (the per-cell lookup wins).
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
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          ) ?? topForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: cellForeground,
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
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          ) ?? bottomForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: cellForeground,
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
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          ) ?? leftForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: leftWidth,
          foreground: cellForeground,
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
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          ) ?? rightForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: rightWidth,
          foreground: cellForeground,
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
    // corners).  When a perimeter blend is active each corner instead
    // takes the perimeter-array color for its cell position.
    if topWidth > 0 && leftWidth > 0 {
      let cornerX = outer.origin.x
      let cornerY = outer.origin.y
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        ) ?? topForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.topLeading,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: topBackground,
        cells: &cells,
        clip: clip
      )
    }
    if topWidth > 0 && rightWidth > 0 {
      let cornerX = outer.origin.x + outer.size.width - rightWidth
      let cornerY = outer.origin.y
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        ) ?? topForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.topTrailing,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: topBackground,
        cells: &cells,
        clip: clip
      )
    }
    if bottomWidth > 0 && leftWidth > 0 {
      let cornerX = outer.origin.x
      let cornerY = outer.origin.y + outer.size.height - 1
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        ) ?? bottomForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.bottomLeading,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: bottomBackground,
        cells: &cells,
        clip: clip
      )
    }
    if bottomWidth > 0 && rightWidth > 0 {
      let cornerX = outer.origin.x + outer.size.width - rightWidth
      let cornerY = outer.origin.y + outer.size.height - 1
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        ) ?? bottomForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.bottomTrailing,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: bottomBackground,
        cells: &cells,
        clip: clip
      )
    }

  }

  /// Maps a cell at local coordinates `(localX, localY)` inside an
  /// `(width × height)` rectangle to its position in the clockwise
  /// perimeter walk used by ``BorderBlend/samplePerimeter(width:height:phase:)``.
  ///
  /// The walk visits cells in this order:
  ///   top edge L→R, right edge T→B (excluding the top-right corner),
  ///   bottom edge R→L (excluding the bottom-right corner), left edge
  ///   B→T (excluding the bottom-left and top-left corners).
  ///
  /// Returns nil for non-perimeter (interior) cells, for out-of-range
  /// coordinates, or when no perimeter colors are available.
  private func perimeterColor(
    atLocalX localX: Int,
    localY: Int,
    width: Int,
    height: Int,
    perimeter: [Color]?
  ) -> Color? {
    guard let perimeter, !perimeter.isEmpty else {
      return nil
    }
    guard
      let index = perimeterIndex(
        localX: localX,
        localY: localY,
        width: width,
        height: height
      )
    else {
      return nil
    }
    let total = perimeter.count
    let normalized = ((index % total) + total) % total
    return perimeter[normalized]
  }

  /// Returns the clockwise perimeter index for `(localX, localY)` in a
  /// rectangle of size `(width × height)`, or nil if the cell is not on
  /// the perimeter or the inputs are degenerate.
  ///
  /// Walk order (matching ``BorderBlend/samplePerimeter(width:height:phase:)``):
  ///   1. Top edge L→R: indices `[0, width)`.
  ///   2. Right column T→B (excluding TR corner): indices `[width, width + h - 1)`.
  ///   3. Bottom row R→L (excluding BR corner): indices
  ///      `[width + h - 1, 2*width + h - 2)`.
  ///   4. Left column B→T (excluding BL and TL corners): indices
  ///      `[2*width + h - 2, 2*width + 2*h - 4)`.
  ///
  /// Hand-traced against a 4×3 fixture (10 perimeter cells):
  ///   (0,0)=0 (1,0)=1 (2,0)=2 (3,0)=3   ← top
  ///   (3,1)=4 (3,2)=5                   ← right (excl. TR)
  ///   (2,2)=6 (1,2)=7 (0,2)=8           ← bottom (excl. BR)
  ///   (0,1)=9                           ← left (excl. BL+TL)
  private func perimeterIndex(
    localX: Int,
    localY: Int,
    width: Int,
    height: Int
  ) -> Int? {
    guard width > 0, height > 0 else { return nil }
    guard localX >= 0, localX < width, localY >= 0, localY < height else { return nil }
    if width == 1 && height == 1 {
      return 0
    }
    // Top edge wins for y == 0 (handles the height == 1 row case too).
    if localY == 0 {
      return localX
    }
    // Right column for x == width - 1, y >= 1.
    if localX == width - 1 {
      return width + (localY - 1)
    }
    // Bottom row R→L for y == height - 1, x < width - 1.
    if localY == height - 1 {
      return 2 * width + height - 3 - localX
    }
    // Left column B→T for x == 0, 1 <= y <= height - 2.
    if localX == 0 {
      return 2 * width + 2 * height - 4 - localY
    }
    // Interior cell — not on the perimeter.
    return nil
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
    let resolvedSet = resolvedStrokeBorderSet(
      for: .rectangle,
      strokeStyle: strokeStyle
    )
    let glyphs = BorderGlyphSet(borderSet: resolvedSet)
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
          borderSet: resolvedSet,
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
          borderSet: resolvedSet,
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
    borderSet: BorderSet,
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
        borderSet: borderSet,
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
    borderSet: BorderSet,
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

    // Presentation chrome borders draw into the inset region of their
    // owning container (popovers, toasts, menus), so their glyph cells
    // should inherit the interior fill rather than the surrounding
    // background.
    if borderSet == .presentationChrome {
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
    case .rectangle:
      return x >= targetBounds.origin.x
        && x < targetBounds.origin.x + targetBounds.size.width
        && y >= targetBounds.origin.y
        && y < targetBounds.origin.y + targetBounds.size.height
    case .circle, .ellipse, .capsule:
      return curvedShapeContains(
        pointX: x,
        pointY: y,
        in: targetBounds,
        geometry: geometry
      )
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

  /// Tests whether the cell at `(x, y)` is inside a curved shape
  /// (``ShapeGeometry/circle``, ``ShapeGeometry/ellipse``,
  /// ``ShapeGeometry/capsule``) at cell resolution.
  ///
  /// The math mirrors the Braille subpixel renderer in
  /// ``paintBrailleShape(geometry:shapeBounds:colorMode:stroke:environment:cells:clip:backgroundStyle:)``
  /// so that a cell the test reports as "inside" is a cell the Braille
  /// rasterizer would actually paint dots into.
  ///
  /// For each cell, the test projects the cell's visual center into the
  /// canvas subpixel grid (every cell is 2 subpixels wide and 4 tall)
  /// and evaluates the same parametric inequality that `fillCircle`,
  /// `fillEllipse`, and `drawCapsule` use.
  private func curvedShapeContains(
    pointX x: Int,
    pointY y: Int,
    in bounds: Rect,
    geometry: ShapeGeometry
  ) -> Bool {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return false
    }
    let cellRelX = x - bounds.origin.x
    let cellRelY = y - bounds.origin.y
    guard cellRelX >= 0, cellRelX < bounds.size.width,
      cellRelY >= 0, cellRelY < bounds.size.height
    else {
      return false
    }

    // Project the cell's visual center onto the subpixel grid used by
    // `paintBrailleShape`.  A cell is 2 subpixels wide and 4 tall, so
    // the center of cell (cx, cy) in subpixel space is
    // (cx*2 + 0.5, cy*4 + 1.5).  We compute `subW`, `subH`, and the
    // per-shape center/radius in Int space to match `paintBrailleShape`
    // exactly (which uses Int floor division), then convert to Double
    // only for the parametric test.  This guarantees the pattern-fill
    // silhouette matches the Braille disc silhouette cell-for-cell.
    let subW = bounds.size.width * 2
    let subH = bounds.size.height * 4
    let px = Double(cellRelX * 2) + 0.5
    let py = Double(cellRelY * 4) + 1.5

    switch geometry {
    case .circle:
      // Matches `paintBrailleShape`'s circle case:
      //   radius = (min(subW, subH) - 1) / 2  (Int floor)
      //   cx = (subW - 1) / 2, cy = (subH - 1) / 2
      let radius = Double(max(0, (min(subW, subH) - 1) / 2))
      let cxSub = Double((subW - 1) / 2)
      let cySub = Double((subH - 1) / 2)
      let dx = px - cxSub
      let dy = py - cySub
      return dx * dx + dy * dy <= radius * radius
    case .ellipse:
      // Matches `paintBrailleShape`'s ellipse case.
      let rx = max(0, (subW - 1) / 2)
      let ry = max(0, (subH - 1) / 2)
      guard rx > 0, ry > 0 else { return false }
      let cxSub = Double((subW - 1) / 2)
      let cySub = Double((subH - 1) / 2)
      let dx = (px - cxSub) / Double(rx)
      let dy = (py - cySub) / Double(ry)
      return dx * dx + dy * dy <= 1
    case .capsule:
      // Matches `drawCapsule`: wide capsules get left/right semicircles
      // joined by a horizontal body rect, tall capsules are transposed.
      if subW == 1 || subH == 1 {
        return true
      }
      if subW >= subH {
        let radius = Double(max(0, (subH - 1) / 2))
        let cySub = Double((subH - 1) / 2)
        let leftCx = radius
        let rightCx = Double(subW - 1) - radius
        if px < leftCx {
          let dx = px - leftCx
          let dy = py - cySub
          return dx * dx + dy * dy <= radius * radius
        } else if px > rightCx {
          let dx = px - rightCx
          let dy = py - cySub
          return dx * dx + dy * dy <= radius * radius
        } else {
          return py >= cySub - radius && py <= cySub + radius
        }
      } else {
        let radius = Double(max(0, (subW - 1) / 2))
        let cxSub = Double((subW - 1) / 2)
        let topCy = radius
        let bottomCy = Double(subH - 1) - radius
        if py < topCy {
          let dx = px - cxSub
          let dy = py - topCy
          return dx * dx + dy * dy <= radius * radius
        } else if py > bottomCy {
          let dx = px - cxSub
          let dy = py - bottomCy
          return dx * dx + dy * dy <= radius * radius
        } else {
          return px >= cxSub - radius && px <= cxSub + radius
        }
      }
    case .rectangle, .roundedRectangle:
      assertionFailure("curvedShapeContains called with non-curved geometry")
      return false
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
    case .radialGradient(let gradient):
      return .sampledRadial(gradient)
    case .patternFill(let pattern):
      return .pattern(pattern)
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
      case .sampledRadial(let gradient):
        let faded = RadialGradient(
          gradient: Gradient(
            stops: gradient.gradient.stops.map {
              .init(color: $0.color.opacity(amount), location: $0.location)
            }),
          center: gradient.center,
          startRadius: gradient.startRadius,
          endRadius: gradient.endRadius
        )
        return .sampledRadial(faded)
      case .pattern(let pattern):
        let faded = PatternFill(
          glyph: pattern.glyph,
          foreground: pattern.foreground.opacity(amount),
          background: pattern.background?.opacity(amount)
        )
        return .pattern(faded)
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
    case .sampledRadial(let gradient):
      return sample(
        gradient,
        in: bounds,
        x: sampleX,
        y: sampleY
      )
    case .pattern(let pattern):
      // Callers that reduce a pattern fill to a scalar color use
      // the foreground's representative color — the per-cell glyph
      // write path bypasses this helper and consults the
      // ``PatternFill`` directly via ``resolvedPatternCellStyle``.
      return pattern.foreground.representativeColor
    }
  }

  private func resolvedPatternCellStyle(
    _ pattern: PatternFill,
    bounds: Rect,
    sampleX: Int,
    sampleY: Int
  ) -> ResolvedTextStyle? {
    let fg = resolvePaint(
      pattern.foreground,
      bounds: bounds,
      sampleX: sampleX,
      sampleY: sampleY
    )
    let bg = pattern.background.flatMap {
      resolvePaint($0, bounds: bounds, sampleX: sampleX, sampleY: sampleY)
    }
    let resolved = ResolvedTextStyle(
      foregroundColor: fg,
      backgroundColor: bg
    )
    return resolved.isDefault ? nil : resolved
  }

  private func resolvePaint(
    _ paint: PatternFill.Paint,
    bounds: Rect,
    sampleX: Int,
    sampleY: Int
  ) -> Color? {
    switch paint {
    case .color(let color):
      return color
    case .linearGradient(let gradient):
      return sample(gradient, in: bounds, x: sampleX, y: sampleY)
    case .radialGradient(let gradient):
      return sample(gradient, in: bounds, x: sampleX, y: sampleY)
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

    let start = (x: gradient.startPoint.x, y: gradient.startPoint.y)
    let end = (x: gradient.endPoint.x, y: gradient.endPoint.y)
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

  private func sample(
    _ gradient: RadialGradient,
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

    // Center in cell-space coordinates (not normalized).
    let center = (
      x: Double(bounds.origin.x) + gradient.center.x * Double(bounds.size.width),
      y: Double(bounds.origin.y) + gradient.center.y * Double(bounds.size.height)
    )

    // Distance from the sample cell's center to the gradient center
    // in raw cell space (no aspect-ratio compensation — matches the
    // linear gradient sampler's cell-space conventions).
    let px = Double(x) + 0.5
    let py = Double(y) + 0.5
    let dx = px - center.x
    let dy = py - center.y
    let distance = (dx * dx + dy * dy).squareRoot()

    // Normalize to [0, 1] using startRadius and endRadius.  Guard the
    // degenerate case where endRadius == startRadius so we always pin
    // to the end color without a divide-by-zero.
    let denominator = max(0.0001, gradient.endRadius - gradient.startRadius)
    let tRaw = (distance - gradient.startRadius) / denominator
    let t = min(1, max(0, tRaw))

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

  /// Resolves the border set used to stroke `geometry` for `strokeStyle`.
  ///
  /// Preserves the legacy "single-line → rounded corners" auto-upgrade for
  /// rounded rectangles: when the default ``StrokeStyle/normal``
  /// (i.e. ``BorderSet/single``) is applied to a shape with a positive
  /// corner radius, the rasterizer silently upgrades it to
  /// ``BorderSet/rounded`` so container chrome (Button, Picker, Menu…)
  /// keeps its curved corners without every call site needing to pass
  /// `.rounded` explicitly.
  private func resolvedStrokeBorderSet(
    for geometry: ShapeGeometry,
    strokeStyle: StrokeStyle
  ) -> BorderSet {
    if strokeStyle.borderSet == .single,
      case .roundedRectangle(let radius) = geometry,
      radius > 0
    {
      return .rounded
    }
    return strokeStyle.borderSet
  }

  /// Thin single-character adapter over ``BorderSet`` used by the
  /// shape-stroke path and rule painter, which deal in single `Character`
  /// values rather than the multi-rune edge strings that power the
  /// layout-aware border path. Derived glyphs fall back to a space if the
  /// underlying edge is empty (``BorderSet/none`` style).
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

    init(borderSet: BorderSet) {
      self.top = borderSet.top.first ?? " "
      self.bottom = borderSet.bottom.first ?? " "
      self.left = borderSet.left.first ?? " "
      self.right = borderSet.right.first ?? " "
      self.topLeading = borderSet.topLeading.first ?? " "
      self.topTrailing = borderSet.topTrailing.first ?? " "
      self.bottomLeading = borderSet.bottomLeading.first ?? " "
      self.bottomTrailing = borderSet.bottomTrailing.first ?? " "
    }
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

extension Rasterizer {
  package struct SubpixelRadii: Equatable {
    package let rx: Int
    package let ry: Int
  }

  /// Given a cell frame and the current cell-pixel metrics, computes the
  /// largest pixel-true circle's radii in Braille sub-pixel units.
  /// Sub-pixel dimensions are `cellPixelMetrics.width / 2` and
  /// `cellPixelMetrics.height / 4`.
  package static func subpixelCircleRadii(
    frameCells: Size,
    metrics: CellPixelMetrics
  ) -> SubpixelRadii {
    let subpixelPxWidth = max(1, metrics.width / 2)
    let subpixelPxHeight = max(1, metrics.height / 4)
    let pxWidth = frameCells.width * metrics.width
    let pxHeight = frameCells.height * metrics.height
    let diameterPx = max(0, min(pxWidth, pxHeight))
    let radiusPx = diameterPx / 2
    return SubpixelRadii(
      rx: radiusPx / subpixelPxWidth,
      ry: radiusPx / subpixelPxHeight
    )
  }
}

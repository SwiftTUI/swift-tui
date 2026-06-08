extension Rasterizer {
  private struct PaintContext {
    var clip: CellRect?
    var activeBlendMode: BlendMode?
    var presentationEffects: [DrawEffect]
    var dirtyRows: Set<Int>?
    var dirtyRowRange: (min: Int, max: Int)?
  }

  private struct PaintVisibility {
    var clip: CellRect?
    var bounds: CellRect
  }

  /// Temporary surface for an isolated compositing group.
  ///
  /// `cells` mirrors the destination surface dimensions so existing absolute
  /// draw commands can paint without translation. `bounds` records the visible
  /// rectangle that should be flattened back into the destination.
  private struct RasterLayer {
    var bounds: CellRect
    var cells: [[RasterCell]]
    var imageAttachments: [RasterImageAttachment]
  }

  private struct CompositingGroupSplit {
    var effectsInsideGroup: DrawEffects
    var effectsAfterGroup: DrawEffects
  }

  internal func maximumExtent(
    for node: DrawNode,
    clip: CellRect?
  ) -> (x: Int, y: Int) {
    struct Frame {
      let node: DrawNode
      let clip: CellRect?
    }

    var maxX = 0
    var maxY = 0
    var hasVisibleExtent = false
    var stack: [Frame] = [Frame(node: node, clip: clip)]

    while let frame = stack.popLast() {
      guard let visibility = paintVisibility(for: frame.node, inheritedClip: frame.clip) else {
        continue
      }

      let nodeMaxX = visibility.bounds.origin.x + visibility.bounds.size.width
      let nodeMaxY = visibility.bounds.origin.y + visibility.bounds.size.height
      if hasVisibleExtent {
        maxX = max(maxX, nodeMaxX)
        maxY = max(maxY, nodeMaxY)
      } else {
        maxX = nodeMaxX
        maxY = nodeMaxY
        hasVisibleExtent = true
      }

      for child in frame.node.children.reversed() {
        stack.append(Frame(node: child, clip: visibility.clip))
      }
    }

    return (x: maxX, y: maxY)
  }

  internal func paint(
    node: DrawNode,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: CellRect?,
    dirtyRows: Set<Int>?,
    dirtyRowRange: (min: Int, max: Int)?,
    visibleIdentities: inout Set<Identity>,
    presentationRecorder: RasterPresentationLayerRecorder?
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
      case visit(node: DrawNode, context: PaintContext)
      case post(
        commands: [DrawCommand],
        environment: StyleEnvironmentSnapshot,
        context: PaintContext)
    }

    let initialContext = PaintContext(
      clip: clip,
      activeBlendMode: nil,
      presentationEffects: [],
      dirtyRows: dirtyRows,
      dirtyRowRange: dirtyRowRange
    )
    var stack: [Frame] = [.visit(node: node, context: initialContext)]

    while let frame = stack.popLast() {
      switch frame {
      case .post(let commands, let environment, let context):
        paint(
          commands: commands,
          environment: environment,
          cells: &cells,
          imageAttachments: &imageAttachments,
          clip: context.clip,
          blendMode: context.activeBlendMode,
          dirtyRows: context.dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: context.presentationEffects
        )
      case .visit(let node, let context):
        var nodeContext = context
        guard let visibility = paintVisibility(for: node, inheritedClip: context.clip) else {
          continue
        }
        nodeContext.clip = visibility.clip

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
        //
        // Off-screen frame elision soundness depends on this set being a
        // strict paint-visibility predicate: a clipped-out identity must
        // NEVER be recorded here.  The elision gate (see
        // Pipeline/OffscreenFrameElision.swift) skips a deadline-only frame
        // when its redraw set is DISJOINT from the committed
        // `drawnIdentities`.  `redrawIdentities` only ever names the
        // directly-animated identity, so for an off-screen animation
        // (including a layout-affecting one) disjointness holds precisely
        // because the clipped child is absent here.  If a future
        // "optimization" recorded laid-out-but-clipped identities, an
        // off-screen animation that DID push visible cells would still look
        // disjoint and would be wrongly elided — silently voiding elision
        // correctness.  Keep this gated on positive post-clip extent.
        if visibility.bounds.size.width > 0, visibility.bounds.size.height > 0 {
          visibleIdentities.insert(node.identity)
        }

        if let dirtyRowRange = nodeContext.dirtyRowRange {
          let nodeTop = max(0, visibility.bounds.origin.y)
          let nodeBottom = nodeTop + max(0, visibility.bounds.size.height)
          // O(1) range-overlap check: skip subtree when its row span
          // is entirely outside the dirty-row range.
          if nodeBottom > nodeTop,
            nodeBottom <= dirtyRowRange.min || nodeTop > dirtyRowRange.max
          {
            continue
          }
        }

        if let groupSplit = splitAtFirstCompositingGroup(node.drawEffects) {
          paintCompositingGroup(
            node,
            split: groupSplit,
            visibleBounds: visibility.bounds,
            context: nodeContext,
            cells: &cells,
            imageAttachments: &imageAttachments,
            visibleIdentities: &visibleIdentities,
            presentationRecorder: presentationRecorder
          )
          continue
        }

        nodeContext = applyingUngroupedEffects(node.drawEffects, to: nodeContext)

        paint(
          commands: node.commands,
          environment: node.environmentSnapshot.style,
          cells: &cells,
          imageAttachments: &imageAttachments,
          clip: nodeContext.clip,
          blendMode: nodeContext.activeBlendMode,
          dirtyRows: nodeContext.dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: nodeContext.presentationEffects
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
              context: nodeContext
            )
          )
        }
        for child in node.children.reversed() {
          stack.append(.visit(node: child, context: nodeContext))
        }
      }
    }
  }

  private func paintVisibility(
    for node: DrawNode,
    inheritedClip: CellRect?
  ) -> PaintVisibility? {
    let clip = intersect(inheritedClip, node.clipBounds)
    let bounds: CellRect
    if let clip {
      guard let clippedBounds = intersect(node.bounds, clip) else {
        return nil
      }
      bounds = clippedBounds
    } else {
      bounds = node.bounds
    }

    return PaintVisibility(clip: clip, bounds: bounds)
  }

  private func applyingUngroupedEffects(
    _ effects: DrawEffects,
    to context: PaintContext
  ) -> PaintContext {
    var updated = context
    for effect in effects.ordered {
      switch effect {
      case .blendMode(let blendMode):
        updated.activeBlendMode = blendMode
        updated.presentationEffects.removeAll { effect in
          if case .blendMode = effect {
            return true
          }
          return false
        }
        updated.presentationEffects.append(.blendMode(blendMode))
      case .compositingGroup:
        // Callers normally split groups before this helper. If a future
        // segment still contains a group marker, it has no streaming effect
        // by itself; only the split/flatten step changes painting behavior.
        continue
      }
    }
    return updated
  }

  private func splitAtFirstCompositingGroup(
    _ effects: DrawEffects
  ) -> CompositingGroupSplit? {
    var effectsBeforeGroup: [DrawEffect] = []
    var effectsAfterGroup: [DrawEffect] = []
    var foundGroup = false

    for effect in effects.ordered {
      if foundGroup {
        effectsAfterGroup.append(effect)
      } else if effect == .compositingGroup {
        foundGroup = true
      } else {
        effectsBeforeGroup.append(effect)
      }
    }

    guard foundGroup else {
      return nil
    }

    return CompositingGroupSplit(
      effectsInsideGroup: DrawEffects(effectsBeforeGroup),
      effectsAfterGroup: DrawEffects(effectsAfterGroup)
    )
  }

  private func paintCompositingGroup(
    _ node: DrawNode,
    split: CompositingGroupSplit,
    visibleBounds: CellRect,
    context: PaintContext,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    visibleIdentities: inout Set<Identity>,
    presentationRecorder: RasterPresentationLayerRecorder?
  ) {
    guard visibleBounds.size.width > 0, visibleBounds.size.height > 0 else {
      return
    }

    var isolatedNode = node
    isolatedNode.drawEffects = split.effectsInsideGroup
    var layer = RasterLayer(
      bounds: visibleBounds,
      cells: emptyCells(matching: cells),
      imageAttachments: []
    )

    paint(
      node: isolatedNode,
      cells: &layer.cells,
      imageAttachments: &layer.imageAttachments,
      clip: visibleBounds,
      dirtyRows: context.dirtyRows,
      dirtyRowRange: context.dirtyRowRange,
      visibleIdentities: &visibleIdentities,
      presentationRecorder: nil
    )
    compositeLayer(
      layer,
      effects: split.effectsAfterGroup,
      context: context,
      cells: &cells,
      imageAttachments: &imageAttachments,
      presentationRecorder: presentationRecorder
    )
  }

  private func compositeLayer(
    _ layer: RasterLayer,
    effects: DrawEffects,
    context: PaintContext,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    presentationRecorder: RasterPresentationLayerRecorder?
  ) {
    if let nestedGroup = splitAtFirstCompositingGroup(effects) {
      var intermediate = RasterLayer(
        bounds: layer.bounds,
        cells: emptyCells(matching: cells),
        imageAttachments: layer.imageAttachments
      )
      let innerContext = applyingUngroupedEffects(
        nestedGroup.effectsInsideGroup,
        to: PaintContext(
          clip: layer.bounds,
          activeBlendMode: nil,
          presentationEffects: [],
          dirtyRows: context.dirtyRows,
          dirtyRowRange: context.dirtyRowRange
        )
      )
      compositeLayerCells(
        from: layer,
        into: &intermediate.cells,
        context: innerContext,
        presentationRecorder: nil
      )
      compositeLayer(
        intermediate,
        effects: nestedGroup.effectsAfterGroup,
        context: context,
        cells: &cells,
        imageAttachments: &imageAttachments,
        presentationRecorder: presentationRecorder
      )
      return
    }

    var outputContext = applyingUngroupedEffects(effects, to: context)
    outputContext.clip = intersect(context.clip, layer.bounds)
    let destinationCellsBeforeLayer = cells
    compositeLayerCells(
      from: layer,
      into: &cells,
      context: outputContext,
      presentationRecorder: presentationRecorder
    )
    let carriedAttachments =
      if let blendMode = outputContext.activeBlendMode {
        layer.imageAttachments.map { attachment in
          applyingPostGroupBlend(
            blendMode,
            to: attachment,
            sourceCells: layer.cells,
            destinationCells: destinationCellsBeforeLayer
          )
        }
      } else {
        layer.imageAttachments
      }
    for attachment in carriedAttachments {
      imageAttachments.append(attachment)
      presentationRecorder?.appendImageAttachment(
        attachment,
        effects: outputContext.presentationEffects
      )
    }
  }

  private func compositeLayerCells(
    from layer: RasterLayer,
    into cells: inout [[RasterCell]],
    context: PaintContext,
    presentationRecorder: RasterPresentationLayerRecorder?
  ) {
    let startY = layer.bounds.origin.y
    let endY = startY + layer.bounds.size.height
    let startX = layer.bounds.origin.x
    let endX = startX + layer.bounds.size.width

    for y in startY..<endY {
      guard y >= 0, y < layer.cells.count else {
        continue
      }
      for x in startX..<endX {
        guard x >= 0, x < layer.cells[y].count else {
          continue
        }
        let source = layer.cells[y][x]
        guard source.spanWidth > 0, source != .empty else {
          continue
        }
        write(
          source.character,
          width: source.spanWidth,
          style: source.style,
          hyperlink: source.hyperlink,
          atX: x,
          y: y,
          cells: &cells,
          clip: context.clip,
          blendMode: context.activeBlendMode,
          presentationRecorder: presentationRecorder,
          presentationEffects: context.presentationEffects
        )
      }
    }
  }

  private func emptyCells(matching cells: [[RasterCell]]) -> [[RasterCell]] {
    guard let width = cells.first?.count else {
      return []
    }
    return Array(
      repeating: Array(repeating: RasterCell.empty, count: width),
      count: cells.count
    )
  }

  internal func paint(
    commands: [DrawCommand],
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    struct Frame {
      let command: DrawCommand
      let clip: CellRect?
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
              clip: frame.clip,
              blendMode: blendMode,
              presentationRecorder: presentationRecorder,
              presentationEffects: presentationEffects
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
              clip: frame.clip,
              blendMode: blendMode,
              presentationRecorder: presentationRecorder,
              presentationEffects: presentationEffects
            )
            x += cluster.cellWidth
          }
        }
      case .styledPreformattedText(
        let bounds,
        let lines,
        let style
      ):
        guard bounds.size.height > 0, bounds.size.width > 0 else {
          continue
        }

        for (lineIndex, line) in lines.prefix(bounds.size.height).enumerated() {
          var x = bounds.origin.x

          for run in line.runs {
            let runStyle = style.merging(run.style)
            let clusters = clusterize(run.content)

            for cluster in clusters {
              guard x + cluster.cellWidth <= bounds.origin.x + bounds.size.width else {
                break
              }

              let resolvedStyle = resolveTextStyle(
                runStyle,
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
                clip: frame.clip,
                blendMode: blendMode,
                presentationRecorder: presentationRecorder,
                presentationEffects: presentationEffects
              )
              x += cluster.cellWidth
            }

            if x >= bounds.origin.x + bounds.size.width {
              break
            }
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
              clip: frame.clip,
              blendMode: blendMode,
              presentationRecorder: presentationRecorder,
              presentationEffects: presentationEffects
            )
            x += cluster.cellWidth
            if x >= bounds.origin.x + bounds.size.width {
              break
            }
          }
        }
      case .image(let bounds, let identity, let payload):
        let visibleBounds: CellRect
        if let clip = frame.clip {
          guard let clippedBounds = intersect(bounds, clip) else {
            continue
          }
          visibleBounds = clippedBounds
        } else {
          visibleBounds = bounds
        }
        let compositing =
          imageCompositing(
            blendMode: blendMode,
            visibleBounds: visibleBounds,
            sourceBackdrop: nil,
            cellPixelSize: payload.resolvedAsset?.cellPixelSize,
            destinationCells: cells
          )
        let attachment = RasterImageAttachment(
          identity: identity,
          bounds: bounds,
          visibleBounds: visibleBounds,
          source: payload.source,
          resolvedReference: payload.resolvedAsset?.reference,
          pixelSize: payload.resolvedAsset?.pixelSize,
          cellPixelSize: payload.resolvedAsset?.cellPixelSize,
          isResizable: payload.isResizable,
          scalingMode: payload.scalingMode,
          compositing: compositing
        )
        imageAttachments.append(attachment)
        presentationRecorder?.appendImageAttachment(
          attachment,
          effects: presentationEffects
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
          clip: frame.clip,
          blendMode: blendMode,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
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
          clip: frame.clip,
          blendMode: blendMode,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
      case .rule(let bounds, let style, let strokeStyle, let stackAxis):
        paintRule(
          in: bounds,
          style: style,
          strokeStyle: strokeStyle,
          stackAxis: stackAxis,
          environment: environment,
          cells: &cells,
          clip: frame.clip,
          blendMode: blendMode,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
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
          clip: frame.clip,
          blendMode: blendMode,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
      case .canvas(let bounds, let payload, let foregroundStyle):
        paintCanvasDrawing(
          in: bounds,
          payload: payload,
          foregroundStyle: foregroundStyle,
          environment: environment,
          cells: &cells,
          clip: frame.clip,
          blendMode: blendMode,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
      case .foreignSurface(let bounds, let payload):
        guard bounds.size.width > 0, bounds.size.height > 0 else {
          continue
        }

        let grid = payload.grid
        let effectiveClip = frame.clip ?? bounds
        for row in 0..<min(grid.size.height, bounds.size.height) {
          let y = bounds.origin.y + row
          if y < effectiveClip.origin.y || y >= effectiveClip.origin.y + effectiveClip.size.height {
            continue
          }
          guard row < grid.cells.count else {
            break
          }
          let sourceRow = grid.cells[row]
          for col in 0..<min(grid.size.width, bounds.size.width) {
            let x = bounds.origin.x + col
            if x < effectiveClip.origin.x || x >= effectiveClip.origin.x + effectiveClip.size.width
            {
              continue
            }
            guard col < sourceRow.count else {
              break
            }
            guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
              continue
            }
            let sourceCell = sourceRow[col]
            if let blendMode {
              guard sourceCell.spanWidth != 0 else {
                continue
              }
              write(
                sourceCell.character,
                width: sourceCell.spanWidth,
                style: sourceCell.style,
                hyperlink: sourceCell.hyperlink,
                atX: x,
                y: y,
                cells: &cells,
                clip: frame.clip,
                blendMode: blendMode,
                presentationRecorder: presentationRecorder,
                presentationEffects: presentationEffects
              )
            } else {
              cells[y][x] = sourceCell
              presentationRecorder?.appendCellFragment(
                from: cells,
                x: x,
                y: y,
                width: max(1, sourceCell.spanWidth),
                effects: presentationEffects
              )
            }
          }
        }
      }
    }
  }

  private func applyingPostGroupBlend(
    _ blendMode: BlendMode,
    to attachment: RasterImageAttachment,
    sourceCells: [[RasterCell]],
    destinationCells: [[RasterCell]]
  ) -> RasterImageAttachment {
    guard let cellPixelSize = attachment.cellPixelSize else {
      return attachment
    }

    var updated = attachment
    let sourceBackdrop = captureImageBackdrop(
      in: sourceCells,
      bounds: attachment.visibleBounds
    )
    updated.compositing = imageCompositing(
      blendMode: blendMode,
      visibleBounds: attachment.visibleBounds,
      sourceBackdrop: sourceBackdrop,
      cellPixelSize: cellPixelSize,
      destinationCells: destinationCells
    )
    return updated
  }

  private func imageCompositing(
    blendMode: BlendMode?,
    visibleBounds: CellRect,
    sourceBackdrop: RasterImageBackdrop?,
    cellPixelSize: PixelSize?,
    destinationCells: [[RasterCell]]
  ) -> RasterImageCompositing? {
    guard let blendMode,
      let cellPixelSize,
      visibleBounds.size.width > 0,
      visibleBounds.size.height > 0
    else {
      return nil
    }

    let destinationBackdrop = captureImageBackdrop(
      in: destinationCells,
      bounds: visibleBounds
    )
    return RasterImageCompositing(
      blendMode: blendMode,
      destinationBackdrop: destinationBackdrop,
      sourceBackdrop: sourceBackdrop,
      cellPixelSize: cellPixelSize,
      backdropSignature: imageCompositingSignature(
        blendMode: blendMode,
        destinationBackdrop: destinationBackdrop,
        sourceBackdrop: sourceBackdrop,
        cellPixelSize: cellPixelSize
      )
    )
  }

  private func captureImageBackdrop(
    in cells: [[RasterCell]],
    bounds: CellRect
  ) -> RasterImageBackdrop {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return RasterImageBackdrop(bounds: bounds, cells: [])
    }

    var backdropCells: [RasterImageBackdropCell] = []
    backdropCells.reserveCapacity(bounds.size.width * bounds.size.height)
    for y in bounds.origin.y..<(bounds.origin.y + bounds.size.height) {
      for x in bounds.origin.x..<(bounds.origin.x + bounds.size.width) {
        let backdropCell: RasterImageBackdropCell =
          if y >= 0, y < cells.count, x >= 0, x < cells[y].count {
            if let leadX = cells[y][x].continuationLeadX,
              leadX >= 0,
              leadX < cells[y].count
            {
              RasterImageBackdropCell(
                backgroundColor: cells[y][x].style?.backgroundColor,
                foregroundColor: cells[y][x].style?.foregroundColor,
                glyph: cells[y][leadX].character,
                spanWidth: max(1, cells[y][leadX].spanWidth),
                spanOffset: max(0, x - leadX)
              )
            } else {
              RasterImageBackdropCell(
                backgroundColor: cells[y][x].style?.backgroundColor,
                foregroundColor: cells[y][x].style?.foregroundColor,
                glyph: cells[y][x].character,
                spanWidth: max(1, cells[y][x].spanWidth),
                spanOffset: 0
              )
            }
          } else {
            RasterImageBackdropCell(backgroundColor: nil)
          }
        backdropCells.append(backdropCell)
      }
    }

    return RasterImageBackdrop(bounds: bounds, cells: backdropCells)
  }

  private func imageCompositingSignature(
    blendMode: BlendMode,
    destinationBackdrop: RasterImageBackdrop,
    sourceBackdrop: RasterImageBackdrop?,
    cellPixelSize: PixelSize
  ) -> UInt64 {
    var hash = DeterministicImageBackdropHasher()
    hash.combine("blend")
    hash.combine(blendMode.rawValue)
    hash.combine("cell")
    hash.combine(cellPixelSize.width)
    hash.combine(cellPixelSize.height)
    hash.combine("destination")
    hash.combine(destinationBackdrop)
    hash.combine("source")
    if let sourceBackdrop {
      hash.combine(sourceBackdrop)
    } else {
      hash.combine(0)
    }
    return hash.value
  }
}

private struct DeterministicImageBackdropHasher {
  private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

  mutating func combine(
    _ string: String
  ) {
    for byte in string.utf8 {
      combine(byte)
    }
    combine(UInt8(0))
  }

  mutating func combine(
    _ value: Int
  ) {
    combine(UInt64(bitPattern: Int64(value)))
  }

  mutating func combine(
    _ value: UInt64
  ) {
    var remaining = value
    for _ in 0..<8 {
      combine(UInt8(remaining & 0xFF))
      remaining >>= 8
    }
  }

  mutating func combine(
    _ backdrop: RasterImageBackdrop
  ) {
    combine(backdrop.bounds.origin.x)
    combine(backdrop.bounds.origin.y)
    combine(backdrop.bounds.size.width)
    combine(backdrop.bounds.size.height)
    combine(backdrop.cells.count)
    for cell in backdrop.cells {
      combine(cell)
    }
  }

  private mutating func combine(
    _ cell: RasterImageBackdropCell
  ) {
    combine("bg")
    combineOptionalColor(cell.backgroundColor)
    combine("fg")
    combineOptionalColor(cell.foregroundColor)
    combine("glyph")
    if let glyph = cell.glyph {
      combine(UInt8(1))
      combine(String(glyph))
    } else {
      combine(UInt8(0))
    }
    combine("span")
    combine(cell.spanWidth)
    combine("offset")
    combine(cell.spanOffset)
    combine("coverage")
    combine(rasterBackdropCoverage(for: cell.glyph, spanWidth: cell.spanWidth))
  }

  private mutating func combineOptionalColor(
    _ color: Color?
  ) {
    guard let color else {
      combine(UInt8(0))
      return
    }
    combine(UInt8(1))
    combine(color.red.bitPattern)
    combine(color.green.bitPattern)
    combine(color.blue.bitPattern)
    combine(color.alpha.bitPattern)
    combine(color.profile.name)
    combine(color.profile.whitePoint.name)
    combine(color.profile.whitePoint.x.bitPattern)
    combine(color.profile.whitePoint.y.bitPattern)
    combine(color.profile.primaries.red.x.bitPattern)
    combine(color.profile.primaries.red.y.bitPattern)
    combine(color.profile.primaries.green.x.bitPattern)
    combine(color.profile.primaries.green.y.bitPattern)
    combine(color.profile.primaries.blue.x.bitPattern)
    combine(color.profile.primaries.blue.y.bitPattern)
    combine(String(describing: color.profile.transferFunction))
  }

  private mutating func combine(
    _ coverage: RasterBackdropCoverage
  ) {
    switch coverage {
    case .none:
      combine("none")
    case .full:
      combine("full")
    case .quadrant(let mask):
      combine("quadrant")
      combine(mask)
    case .braille(let mask):
      combine("braille")
      combine(mask)
    case .textApproximation:
      combine("text")
    }
  }

  private mutating func combine(
    _ byte: UInt8
  ) {
    value ^= UInt64(byte)
    value &*= 0x100_0000_01b3
  }
}

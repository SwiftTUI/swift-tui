extension Rasterizer {
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
      let effectiveClip = intersect(frame.clip, frame.node.clipBounds)
      let visibleBounds: CellRect
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

  internal func paint(
    node: DrawNode,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: CellRect?,
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
      case visit(node: DrawNode, clip: CellRect?, blendMode: BlendMode?)
      case post(
        commands: [DrawCommand],
        environment: StyleEnvironmentSnapshot,
        clip: CellRect?,
        blendMode: BlendMode?)
    }

    var stack: [Frame] = [.visit(node: node, clip: clip, blendMode: nil)]

    while let frame = stack.popLast() {
      switch frame {
      case .post(let commands, let environment, let clip, let blendMode):
        paint(
          commands: commands,
          environment: environment,
          cells: &cells,
          imageAttachments: &imageAttachments,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows
        )
      case .visit(let node, let frameClip, let inheritedBlendMode):
        let activeBlendMode = node.metadata.blendMode ?? inheritedBlendMode
        let effectiveClip = intersect(frameClip, node.clipBounds)
        let visibleBounds: CellRect
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
          blendMode: activeBlendMode,
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
              clip: effectiveClip,
              blendMode: activeBlendMode
            )
          )
        }
        for child in node.children.reversed() {
          stack.append(.visit(node: child, clip: effectiveClip, blendMode: activeBlendMode))
        }
      }
    }
  }

  internal func paint(
    commands: [DrawCommand],
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil
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
              blendMode: blendMode
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
              blendMode: blendMode
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
                blendMode: blendMode
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
              blendMode: blendMode
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
          clip: frame.clip,
          blendMode: blendMode
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
          blendMode: blendMode
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
          blendMode: blendMode
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
          blendMode: blendMode
        )
      case .canvas(let bounds, let payload, let foregroundStyle):
        paintCanvasDrawing(
          in: bounds,
          payload: payload,
          foregroundStyle: foregroundStyle,
          environment: environment,
          cells: &cells,
          clip: frame.clip,
          blendMode: blendMode
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
                blendMode: blendMode
              )
            } else {
              cells[y][x] = sourceCell
            }
          }
        }
      }
    }
  }

}

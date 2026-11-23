extension Rasterizer {
  /// Applies one isolation boundary. Implicit capture keeps a snapshot of its enclosing
  /// destination available to nested readers. Explicit compositing groups start a new target.
  func paintCellLayer(
    _ node: DrawNode, pass: CellEffectPass, clip: CellRect?, blendMode: BlendMode?,
    effects: [DrawEffect], dirtyRows: Set<Int>?, cells: inout [[RasterCell]],
    visibleIdentities: inout Set<Identity>, recorder: RasterPresentationLayerRecorder?,
    lineArms: LineArmsTable? = nil
  ) {
    guard !node.bounds.isEmpty else { return }
    let size = CellSize(width: cells.first?.count ?? 0, height: cells.count)
    let surface = CellRect(origin: .zero, size: size)
    guard let target = surface.intersection(clip ?? surface) else { return }
    let inheritedViewport = recorder?.cellCapture?.viewport ?? surface
    let viewport = clip.map { inheritedViewport.intersection($0) ?? .zero } ?? inheritedViewport
    let origin = node.bounds.origin
    // A previous pass can paint beyond layout. Preserve that ink for an outer
    // shader without changing the subject's local coordinate origin.
    var sourceBounds = node.subtreeHasCellEffect ? node.subtreeBounds : node.bounds
    if node.subtreeDrawsInViewport { sourceBounds = sourceBounds.union(viewport) }
    let localSource = sourceBounds.relative(to: origin)
    let localViewport = viewport.relative(to: origin)
    // Captures must be able to paint offscreen source before a later mapping
    // brings it back into view. An explicitly requested viewport remains the
    // real enclosing viewport regardless of the current scratch dimensions.
    let domain = recorder?.cellCapture?.paintDomain ?? surface
    let clippedDomain = clip.map { domain.intersection($0) ?? .zero } ?? domain
    let logicalOutput = pass.shader.region.bounds(
      source: localSource,
      viewport: (pass.shader.region == .viewport ? viewport : clippedDomain).relative(to: origin))
    guard let output = logicalOutput.intersection(target.relative(to: origin)) else { return }
    if let probe = RasterWorkProbe.active() {
      var work = RasterWorkCounters()
      work.cellEffectCaptures = 1
      probe.record(work)
    }
    let style = node.environmentSnapshot.style
    let targetOrigin = recorder?.cellCapture?.originInRoot ?? .zero
    let rootOrigin = CellPoint(
      x: SaturatingConversion.adding(targetOrigin.x, origin.x),
      y: SaturatingConversion.adding(targetOrigin.y, origin.y))
    let context = CellEffectContext(
      sourceBounds: pass.targetsBackdrop ? logicalOutput : localSource, outputBounds: logicalOutput,
      viewport: localViewport,
      originInRoot: rootOrigin, appearance: style.appearance,
      cellPixelMetrics: style.cellPixelMetrics)

    // A single source-only pass never depends on prior paint. Avoid retaining
    // destination rows and forcing a COW copy for every row we overwrite.
    let backdrop: CellLayer
    if pass.targetsBackdrop || pass.shader.readsBackdrop || node.subtreeHasCellEffect {
      backdrop = cellLayer(
        cells: cells, capture: recorder?.cellCapture, absoluteBounds: viewport,
        origin: origin, allowsLink: true, backdropContext: context)
    } else {
      backdrop = CellLayer(bounds: .zero, readableBounds: .zero) { _ in .empty }
    }
    // Reuse absolute coordinates for an on-screen capture. For off-screen
    // content the scratch origin travels to the needed source rectangle.
    let input: CellRect
    if case .prepared = pass.shader.program {
      input = sourceBounds
    } else {
      switch pass.offset {
      case .layerBounds: input = sourceBounds
      case .cells(let dx, let dy):
        // A read at a continuation also needs the lead just outside the window.
        let reach = CellDrawingRegion.outset(x: SaturatingConversion.adding(max(0, dx), 2), y: dy)
        let readOutput: CellRect
        if case .ordered = pass.shader.program {
          readOutput = logicalOutput
        } else {
          readOutput = output
        }
        let readBounds = reach.bounds(source: readOutput, viewport: localSource)
        input = .init(
          origin: .init(
            x: SaturatingConversion.adding(origin.x, readBounds.origin.x),
            y: SaturatingConversion.adding(origin.y, readBounds.origin.y)), size: readBounds.size)
      }
    }
    let captureBounds = sourceBounds
    let tiles: RasterCellSourceTiles?
    let capture: CellLayer
    let strokeArms = node.metadata.layoutBorderEffect == nil ? nil : lineArms?.snapshot()
    let visibleStroke = strokeArms.map { arms in
      captureSourceTile(
        node: node, sourceBounds: captureBounds, viewport: viewport,
        targetOrigin: targetOrigin, backdrop: backdrop, tile: surface,
        visibleIdentities: &visibleIdentities, strokeBackdrop: cells, strokeArms: arms)
    }
    if pass.targetsBackdrop {
      tiles = nil
      capture = CellLayer(bounds: logicalOutput, readableBounds: logicalOutput) { position in
        let sample = backdrop.sample(at: position)
        switch sample {
        case .empty: return .empty
        case .glyph(let glyph):
          return glyph.width <= logicalOutput.maxX - position.x ? sample : .empty
        case .continuation(let back):
          guard back <= position.x - logicalOutput.origin.x,
            let glyph = backdrop.glyph(occupying: position),
            glyph.width - back <= logicalOutput.maxX - position.x
          else { return .empty }
          return sample
        }
      }
    } else if Self.boundedSurfaceSize(input.size, maximum: nil) != input.size {
      let cache = RasterCellSourceTiles()
      tiles = cache
      capture = CellLayer(bounds: localSource, readableBounds: localSource) { position in
        cache.sample(position, in: localSource) { tile, identities in
          let absolute = CellRect(
            origin: .init(
              x: SaturatingConversion.adding(tile.origin.x, origin.x),
              y: SaturatingConversion.adding(tile.origin.y, origin.y)), size: tile.size)
          return captureSourceTile(
            node: node, sourceBounds: captureBounds, viewport: viewport,
            targetOrigin: targetOrigin, backdrop: backdrop, tile: absolute,
            visibleIdentities: &identities)
        }
      }
    } else {
      tiles = nil
      let tile = input.intersection(surface) == input ? surface : input
      if tile == surface, let visibleStroke {
        capture = visibleStroke
      } else {
        capture = captureSourceTile(
          node: node, sourceBounds: captureBounds, viewport: viewport,
          targetOrigin: targetOrigin, backdrop: backdrop, tile: tile,
          visibleIdentities: &visibleIdentities)
      }
    }
    let source: CellLayer
    if let visibleStroke {
      let onSurface = surface.relative(to: origin)
      source = CellLayer(bounds: localSource, readableBounds: localSource) { point in
        onSurface.contains(point) ? visibleStroke.sample(at: point) : capture.sample(at: point)
      }
    } else {
      source = capture
    }
    defer {
      if let tiles { visibleIdentities.formUnion(tiles.visibleIdentities) }
    }

    evaluateCellPass(
      node, pass: pass, source: source, backdrop: backdrop, context: context,
      output: output, domain: clippedDomain.relative(to: origin), target: target,
      blendMode: blendMode, effects: effects, dirtyRows: dirtyRows, cells: &cells,
      recorder: recorder,
      joins: strokeArms.flatMap { scratch in lineArms.map { ($0, scratch) } })
  }

  private func evaluateCellPass(
    _ node: DrawNode, pass: CellEffectPass, source: CellLayer, backdrop: CellLayer,
    context: CellEffectContext, output: CellRect, domain: CellRect, target: CellRect,
    blendMode: BlendMode?, effects: [DrawEffect], dirtyRows: Set<Int>?, cells: inout [[RasterCell]],
    recorder: RasterPresentationLayerRecorder?, joins: (LineArmsTable, LineArmsTable)?
  ) {
    var resolved = pass
    var effective = context
    var writeBounds = output
    if case .prepared(let prepare) = pass.shader.program {
      let geometry = CellEffectContext(
        sourceBounds: source.bounds,
        outputBounds: source.bounds.intersection(context.viewport) ?? .zero,
        viewport: context.viewport,
        originInRoot: context.originInRoot, appearance: context.appearance,
        cellPixelMetrics: context.cellPixelMetrics)
      let shader = prepare(source, geometry, cellPreparationFrame ?? .init(at: .now()))
      resolved = .init(shader, offset: pass.offset)
      let bounds = shader.region.bounds(
        source: source.bounds,
        viewport: shader.region == .viewport ? context.viewport : domain)
      guard let visible = bounds.intersection(target.relative(to: node.bounds.origin)) else {
        return
      }
      writeBounds = visible
      effective = .init(
        sourceBounds: source.bounds, outputBounds: bounds, viewport: context.viewport,
        originInRoot: context.originInRoot, appearance: context.appearance,
        cellPixelMetrics: context.cellPixelMetrics)
    }
    compositeCellLayer(
      node, pass: resolved, source: source, backdrop: backdrop,
      context: effective, output: writeBounds, target: target, blendMode: blendMode,
      effects: effects,
      dirtyRows: dirtyRows, cells: &cells, recorder: recorder, joins: joins)
  }

  // Source capture above can recursively enter another effect on a 512 KiB
  // worker. Allocate the evaluation and compositing frame after capture returns.
  private func compositeCellLayer(
    _ node: DrawNode, pass: CellEffectPass, source: CellLayer, backdrop: CellLayer,
    context: CellEffectContext, output: CellRect, target: CellRect, blendMode: BlendMode?,
    effects: [DrawEffect], dirtyRows: Set<Int>?, cells: inout [[RasterCell]],
    recorder: RasterPresentationLayerRecorder?, joins: (LineArmsTable, LineArmsTable)?
  ) {
    let logicalOutput = context.outputBounds
    let origin = node.bounds.origin
    let evaluate: (CellPoint) -> CellCompositeResult
    switch pass.shader.program {
    case .placement, .prepared:
      // Descriptors are resolved at placement or before compositing.
      return
    case .source(let shade):
      evaluate = { point in
        let input = source.restricted(
          to: pass.offset.window(around: point, in: source.bounds), pass: pass)
        let sample = shade(point, input, context)
        if sample == .empty && !pass.targetsBackdrop { return .keepDestination }
        return .replace(sample)
      }
    case .composite(let composite):
      let lower = pass.targetsBackdrop ? source : backdrop
      evaluate = { point in
        composite(
          point,
          source.restricted(to: pass.offset.window(around: point, in: source.bounds), pass: pass),
          lower.restricted(to: pass.offset.window(around: point, in: lower.bounds), pass: pass),
          context)
      }
    case .ordered(let apply):
      let read: CellRect
      switch pass.offset {
      case .layerBounds: read = source.bounds
      case .cells(let x, let y):
        read = CellDrawingRegion.outset(x: x, y: y).bounds(
          source: logicalOutput, viewport: source.bounds)
      }
      let input = source.restricted(to: read, pass: pass)
      var buffer = CellEffectBuffer(bounds: logicalOutput, source: input)
      apply(input, &buffer, context)
      let result = buffer.snapshot()
      evaluate = { point in
        let sample = result.sample(at: point)
        if sample == .empty && !pass.targetsBackdrop { return .keepDestination }
        return .replace(sample)
      }
    }

    for localY in output.origin.y..<output.maxY {
      let y = localY + origin.y
      if let dirtyRows, !dirtyRows.contains(y) { continue }
      var claimedUntil = output.origin.x
      for localX in output.origin.x..<output.maxX {
        let position = CellPoint(x: localX, y: localY)
        guard case .replace(let sample) = evaluate(position), localX >= claimedUntil else {
          continue
        }
        if case .empty = sample {
          if let (targetArms, tentative) = joins {
            targetArms.adopt(tentative, at: .init(x: localX + origin.x, y: y), matching: nil)
          }
          clearExistingGlyph(
            atX: localX + origin.x, y: y, cells: &cells, capture: recorder?.cellCapture)
          continue
        }
        guard case .glyph(let glyph) = sample, glyph.width > 0,
          glyph.width <= output.maxX - localX, glyph.paint.coverage > 0
        else { continue }
        let x = localX + origin.x
        var paint = glyph.paint
        let fraction = paint.coverage
        let deferCoverage =
          recorder?.cellCapture?.defersCoverage == true
          && recorder?.cellCapture?.columns[y][x].hasPaint == false
        if fraction < 1 && !deferCoverage {
          let under = cells[y][x].style?.backgroundColor ?? context.appearance.backgroundColor
          paint = context.compositingCoverage(of: glyph, over: under)
        }
        let result = glyph.rasterStyle(for: paint, in: context.appearance)
        // A compositing result already names the final channels. Retaining
        // the old style here would blend it a second time or turn a requested
        // default channel back into the previous foreground/background.
        if pass.targetsBackdrop || pass.shader.readsBackdrop, blendMode == nil {
          clearExistingGlyph(atX: x, y: y, cells: &cells, capture: recorder?.cellCapture)
        }
        write(
          glyph.character, width: glyph.width, style: result.isDefault ? nil : result,
          hyperlink: node.isTransient ? nil : glyph.link?.rawValue, atX: x, y: y, cells: &cells,
          clip: target,
          blendMode: blendMode, presentationRecorder: recorder, presentationEffects: effects)
        if let (targetArms, tentative) = joins {
          let isOriginal = source.glyph(occupying: position)?.character == glyph.character
          targetArms.adopt(
            tentative, at: .init(x: x, y: y), matching: isOriginal ? glyph.character : nil)
        }
        if fraction < 1 && deferCoverage {
          recorder?.cellCapture?.fractionalCoverage[.init(x: x, y: y)] = fraction
        }
        claimedUntil = localX + glyph.width
      }
    }
  }
}

extension Rasterizer {
  /// Project at the image paint command so later text and borders occlude it normally.
  func paintEffectImage(
    _ attachment: RasterImageAttachment, appearance: TerminalAppearance,
    cells: inout [[RasterCell]], recorder: RasterPresentationLayerRecorder?, effects: [DrawEffect]
  ) {
    guard let image = effectImageProjection?(attachment, appearance.backgroundColor),
      let visible = attachment.visibleBounds.intersection(image.bounds)?.intersection(
        .init(origin: .zero, size: .init(width: cells.first?.count ?? 0, height: cells.count)))
    else { return }
    for y in visible.origin.y..<visible.maxY {
      let row = y - image.bounds.origin.y
      guard image.cells.indices.contains(row) else { continue }
      for x in visible.origin.x..<visible.maxX {
        let column = x - image.bounds.origin.x
        guard image.cells[row].indices.contains(column), let cell = image.cells[row][column] else {
          continue
        }
        write(
          cell.character, width: cell.spanWidth, attributes: cell.attributes,
          atX: x, y: y, cells: &cells, clip: visible, presentationRecorder: recorder,
          presentationEffects: effects)
      }
    }
  }
}

extension CellEffectContext {
  func compositingCoverage(of glyph: CellGlyph, over lowerPaper: Color) -> CellPaint {
    let resolved = resolvedColors(for: glyph.paint, emphasis: glyph.emphasis, over: lowerPaper)
    let paper = resolved.background.opacity(glyph.paint.coverage).composited(over: lowerPaper)
    let ink = resolved.foreground.opacity(glyph.paint.coverage).composited(over: paper)
    let reversed = glyph.emphasis.contains(.reverse)
    return CellPaint(
      foreground: .color(reversed ? paper : ink), background: .color(reversed ? ink : paper))
  }
}

extension CellGlyph {
  func rasterStyle(for paint: CellPaint, in appearance: TerminalAppearance) -> ResolvedTextStyle {
    var style = ResolvedTextStyle(
      foregroundColor: paint.foreground.color(in: appearance),
      backgroundColor: paint.background.color(in: appearance), emphasis: emphasis,
      underlineStyle: underline, strikethroughStyle: strikethrough, opacity: originalOpacity)
    style.foregroundPaletteIndex = paint.foreground.paletteIndex
    style.backgroundPaletteIndex = paint.background.paletteIndex
    return style
  }
}

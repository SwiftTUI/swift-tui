extension View {
  /// Transforms cells painted by this mounted view at its position in the draw order.
  public func layerEffect(
    _ shader: CellLayerShader, maxSampleOffset: CellSampleOffset, isEnabled: Bool = true
  ) -> some View {
    modifier(
      DrawEffectModifier(
        effect: isEnabled ? .cellLayer(.init(shader, offset: maxSampleOffset)) : nil))
  }

  /// Transforms cells using a Swift function. Captured inputs must remain stable during paint.
  public func layerEffect(
    maxSampleOffset: CellSampleOffset, isEnabled: Bool = true,
    _ shade: @escaping CellLayerShader.Function
  ) -> some View {
    layerEffect(CellLayerShader(shade), maxSampleOffset: maxSampleOffset, isEnabled: isEnabled)
  }

  /// Transforms the selected lower paint immediately before drawing this view.
  public func backdropEffect(
    _ shader: CellLayerShader, in region: CellDrawingRegion,
    maxSampleOffset: CellSampleOffset, isEnabled: Bool = true
  ) -> some View {
    modifier(
      DrawEffectModifier(
        effect: isEnabled
          ? .cellLayer(
            .init(shader.drawing(in: region), offset: maxSampleOffset, targetsBackdrop: true))
          : nil))
  }
}

extension View {
  /// Prepares an immutable shader once per logical sample at this mounted modifier site.
  public func layerEffect<K: CellPreparedLayerKernel>(
    _ kernel: K, maxSampleOffset: CellSampleOffset, isEnabled: Bool = true
  ) -> some View {
    modifier(
      PreparedCellEffectModifier(kernel: kernel, offset: maxSampleOffset, enabled: isEnabled))
  }

  /// Shades the current laid-out cells during an animated change of placement in the same parent.
  public func placementEffect(
    maxSampleOffset: CellSampleOffset, isEnabled: Bool = true,
    _ makeShader: @escaping @Sendable (CellPlacementContext) -> CellLayerShader
  ) -> some View {
    layerEffect(
      CellLayerShader(placement: makeShader), maxSampleOffset: maxSampleOffset, isEnabled: isEnabled
    )
  }
}

@MainActor
private final class CellPreparationRecord {
  weak var run: AnyObject?
  init(_ run: AnyObject) { self.run = run }
}

private struct PreparedCellEffectModifier<K: CellPreparedLayerKernel>:
  IterativePrimitiveViewModifier
{
  let kernel: K
  let offset: CellSampleOffset
  let enabled: Bool

  func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>, in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    var next = context
    next.cellPreparationOrdinal += 1
    let key = CellPreparationSite(
      identity: context.identity, position: context.cellPreparationOrdinal)
    let run: CellPreparationRun<K>?
    if let owner = ValueGateRecords.owner(in: context), let graph = context.viewGraph {
      let ordinal = StateSlotOrdinals.preparedCellEffects
      typealias Runs = [CellPreparationSite: CellPreparationRecord]
      var runs: Runs = [:]
      if let slot = owner.stateSlotStorage(ordinal: ordinal), slot.stores(Runs.self) {
        runs = slot.value(as: Runs.self)
      }
      if enabled, let active = runs[key]?.run as? CellPreparationRun<K>,
        ValueGateRecords.isLive(key.identity, owner: owner, in: graph)
      {
        run = active
      } else {
        // The visual owns the run, so a surviving flattened parent cannot keep
        // a removed view's offscreen history alive.
        runs = runs.filter { $0.value.run != nil }
        run = enabled ? CellPreparationRun<K>(at: key) : nil
        runs[key] = run.map(CellPreparationRecord.init)
        owner.setStateSlotSilently(ordinal: ordinal, value: runs)
      }
    } else {
      run = enabled ? CellPreparationRun<K>(at: key) : nil
    }
    return content.resolveWork(in: next).map { completed in
      var node = completed
      if let run {
        node.drawEffects.append(
          .cellLayer(.init(.init(preparing: kernel, run: run), offset: offset)))
      }
      return [node]
    }
  }
}

// Issued-proposal record assembly (plan 2026-08-11-006 Stage 0).
//
// Records are assembled at FINISH sites from state each finish already
// holds — never per request — so the measure hot path pays nothing beyond
// what plan 004's counters already established, and the re-entry-live
// frames gain only call staging (the -Onone lesson: every inline
// temporary in the work-stack spine is a per-nesting-level stack cost).

extension LayoutEngine {
  /// The default record set: one final-round proposal per child, read from
  /// the child products themselves. Complete for every single-round
  /// container (forwarding behaviors, decoration, safe-area insets, the
  /// custom pre-measure round); multi-round containers pass explicit
  /// records instead. Custom containers additionally merge the author
  /// probes recorded on the pass context's probe frame.
  func resolvedIssuedProposalRecords(
    for resolved: ResolvedNode,
    childMeasurements: [MeasuredNode],
    explicit: [ChildIssuedProposalRecord]?,
    passContext: LayoutPassContext?
  ) -> [ChildIssuedProposalRecord]? {
    // Lazy stacks store no child measurements, and windowed products are
    // outside the records' consumers until plan 006 Stage 2.
    if case .lazyStack = resolved.layoutBehavior {
      return nil
    }
    guard !childMeasurements.isEmpty else {
      return nil
    }
    var records =
      explicit
      ?? childMeasurements.map { child in
        ChildIssuedProposalRecord(identity: child.identity, proposals: [child.proposal])
      }
    if case .custom = resolved.layoutBehavior,
      let probes = passContext?.currentIssuedProposalProbes(),
      !probes.isEmpty
    {
      for index in records.indices {
        guard let probed = probes[records[index].identity] else {
          continue
        }
        for proposal in probed {
          records[index].record(proposal)
        }
      }
    }
    return records
  }

  /// Stack records: the shared ideal-round proposal plus each child's
  /// final-round proposal (the allocation offer, or the ideal itself on
  /// the ideal-only path).
  func stackIssuedProposalRecords(
    children: [ResolvedNode],
    axis: Axis,
    effectiveProposal: ProposedSize,
    finalMeasurements: [MeasuredNode]
  ) -> [ChildIssuedProposalRecord] {
    let idealProposal = stackProposal(
      axis: axis,
      main: .unspecified,
      cross: crossDimension(of: effectiveProposal, for: axis)
    )
    return zip(children, finalMeasurements).map { child, final in
      var record = ChildIssuedProposalRecord(
        identity: child.identity,
        proposals: [idealProposal]
      )
      record.record(final.proposal)
      return record
    }
  }

  /// Reconciliation records: ideal, the pre-reconciliation round each
  /// child answered, and the reconciliation proposal for replaced
  /// children.
  func stackReconciliationIssuedProposalRecords(
    children: [ResolvedNode],
    axis: Axis,
    effectiveProposal: ProposedSize,
    preReconciliationMeasurements: [MeasuredNode],
    replacementIndices: [Int],
    replacements: [MeasuredNode]
  ) -> [ChildIssuedProposalRecord] {
    var records = stackIssuedProposalRecords(
      children: children,
      axis: axis,
      effectiveProposal: effectiveProposal,
      finalMeasurements: preReconciliationMeasurements
    )
    for (index, replacement) in zip(replacementIndices, replacements)
    where records.indices.contains(index) {
      records[index].record(replacement.proposal)
    }
    return records
  }

  /// ViewThatFits records: every child answered the real proposal; the
  /// probed prefix (through the selected or last child) also answered the
  /// relaxed fit probe.
  func viewThatFitsIssuedProposalRecords(
    children: [ResolvedNode],
    effectiveProposal: ProposedSize,
    axes: AxisSet,
    probedThrough probeIndex: Int
  ) -> [ChildIssuedProposalRecord] {
    let fitProbe = proposalByRelaxingAxes(effectiveProposal, axes: axes)
    return children.enumerated().map { index, child in
      var record = ChildIssuedProposalRecord(
        identity: child.identity,
        proposals: [effectiveProposal]
      )
      if index <= probeIndex {
        record.record(fitProbe)
      }
      return record
    }
  }
}

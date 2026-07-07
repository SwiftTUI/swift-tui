/// Sequential SwiftUI-parity stack main-axis allocation.
///
/// Children are offered space one at a time: priority groups descending
/// (children in lower-priority groups are guaranteed only their
/// structural minimums), and within a group in increasing estimated
/// flexibility so rigid children respond first and flexible children
/// absorb what remains. Every offer is re-measured and the child's
/// actual response feeds back into the remaining budget, so max caps,
/// `.fixedSize` subtrees, and estimate misses never strand space. A
/// trailing run of unbounded children within a group (Spacers, shapes,
/// `.infinity` frames — all of which size exactly to finite proposals)
/// is allocated in one balanced batch so remainder cells spread
/// symmetrically, matching the historical `Spacer` distribution.
struct StackSequentialAllocationPlan {
  /// Child indices in allocation order: priority descending, then
  /// estimated flexibility ascending, then source order.
  var order: [Int]
  /// Structural minimum main sizes, indexed by child.
  var minimums: [Int]
  /// Estimated maximum main sizes, indexed by child; `nil` = unbounded.
  var maximums: [Int?]
  /// Ideal-pass main sizes, indexed by child.
  var ideals: [Int]
  /// For each order position, the position one past the end of its
  /// priority group.
  var groupEndPositions: [Int]
  /// For each order position, the summed minimums of every child in
  /// lower-priority groups — space the current group must leave behind.
  var reservedLowerMinimums: [Int]
  /// For each order position, the summed ideal sizes of it and every
  /// later member of its priority group. While the available budget
  /// covers this, the group is in surplus and no member yields below
  /// its ideal (measure-time truncation makes under-offers lossy, so
  /// equal division must not undercut rigid children only to hand the
  /// slack to a more flexible sibling).
  var groupIdealSuffixes: [Int]
  /// For each order position, whether it and every later member of its
  /// group are unbounded (eligible for balanced batch allocation).
  var unboundedTailFromPosition: [Bool]
}

struct StackSequentialAllocationState {
  var plan: StackSequentialAllocationPlan
  /// Next order position to offer space to.
  var position: Int
  /// Main-axis cells not yet consumed by processed children.
  var remainingMain: Int
  /// Offered main sizes, indexed by child. Spacers commit to this value
  /// (their own measurement never absorbs the offer).
  var allocatedMainSizes: [Int]
  /// Collected allocation-pass measurements, indexed by child.
  var measurements: [MeasuredNode?]
}

extension LayoutEngine {
  func makeStackAllocationPlan(
    children: [ResolvedNode],
    idealMeasurements: [MeasuredNode],
    axis: Axis
  ) -> StackSequentialAllocationPlan {
    let minimums = children.indices.map {
      minimumMainSize(
        for: children[$0],
        idealMeasurement: idealMeasurements[$0],
        axis: axis
      )
    }
    let maximums = children.indices.map {
      derivedMaximumMainSize(
        for: children[$0],
        idealMeasurement: idealMeasurements[$0],
        axis: axis
      )
    }
    let ideals = idealMeasurements.map {
      mainDimension(of: $0.measuredSize, for: axis)
    }
    let flexibilities: [Int?] = children.indices.map { index in
      maximums[index].map { max(0, $0 - minimums[index]) }
    }

    let order = children.indices.sorted { lhs, rhs in
      let leftPriority = children[lhs].layoutMetadata.layoutPriority
      let rightPriority = children[rhs].layoutMetadata.layoutPriority
      if leftPriority != rightPriority {
        return leftPriority > rightPriority
      }
      switch (flexibilities[lhs], flexibilities[rhs]) {
      case (.some(let left), .some(let right)) where left != right:
        return left < right
      case (.some, .none):
        return true
      case (.none, .some):
        return false
      default:
        return lhs < rhs
      }
    }

    var groupEndPositions = [Int](repeating: order.count, count: order.count)
    var groupStart = 0
    while groupStart < order.count {
      let priority = children[order[groupStart]].layoutMetadata.layoutPriority
      var groupEnd = groupStart
      while groupEnd < order.count,
        children[order[groupEnd]].layoutMetadata.layoutPriority == priority
      {
        groupEnd += 1
      }
      for position in groupStart..<groupEnd {
        groupEndPositions[position] = groupEnd
      }
      groupStart = groupEnd
    }

    var suffixMinimums = [Int](repeating: 0, count: order.count + 1)
    for position in order.indices.reversed() {
      suffixMinimums[position] = suffixMinimums[position + 1] + minimums[order[position]]
    }
    let reservedLowerMinimums = order.indices.map {
      suffixMinimums[groupEndPositions[$0]]
    }

    var suffixIdeals = [Int](repeating: 0, count: order.count + 1)
    for position in order.indices.reversed() {
      suffixIdeals[position] = suffixIdeals[position + 1] + ideals[order[position]]
    }
    let groupIdealSuffixes = order.indices.map {
      suffixIdeals[$0] - suffixIdeals[groupEndPositions[$0]]
    }

    var unboundedTailFromPosition = [Bool](repeating: false, count: order.count)
    for position in order.indices.reversed() {
      guard maximums[order[position]] == nil else {
        continue
      }
      let next = position + 1
      unboundedTailFromPosition[position] =
        next == groupEndPositions[position] || unboundedTailFromPosition[next]
    }

    return StackSequentialAllocationPlan(
      order: order,
      minimums: minimums,
      maximums: maximums,
      ideals: ideals,
      groupEndPositions: groupEndPositions,
      reservedLowerMinimums: reservedLowerMinimums,
      groupIdealSuffixes: groupIdealSuffixes,
      unboundedTailFromPosition: unboundedTailFromPosition
    )
  }

  /// Advances the sequential allocation: finishes the stack when every
  /// child has been offered space, batch-allocates a trailing unbounded
  /// run, or offers the next child its share and schedules its
  /// measurement followed by a `.stackAllocateStep` continuation.
  func continueStackAllocation(
    _ node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    state: StackSequentialAllocationState,
    passContext: LayoutPassContext?,
    work: inout [MeasurementWorkItem],
    results: inout [MeasuredNode]
  ) {
    var state = state
    let plan = state.plan

    guard state.position < plan.order.count else {
      completeStackAllocation(
        node,
        originalProposal: originalProposal,
        effectiveProposal: effectiveProposal,
        children: children,
        axis: axis,
        state: state,
        passContext: passContext,
        work: &work,
        results: &results
      )
      return
    }

    let position = state.position
    let cross = crossDimension(of: effectiveProposal, for: axis)
    let available = max(0, state.remainingMain - plan.reservedLowerMinimums[position])

    if plan.unboundedTailFromPosition[position] {
      let run = position..<plan.groupEndPositions[position]
      let runChildIndices = run.map { plan.order[$0] }
      let runIdealTotal = runChildIndices.reduce(0) { $0 + plan.ideals[$1] }
      let targets: [Int]
      if available >= runIdealTotal {
        // Surplus: equal division from zero (SwiftUI's treatment of
        // unbounded children), floored at each member's ideal so a
        // content-bearing member is never undercut just to hand cells
        // to a Spacer.
        targets = surplusBatchTargets(
          available: available,
          floors: runChildIndices.map { max(plan.minimums[$0], plan.ideals[$0]) }
        )
      } else {
        // Deficit: compress from ideals in proportion to what each
        // member can give up, so trailing Spacers collapse before
        // content (a ScrollView panel) loses rows.
        targets = deficitBatchTargets(
          available: available,
          ideals: runChildIndices.map { plan.ideals[$0] },
          minimums: runChildIndices.map { plan.minimums[$0] }
        )
      }

      // Unbounded children size exactly to their offer, so consumption
      // is known at scheduling time; the batch finish item only merges
      // measurements.
      var consumed = 0
      for (offset, runPosition) in run.enumerated() {
        let childIndex = plan.order[runPosition]
        state.allocatedMainSizes[childIndex] = targets[offset]
        consumed += targets[offset]
      }
      state.remainingMain = max(0, state.remainingMain - consumed)
      state.position = run.upperBound

      work.append(
        .finishStackAllocationBatch(
          node,
          originalProposal: originalProposal,
          effectiveProposal: effectiveProposal,
          children: children,
          axis: axis,
          state: state,
          batchPositions: run
        )
      )
      for runPosition in run.reversed() {
        let childIndex = plan.order[runPosition]
        work.append(
          .measure(
            children[childIndex],
            stackProposal(
              axis: axis,
              main: .finite(state.allocatedMainSizes[childIndex]),
              cross: cross
            )
          )
        )
      }
      return
    }

    let childIndex = plan.order[position]
    let groupCountLeft = plan.groupEndPositions[position] - position
    // Round-half-up division: plain floor division would concentrate a
    // deficit's rounding loss on the earliest children (e.g. 4 cells
    // over 5 children offers the first child 0), while rounding keeps
    // per-step offers balanced; the response feedback absorbs any
    // cumulative drift on later children.
    let share = (2 * available + groupCountLeft) / (2 * groupCountLeft)
    // In surplus, no group member yields below its ideal: unlike
    // SwiftUI (where text responds larger than a lean offer), measure
    // here truncates, so an equal-division offer below a rigid child's
    // ideal would lose content only to hand the slack to a more
    // flexible sibling.
    let floorSize =
      available >= plan.groupIdealSuffixes[position]
      ? max(plan.minimums[childIndex], plan.ideals[childIndex])
      : plan.minimums[childIndex]
    var offer = max(share, floorSize)
    if let cap = plan.maximums[childIndex] {
      offer = min(offer, cap)
    }
    state.allocatedMainSizes[childIndex] = offer

    work.append(
      .stackAllocateStep(
        node,
        originalProposal: originalProposal,
        effectiveProposal: effectiveProposal,
        children: children,
        axis: axis,
        state: state
      )
    )
    work.append(
      .measure(
        children[childIndex],
        stackProposal(axis: axis, main: .finite(offer), cross: cross)
      )
    )
  }

  func completeStackAllocation(
    _ node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    state: StackSequentialAllocationState,
    passContext: LayoutPassContext?,
    work: inout [MeasurementWorkItem],
    results: inout [MeasuredNode]
  ) {
    var allocatedMeasurements = state.measurements.compactMap { $0 }
    precondition(
      allocatedMeasurements.count == children.count,
      "stack allocation completed with missing child measurements"
    )

    for index in children.indices where isSpacer(children[index]) {
      allocatedMeasurements[index].measuredSize = settingMainDimension(
        of: allocatedMeasurements[index].measuredSize,
        for: axis,
        to: state.allocatedMainSizes[index]
      )
    }

    guard case .unspecified = crossDimension(of: effectiveProposal, for: axis) else {
      results.append(
        makeMeasuredNode(
          for: node,
          originalProposal: originalProposal,
          effectiveProposal: effectiveProposal,
          childMeasurements: allocatedMeasurements,
          selectedChildIndex: nil,
          passContext: passContext
        )
      )
      return
    }

    scheduleStackCrossReconciliation(
      node,
      originalProposal: originalProposal,
      effectiveProposal: effectiveProposal,
      children: children,
      axis: axis,
      measurements: allocatedMeasurements,
      passContext: passContext,
      work: &work,
      results: &results
    )
  }

  /// Equal division of `available` with balanced remainder placement,
  /// where no member drops below its floor. Members whose floor exceeds
  /// the equal share are pinned at their floor and the rest re-divide
  /// what remains (bounded fair share). Callers guarantee
  /// `available >= floors.reduce(0, +)`.
  private func surplusBatchTargets(
    available: Int,
    floors: [Int]
  ) -> [Int] {
    var targets = [Int?](repeating: nil, count: floors.count)

    while true {
      let freeOffsets = targets.indices.filter { targets[$0] == nil }
      guard !freeOffsets.isEmpty else {
        return targets.map { $0 ?? 0 }
      }
      let budget = available - targets.compactMap { $0 }.reduce(0, +)
      let base = budget / freeOffsets.count
      let pinned = freeOffsets.filter { floors[$0] > base }
      guard pinned.isEmpty else {
        for offset in pinned {
          targets[offset] = floors[offset]
        }
        continue
      }
      var shares = [Int](repeating: base, count: freeOffsets.count)
      for extra in evenlyDistributedOffsets(
        count: freeOffsets.count,
        picks: budget % freeOffsets.count
      ) {
        shares[extra] += 1
      }
      for (position, offset) in freeOffsets.enumerated() {
        targets[offset] = shares[position]
      }
      return targets.map { $0 ?? 0 }
    }
  }

  /// Compression from ideals in proportion to each member's give
  /// (ideal − minimum), with balanced remainder placement — the
  /// historical deficit distribution.
  private func deficitBatchTargets(
    available: Int,
    ideals: [Int],
    minimums: [Int]
  ) -> [Int] {
    let overflow = ideals.reduce(0, +) - available
    let compressibles = ideals.indices.map { max(0, ideals[$0] - minimums[$0]) }
    let totalCompressible = compressibles.reduce(0, +)

    guard overflow < totalCompressible else {
      return minimums
    }

    var reductions = [Int](repeating: 0, count: ideals.count)
    var distributed = 0
    for offset in ideals.indices {
      let reduction = (overflow * compressibles[offset]) / totalCompressible
      reductions[offset] = reduction
      distributed += reduction
    }

    let remainder = overflow - distributed
    if remainder > 0 {
      let eligibleOffsets = ideals.indices.filter {
        reductions[$0] < compressibles[$0]
      }
      for offset in evenlyDistributedOffsets(
        count: eligibleOffsets.count,
        picks: min(remainder, eligibleOffsets.count)
      ) {
        reductions[eligibleOffsets[offset]] += 1
      }
    }

    return ideals.indices.map {
      max(minimums[$0], ideals[$0] - reductions[$0])
    }
  }

  package func evenlyDistributedOffsets(
    count: Int,
    picks: Int
  ) -> [Int] {
    guard count > 0, picks > 0 else {
      return []
    }

    return (0..<picks).map { pick in
      ((pick * 2 + 1) * count) / (picks * 2)
    }
  }
}

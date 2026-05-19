extension LayoutEngine {
  /// Hands extra main-axis space to any children that can absorb it.
  ///
  /// `Spacer` is the dedicated "eat all the space" primitive, so when
  /// a row contains at least one Spacer the surplus goes there. When
  /// there's no Spacer, fall back to any non-Spacer child whose
  /// subtree exposes flexible content on the main axis — e.g. a
  /// `Button` whose label uses `.frame(maxWidth: .infinity)`. Without
  /// this second fallback, a lone "submit"-style button on a row of
  /// fixed-width siblings (the classic calculator `=` key) would
  /// round out at its minWidth even though it's explicitly unbounded
  /// on the right, producing the "over-cascading min-size" symptom
  /// where the stack hands every child its smallest possible size
  /// and never redistributes the slack.
  package func distributeExtraSpaceToFlexibleChildren(
    _ children: [ResolvedNode],
    into allocatedMainSizes: inout [Int],
    axis: Axis,
    extraSpace: Int
  ) {
    guard extraSpace > 0 else {
      return
    }

    let spacerIndices = children.indices.filter { isSpacer(children[$0]) }
    let targetIndices: [Int]
    if !spacerIndices.isEmpty {
      targetIndices = spacerIndices
    } else {
      targetIndices = children.indices.filter { index in
        subtreeHasFlexibleContent(children[index], axis: axis)
      }
    }
    guard !targetIndices.isEmpty else {
      return
    }

    let baseShare = extraSpace / targetIndices.count
    let remainder = extraSpace % targetIndices.count

    for index in targetIndices {
      allocatedMainSizes[index] += baseShare
    }

    guard remainder > 0 else {
      return
    }

    for offset in evenlyDistributedOffsets(
      count: targetIndices.count,
      picks: remainder
    ) {
      allocatedMainSizes[targetIndices[offset]] += 1
    }
  }

  package func compressStackChildren(
    _ children: [ResolvedNode],
    idealMeasurements: [MeasuredNode],
    axis: Axis,
    allocatedMainSizes: inout [Int],
    overflow: Int
  ) {
    var remainingOverflow = overflow
    let priorities = Set(children.map { $0.layoutMetadata.layoutPriority }).sorted()

    for priority in priorities where remainingOverflow > 0 {
      let indices = children.indices.filter {
        children[$0].layoutMetadata.layoutPriority == priority
      }
      let minimumSizes = indices.map {
        minimumMainSize(for: children[$0], idealMeasurement: idealMeasurements[$0], axis: axis)
      }
      let compressibles = indices.enumerated().map { offset, index in
        max(0, allocatedMainSizes[index] - minimumSizes[offset])
      }
      let totalCompressible = compressibles.reduce(0, +)

      guard totalCompressible > 0 else {
        continue
      }

      if remainingOverflow >= totalCompressible {
        for (offset, index) in indices.enumerated() {
          allocatedMainSizes[index] = minimumSizes[offset]
        }
        remainingOverflow -= totalCompressible
        continue
      }

      var reductions = Array(repeating: 0, count: indices.count)
      var distributed = 0

      for offset in indices.indices {
        let reduction = (remainingOverflow * compressibles[offset]) / totalCompressible
        reductions[offset] = reduction
        distributed += reduction
      }

      let remainder = remainingOverflow - distributed
      if remainder > 0 {
        let eligibleOffsets = indices.indices.filter {
          reductions[$0] < compressibles[$0]
        }
        for offset in evenlyDistributedOffsets(
          count: eligibleOffsets.count,
          picks: min(remainder, eligibleOffsets.count)
        ) {
          reductions[eligibleOffsets[offset]] += 1
        }
      }

      for (offset, index) in indices.enumerated() {
        allocatedMainSizes[index] = max(
          minimumSizes[offset],
          allocatedMainSizes[index] - reductions[offset]
        )
      }

      remainingOverflow = 0
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

extension LayoutEngine {
  package func measuredListSize(
    for payload: ListPayload,
    proposal: ProposedSize
  ) -> Size {
    let idealSize = measuredListIdealSize(for: payload)

    return Size(
      width: resolvedExpandingListDimension(idealSize.width, proposal: proposal.width),
      height: resolvedExpandingListDimension(idealSize.height, proposal: proposal.height)
    )
  }

  package func measuredListIdealSize(
    for payload: ListPayload
  ) -> Size {
    payload.style.measuredListIdealSize(for: payload)
  }

  package func resolvedListDimension(
    _ ideal: Int,
    proposal: ProposedDimension
  ) -> Int {
    switch proposal {
    case .unspecified, .infinity:
      return ideal
    case .finite(let value):
      return min(max(ideal, 0), value)
    }
  }

  package func resolvedExpandingListDimension(
    _ ideal: Int,
    proposal: ProposedDimension
  ) -> Int {
    switch proposal {
    case .unspecified, .infinity:
      return ideal
    case .finite(let value):
      return max(0, value)
    }
  }

}

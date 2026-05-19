struct PlacementRequest {
  var resolved: ResolvedNode
  var measured: MeasuredNode
  var bounds: CellRect
}

enum PlacementWorkItem {
  case place(
    ResolvedNode,
    measured: MeasuredNode,
    bounds: CellRect,
    viewportContext: LazyStackViewportContext?
  )
  case finish(
    ResolvedNode,
    measured: MeasuredNode,
    bounds: CellRect,
    childCount: Int
  )
}

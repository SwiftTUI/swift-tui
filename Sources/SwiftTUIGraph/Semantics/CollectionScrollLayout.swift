/// Row geometry and the usable viewport from the same layout pass. The range
/// uses body display-line coordinates and excludes fixed chrome and indicators.
package struct CollectionScrollLayout: Equatable, Sendable {
  package let geometry: CollectionScrollGeometry
  package let visibleLines: Range<Int>
  package let anchor: CollectionScrollAnchor?

  package init(
    geometry: CollectionScrollGeometry,
    visibleLines: Range<Int>,
    anchor: CollectionScrollAnchor? = nil
  ) {
    self.geometry = geometry
    self.visibleLines = visibleLines
    self.anchor = anchor
  }
}

@_spi(Runners) package import SwiftTUIRuntime

package struct WebSurfaceFrameEncodingState: Sendable {
  package var deltaEnabled: Bool
  package var knownImageIDs: Set<String>
  package var persistentStyles: [ResolvedTextStyle?]
  package var hasBaseline: Bool
  package var baselineSize: CellSize?

  package init(
    deltaEnabled: Bool,
    knownImageIDs: Set<String> = [],
    persistentStyles: [ResolvedTextStyle?] = [nil],
    hasBaseline: Bool = false,
    baselineSize: CellSize? = nil
  ) {
    self.deltaEnabled = deltaEnabled
    self.knownImageIDs = knownImageIDs
    self.persistentStyles = persistentStyles.isEmpty ? [nil] : persistentStyles
    self.hasBaseline = hasBaseline
    self.baselineSize = baselineSize
  }
}

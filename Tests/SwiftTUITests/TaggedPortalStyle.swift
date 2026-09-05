import SwiftTUIViews

struct TaggedPortalStyle: PromptStyle, FullScreenCoverStyle, PopoverStyle, Equatable {
  let tag: String
  func resolvePresentation(for configuration: PromptStyleConfiguration)
    -> PromptSurfaceStylePresentation
  {
    configuration.defaultPresentation
  }
  func resolvePresentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  {
    configuration.defaultPresentation
  }
  func resolvePresentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    configuration.defaultPresentation
  }
  var snapshotLabel: String { tag }
}

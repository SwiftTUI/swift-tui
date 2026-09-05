import SwiftTUIViews

// This file is also typechecked separately using only the public Views module.
struct ConsumerPromptStyle: PromptStyle, Equatable {
  var inset: Int = 2
  var invalid = false
  func resolvePresentation(for configuration: PromptStyleConfiguration)
    -> PromptSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    presentation.contentInsets = .init(horizontal: inset, vertical: 1)
    presentation.backgroundStyle = AnyShapeStyle(.blue)
    presentation.borderStyle = AnyShapeStyle(.yellow)
    if invalid { presentation.scrollMaximumHeight = -1 }
    return presentation
  }
}

struct ConsumerFullScreenCoverStyle: FullScreenCoverStyle, Equatable {
  var inset: Int = 2
  func resolvePresentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    presentation.contentInsets = .init(horizontal: inset, vertical: inset)
    presentation.backgroundStyle = AnyShapeStyle(.blue)
    return presentation
  }
}

struct ConsumerPopoverStyle: PopoverStyle, Equatable {
  var inset: Int = 2
  var invalid = false
  func resolvePresentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    presentation.contentInsets = .init(horizontal: inset, vertical: 1)
    presentation.backgroundStyle = AnyShapeStyle(.blue)
    presentation.borderStyle = AnyShapeStyle(.yellow)
    if invalid { presentation.maximumHeight = 0 }
    return presentation
  }
}

struct ConsumerPortalSheetStyle: SheetStyle, Equatable {
  var dropdown = false
  var invalid = false
  func resolvePresentation(for configuration: SheetStyleConfiguration)
    -> SheetSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    presentation.container = dropdown ? .dropdown : .standard
    presentation.contentInsets = .init(horizontal: 2, vertical: 1)
    presentation.backgroundStyle = AnyShapeStyle(.blue)
    presentation.borderStyle = AnyShapeStyle(.yellow)
    if invalid { presentation.backdropOpacity = .nan }
    return presentation
  }
}

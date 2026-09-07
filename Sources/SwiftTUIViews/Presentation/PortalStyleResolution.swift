import SwiftTUICore

/// The environment a portal style resolves against, captured when the
/// declaring modifier resolves.
///
/// The modifier reads its style eagerly, so a closed declaration stays
/// dependent on the nearest style value and a later opening uses the current
/// one. The style call and its validation wait until the surface presents:
/// a closed declaration renders nothing, so it has nothing to fall back to
/// and reports nothing. Every portal family resolves through this one seam,
/// which is also where the validate-and-fall-back rule lives once.
package struct PortalStyleResolveInputs: Sendable {
  package var terminalSize: CellSize
  package var controlProminence: ControlProminence
  package var styleEnvironment: StyleEnvironmentSnapshot
  package var identity: Identity

  @MainActor
  package init(_ context: ResolveContext) {
    terminalSize = context.environmentValues.terminalSize
    controlProminence = context.environmentValues.controlProminence
    styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    identity = context.identity
  }

  @MainActor
  package func resolvedSheetPresentation(
    style: AnySheetStyle, baseline: SheetSurfaceStylePresentation
  ) -> SheetSurfaceStylePresentation {
    validated(family: "SheetStyle", style: style, baseline: baseline) {
      style.presentation(
        for: .init(
          defaultPresentation: baseline, terminalSize: terminalSize,
          controlProminence: controlProminence, styleEnvironment: styleEnvironment))
    }
  }

  @MainActor
  package func resolvedPromptPresentation(
    style: AnyPromptStyle, baseline: PromptSurfaceStylePresentation,
    hasMessage: Bool, hasActions: Bool
  ) -> PromptSurfaceStylePresentation {
    validated(family: "PromptStyle", style: style, baseline: baseline) {
      style.presentation(
        for: .init(
          hasMessage: hasMessage, hasActions: hasActions, defaultPresentation: baseline,
          terminalSize: terminalSize, controlProminence: controlProminence,
          styleEnvironment: styleEnvironment))
    }
  }

  @MainActor
  package func resolvedFullScreenCoverPresentation(
    style: AnyFullScreenCoverStyle, baseline: FullScreenSurfaceStylePresentation
  ) -> FullScreenSurfaceStylePresentation {
    validated(family: "FullScreenCoverStyle", style: style, baseline: baseline) {
      style.presentation(
        for: .init(
          defaultPresentation: baseline, terminalSize: terminalSize,
          controlProminence: controlProminence, styleEnvironment: styleEnvironment))
    }
  }

  @MainActor
  package func resolvedPopoverPresentation(
    style: AnyPopoverStyle
  ) -> AnchoredSurfaceStylePresentation {
    let baseline = AnchoredSurfaceStylePresentation.popoverBaseline
    return validated(family: "PopoverStyle", style: style, baseline: baseline) {
      style.presentation(
        for: .init(
          defaultPresentation: baseline, terminalSize: terminalSize,
          controlProminence: controlProminence, styleEnvironment: styleEnvironment))
    }
  }

  /// The rule every portal family shares: an invalid presentation reports
  /// once through the misuse channel and the declaration's baseline renders
  /// for this resolve.
  @MainActor
  private func validated<Presentation: PortalStylePresentation>(
    family: String, style: some CustomStringConvertible, baseline: Presentation,
    resolve: () -> Presentation
  ) -> Presentation {
    let resolved = resolve()
    return StyleMisuse.validatedPresentation(
      resolved, problems: resolved.validationProblems, family: family,
      styleLabel: style.description, identity: identity,
      report: ImperativeRuntimeIssueQueue.record, fallback: { baseline })
  }
}

/// A portal presentation value that can report why it is invalid.
package protocol PortalStylePresentation: Sendable {
  var validationProblems: [String] { get }
}

extension SheetSurfaceStylePresentation: PortalStylePresentation {}
extension PromptSurfaceStylePresentation: PortalStylePresentation {}
extension FullScreenSurfaceStylePresentation: PortalStylePresentation {}
extension AnchoredSurfaceStylePresentation: PortalStylePresentation {}

extension AnchoredSurfaceStylePresentation {
  /// Popovers keep their rounded stroke; Menu's shared value has its own baseline.
  package static var popoverBaseline: Self { .init(borderStroke: StrokeStyle()) }
}

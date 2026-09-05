import SwiftTUICore

package struct HostedPromptPresentation: View {
  package var item: PromptPresentationItem

  package init(
    item: PromptPresentationItem
  ) {
    self.item = item
  }

  package var body: some View {
    ZStack(alignment: .topLeading) {
      if item.descriptor.backdropOpacity > 0 {
        Rectangle()
          .fill(.background.opacity(item.descriptor.backdropOpacity))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      sizedSurface
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: item.descriptor.alignment
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var sizedSurface: some View {
    switch item.descriptor.surfaceMode {
    case .fullScreen:
      PromptPresentationSurface(item: item)
    case .standard:
      let surface = PromptPresentationSurface(item: item)
        .padding(insetEdges)

      switch item.descriptor.contentSizing {
      case .fillAvailable:
        surface
      case .intrinsic:
        surface.fixedSize(horizontal: true, vertical: true)
      }
    }
  }

  // Dropdown chrome lands flush against the window edges; surface
  // chrome floats with a 1-cell inset so the stroked box never kisses
  // the terminal edge.
  private var insetEdges: EdgeInsets {
    switch item.descriptor.chrome {
    case .surface:
      .init(top: 1, leading: 1, bottom: 1, trailing: 1)
    case .dropdown:
      .init(top: 0, leading: 0, bottom: 0, trailing: 0)
    // Menu chrome supplies its own padding around its bordered box;
    // the host applies a small leading/top inset so the box doesn't
    // kiss the terminal edge when the menu opens at top-leading.
    case .menu:
      .init(top: 0, leading: 1, bottom: 0, trailing: 0)
    }
  }
}

/// The root view of a presented sheet/alert/confirmation-dialog
/// subtree.
///
/// `PromptPresentationSurface` is the presented content root: when a
/// `.sheet(...)`, `.alert(...)`, or `.confirmationDialog(...)` is
/// active, this view appears as the root of that presentation's
/// subtree in the rendered tree, wrapped in the presentation host
/// overlay. Its resolved node carries `focusScopeBoundary: true` via
/// the `.focusScope()` modifier applied in its body, so every focus
/// region emitted underneath a presentation carries the
/// presentation's identity on its `scopePath`.
///
/// Conforming to `ActionScope` makes the presentation a first-class
/// scope in the `ActionScope` world: commands scoped to the
/// presentation become active exactly when the presentation's scope
/// identity is on the focus chain.
package struct PromptPresentationSurface: View, ActionScope {
  package typealias ID = String

  package var item: PromptPresentationItem

  package init(
    item: PromptPresentationItem
  ) {
    self.item = item
  }

  /// The presentation's identity is the item's attachment id — a
  /// stable `String` derived from the source identity and the
  /// presentation token (see `presentationAttachmentID`).
  package nonisolated var id: String {
    item.id
  }

  package var body: some View {
    switch item.descriptor.surfaceMode {
    case .fullScreen:
      fullScreenContentBody
    case .standard:
      standardSurface
    }
  }

  @ViewBuilder
  private var standardSurface: some View {
    let content = VStack(alignment: .leading, spacing: 0) {
      presentationHeader
      switch item.descriptor.bodyMode {
      case .contentOnly:
        contentBody
      case .messageAndActions:
        messageAndActionBody
      }
    }
    .padding(.init(horizontal: 1, vertical: 1))

    // Each container is its own primitive surface rather than a branch of
    // one catch-all body. `.standard` and `.dropdown` are what `SheetStyle`
    // selects between; MenuStyle supplies the anchored surface presentation.
    switch item.descriptor.chrome {
    case .surface:
      StandardContentPortalSurface(
        content: content,
        borderStyle: item.descriptor.borderStyle,
        minimumWidth: item.descriptor.minWidth,
        maximumWidth: maximumWidth,
        semanticMetadata: presentationSemanticMetadata
      )
    case .menu:
      AnchoredContentPortalSurface(
        content: menuContentBody,
        presentation: item.descriptor.anchoredPresentation ?? .init(),
        semanticMetadata: presentationSemanticMetadata
      )
    case .dropdown:
      DropdownContentPortalSurface(
        content: contentBody,
        semanticMetadata: presentationSemanticMetadata
      )
    }
  }

  private var fullScreenContentBody: some View {
    PortalAttachmentGroupView(
      kindName: "PresentationContent",
      payloads: item.contentPayloads
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background {
      Rectangle().fill(.terminalSurfaceBackground)
    }
    .semanticMetadata(presentationSemanticMetadata)
  }

  private var maximumWidth: ProposedDimension {
    if let maxWidth = item.descriptor.maxWidth {
      return .finite(maxWidth)
    }
    return .infinity
  }

  private var presentationSemanticMetadata: SemanticMetadata {
    var metadata = SemanticMetadata(
      accessibilityRole: item.descriptor.accessibilityRole
    )
    if item.descriptor.createsFocusScope {
      metadata = metadata.merging(focusStructureMetadata(scopeBoundary: true))
    }
    return metadata
  }

  private var presentationHeader: some View {
    HStack(alignment: .center, spacing: 1) {
      if !item.title.isEmpty {
        Text(item.title)
          .bold()
      }
      Spacer(minLength: 0)
      Button("×", role: .close, action: item.dismiss)
        .buttonStyle(.borderedProminent)
    }
    .frame(height: 1, alignment: .leading)
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(item.descriptor.headerTone, isSelected: true))
  }

  private var messageAndActionBody: some View {
    Group {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          if !item.messagePayloads.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              PortalAttachmentGroupView(
                kindName: "PresentationMessage",
                payloads: item.messagePayloads
              )
            }
            .padding(.init(horizontal: 1, vertical: 1))
          }
        }
      }
      .frame(
        maxWidth: .infinity,
        minHeight: .finite(item.descriptor.scrollMinHeight),
        idealHeight: .finite(item.descriptor.scrollIdealHeight),
        maxHeight: .finite(item.descriptor.scrollMaxHeight),
        alignment: .topLeading
      )
      presentationActions
    }
  }

  private var contentBody: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        PortalAttachmentGroupView(
          kindName: "PresentationContent",
          payloads: item.contentPayloads
        )
      }
      .padding(.init(horizontal: 1, vertical: 1))
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(item.descriptor.scrollMinHeight),
      idealHeight: .finite(item.descriptor.scrollIdealHeight),
      maxHeight: .finite(item.descriptor.scrollMaxHeight),
      alignment: .topLeading
    )
  }

  /// Menu declarations expand into a VStack of independent items. The anchored
  /// surface applies the style's optional viewport cap around this content;
  /// short menus retain their intrinsic height.
  ///
  /// Expands payloads through a transparent sequence rather than an indexed
  /// `ForEach`. The sequence gives the VStack separate children to lay out
  /// vertically while preserving declaration-side entity identity when the
  /// payloads themselves came from a `ForEach`.
  private var menuContentBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      PortalAttachmentSequenceView(payloads: item.contentPayloads)
    }
  }

  private var presentationActions: some View {
    HStack(spacing: 1) {
      PortalAttachmentSequenceView(
        payloads: item.actionPayloads,
        fixedSizeChildren: true
      )
    }
    .fixedSize()
    .padding(.init(horizontal: 1, vertical: 0))
  }
}

/// The centered, bordered sheet surface — the treatment
/// `SheetSurfaceContainer.standard` selects.
private struct StandardContentPortalSurface<Content: View>: View {
  let content: Content
  let borderStyle: StrokeStyle
  let minimumWidth: Int
  let maximumWidth: ProposedDimension
  let semanticMetadata: SemanticMetadata

  var body: some View {
    content
      .background {
        Rectangle().fill(.terminalSurfaceBackground)
      }
      .overlay {
        Rectangle().strokeBorder(
          .terminalBorder(.accent),
          style: borderStyle,
          background: .terminalSurfaceBackground
        )
      }
      .frame(
        minWidth: .finite(minimumWidth),
        maxWidth: maximumWidth,
        alignment: .leading
      )
      .semanticMetadata(semanticMetadata)
  }
}

/// The flat, edge-to-edge strip with a soft divider beneath it — the
/// treatment `SheetSurfaceContainer.dropdown` selects, and what the palette
/// declaration presents into.
private struct DropdownContentPortalSurface<Content: View>: View {
  let content: Content
  let semanticMetadata: SemanticMetadata

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background {
        Rectangle().fill(.terminalSurfaceBackground)
      }
      .overlay(alignment: .bottom) {
        Divider()
          .foregroundStyle(.separator)
          .drawMetadata(.init(opacity: 0.6))
          .frame(maxWidth: .infinity, alignment: .bottom)
      }
      .semanticMetadata(semanticMetadata)
  }
}

/// The anchored surface shared by menu and popover presentation values.
private struct AnchoredContentPortalSurface<Content: View>: View {
  let content: Content
  let presentation: AnchoredSurfaceStylePresentation
  let semanticMetadata: SemanticMetadata

  var body: some View {
    sizedContent
      .background {
        Rectangle().fill(presentation.backgroundStyle)
      }
      .overlay {
        Rectangle().strokeBorder(
          presentation.borderStyle ?? AnyShapeStyle(.terminalBorder(.accent)),
          style: presentation.borderStroke
        )
      }
      .semanticMetadata(semanticMetadata)
  }

  @ViewBuilder private var sizedContent: some View {
    if presentation.minimumWidth > 0 || presentation.maximumWidth != nil {
      AnchoredWidthLayout(minimum: presentation.minimumWidth, maximum: presentation.maximumWidth) {
        viewport.padding(presentation.contentInsets)
      }
    } else {
      viewport.padding(presentation.contentInsets)
    }
  }

  @ViewBuilder private var viewport: some View {
    if presentation.maximumHeight == .max {
      content
    } else {
      AnchoredViewportLayout(maximumHeight: presentation.maximumHeight) {
        ScrollView(.vertical) { content }.focusable(false)
      }
    }
  }
}

/// Width bounds clamp intrinsic content rather than replacing its ideal size.
/// Chrome is applied outside this layout so it covers the constrained surface.
private struct AnchoredWidthLayout: Layout {
  let minimum: Int
  let maximum: Int?

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    guard let child = subviews.first else { return .zero }
    let ideal = child.sizeThatFits(proposal)
    let width = min(max(minimum, ideal.width), maximum ?? .max)
    guard width != ideal.width else { return ideal }
    let resized = child.sizeThatFits(.init(width: .finite(width), height: proposal.height))
    return .init(width: width, height: resized.height)
  }

  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize,
    subviews: LayoutSubviews, cache: inout Void
  ) {
    subviews.first?.place(
      at: bounds.origin, anchor: .topLeading,
      proposal: .init(width: bounds.size.width, height: bounds.size.height))
  }
}

/// Measures the scrolling content at its intrinsic height before capping the
/// viewport. This avoids reserving the cap for short menus, and resolves the
/// authored content exactly once regardless of whether it needs scrolling.
private struct AnchoredViewportLayout: Layout {
  let maximumHeight: Int

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    guard let child = subviews.first else { return .zero }
    let ideal = child.sizeThatFits(.init(width: proposal.width, height: .unspecified))
    return .init(width: ideal.width, height: min(ideal.height, maximumHeight))
  }

  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize,
    subviews: LayoutSubviews, cache: inout Void
  ) {
    subviews.first?.place(
      at: bounds.origin, anchor: .topLeading,
      proposal: .init(width: bounds.size.width, height: bounds.size.height))
  }
}

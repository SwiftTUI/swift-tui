import SwiftTUICore

// Fixed portal surfaces share placement and paint helpers, not a kind switch.

/// A placement host. The declaring modifier has already selected a typed
/// surface; the host does not interpret a presentation kind or body mode.
package struct HostedPromptPresentation: View {
  package var item: PromptPresentationItem

  package var body: some View {
    ZStack(alignment: .topLeading) {
      if item.surface.backdropOpacity > 0 {
        Rectangle()
          .fill(.background.opacity(item.surface.backdropOpacity))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      PortalSurfaceRoot(item: item)
        .padding(item.surface.hostInsets)
        .fixedSize(horizontal: item.surface.isIntrinsic, vertical: item.surface.isIntrinsic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.surface.alignment)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Keeps the presentation's action scope independent of its visual surface.
package struct PortalSurfaceRoot: View, ActionScope {
  package var item: PromptPresentationItem
  package nonisolated var id: String { item.id }
  package var body: some View { PortalSurfaceContents(item: item) }
}

private struct PortalSurfaceContents: PrimitiveView, ResolvableView {
  let item: PromptPresentationItem
  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [item.surface.resolve(item, in: context)]
  }
}

/// Alert and confirmation-dialog message/action structure.
struct PromptActionPortalSurface: View {
  let item: PromptPresentationItem
  let presentation: PromptSurfaceStylePresentation

  var body: some View {
    BorderedPortalSurface(
      content: VStack(alignment: .leading, spacing: 0) {
        PortalHeader(title: item.title, dismiss: item.dismiss, tone: presentation.headerTone)
        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: 0) {
            if !item.messagePayloads.isEmpty {
              VStack(alignment: .leading, spacing: 0) {
                PortalAttachmentGroupView(
                  kindName: "PresentationMessage", payloads: item.messagePayloads)
              }
              .padding(.init(horizontal: 1, vertical: 1))
            }
          }
        }
        .frame(
          maxWidth: .infinity,
          minHeight: .finite(presentation.scrollMinimumHeight),
          idealHeight: .finite(presentation.scrollIdealHeight),
          maxHeight: .finite(presentation.scrollMaximumHeight),
          alignment: .topLeading)
        HStack(spacing: 1) {
          PortalAttachmentSequenceView(payloads: item.actionPayloads, fixedSizeChildren: true)
        }
        .fixedSize()
        .padding(.init(horizontal: 1, vertical: 0))
      }.padding(presentation.contentInsets),
      backgroundStyle: presentation.backgroundStyle,
      borderStroke: presentation.borderStroke,
      borderStyle: presentation.borderStyle,
      minimumWidth: presentation.minimumWidth,
      maximumWidth: presentation.maximumWidth
    )
    .semanticMetadata(item.surface.semanticMetadata)
  }
}

/// A standard sheet owns its header and scrolling content structure.
struct StandardContentPortalSurface: View {
  let item: PromptPresentationItem
  let presentation: SheetSurfaceStylePresentation

  var body: some View {
    BorderedPortalSurface(
      content: VStack(alignment: .leading, spacing: 0) {
        PortalHeader(title: item.title, dismiss: item.dismiss, tone: presentation.headerTone)
        PortalScrollingContent(
          payloads: item.contentPayloads,
          minimumHeight: presentation.scrollMinimumHeight,
          idealHeight: presentation.scrollIdealHeight,
          maximumHeight: presentation.scrollMaximumHeight,
          contentInsets: .init(horizontal: 1, vertical: 1))
      }.padding(presentation.contentInsets),
      backgroundStyle: presentation.backgroundStyle,
      borderStroke: presentation.borderStroke,
      borderStyle: presentation.borderStyle,
      minimumWidth: presentation.minimumWidth,
      maximumWidth: presentation.maximumWidth
    )
    .semanticMetadata(item.surface.semanticMetadata)
  }
}

/// The full-width dropdown shared by sheets and the command palette.
struct DropdownContentPortalSurface: View {
  let item: PromptPresentationItem
  let presentation: SheetSurfaceStylePresentation

  var body: some View {
    PortalScrollingContent(
      payloads: item.contentPayloads,
      minimumHeight: presentation.scrollMinimumHeight,
      idealHeight: presentation.scrollIdealHeight,
      maximumHeight: presentation.scrollMaximumHeight,
      contentInsets: presentation.contentInsets
    )
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background {
      Rectangle().fill(presentation.backgroundStyle ?? AnyShapeStyle(.terminalSurfaceBackground))
    }
    .overlay(alignment: .bottom) {
      Divider()
        .foregroundStyle(presentation.borderStyle ?? AnyShapeStyle(.separator))
        .drawMetadata(.init(opacity: 0.6))
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
    .semanticMetadata(item.surface.semanticMetadata)
  }
}

/// A cover always fills the host and has no framework header or border.
struct FullScreenContentPortalSurface: View {
  let item: PromptPresentationItem
  let presentation: FullScreenSurfaceStylePresentation

  var body: some View {
    PortalAttachmentGroupView(kindName: "PresentationContent", payloads: item.contentPayloads)
      .padding(presentation.contentInsets)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background { Rectangle().fill(presentation.backgroundStyle) }
      .semanticMetadata(item.surface.semanticMetadata)
  }
}

private struct PortalHeader: View {
  let title: String
  let dismiss: @MainActor @Sendable () -> Void
  let tone: TerminalTone

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      if !title.isEmpty { Text(title).bold() }
      Spacer(minLength: 0)
      Button("×", role: .close, action: dismiss).buttonStyle(.borderedProminent)
    }
    .frame(height: 1, alignment: .leading)
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(tone, isSelected: true))
  }
}

private struct PortalScrollingContent: View {
  let payloads: [PortalAttachmentPayload]
  let minimumHeight: Int
  let idealHeight: Int
  let maximumHeight: Int
  let contentInsets: EdgeInsets

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        PortalAttachmentGroupView(kindName: "PresentationContent", payloads: payloads)
      }
      .padding(contentInsets)
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(minimumHeight),
      idealHeight: .finite(idealHeight),
      maxHeight: .finite(maximumHeight),
      alignment: .topLeading)
  }
}

/// Shared paint and width mechanics; structure belongs to each fixed surface.
private struct BorderedPortalSurface<Content: View>: View {
  let content: Content
  let backgroundStyle: AnyShapeStyle?
  let borderStroke: StrokeStyle
  let borderStyle: AnyShapeStyle?
  let minimumWidth: Int
  let maximumWidth: Int?

  var body: some View {
    content
      .background { Rectangle().fill(backgroundStyle ?? AnyShapeStyle(.terminalSurfaceBackground)) }
      .overlay {
        Rectangle().strokeBorder(
          borderStyle ?? AnyShapeStyle(.terminalBorder(.accent)),
          style: borderStroke,
          background: backgroundStyle ?? AnyShapeStyle(.terminalSurfaceBackground))
      }
      .frame(
        minWidth: .finite(minimumWidth),
        maxWidth: maximumWidth.map(ProposedDimension.finite) ?? .infinity,
        alignment: .leading)
  }
}

/// The anchored surface shared by menu and popover presentation values.
struct AnchoredContentPortalSurface<Content: View>: View {
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

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
    let surface = PromptPresentationSurface(item: item)
      .padding(insetEdges)

    switch item.descriptor.contentSizing {
    case .fillAvailable:
      surface
    case .intrinsic:
      surface.fixedSize(horizontal: true, vertical: true)
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

    switch item.descriptor.chrome {
    case .surface:
      content
        .background {
          RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(.terminalSurfaceBackground)
        }
        .overlay {
          // .outset: chrome reserves layout space (frame grows). The rasterizer's
          // interior-fill sampling for presentation chrome is a separate
          // glyph-identity check, not a placement check.
          RoundedRectangle(cornerRadius: 1).strokeBorder(
            .terminalBorder(.accent),
            style: item.descriptor.borderStyle
          )
        }
        .frame(
          minWidth: .finite(item.descriptor.minWidth),
          maxWidth: maximumWidth,
          alignment: .leading
        )
        .semanticMetadata(
          presentationSemanticMetadata
        )
    case .menu:
      // Menu chrome: compact, intrinsic-width bordered box. No header
      // row (the trigger that opened it stays in place behind the
      // overlay), no close button (Escape dismisses), no max-width cap
      // (the menu sizes to its longest item).
      menuContentBody
        .padding(.init(horizontal: 1, vertical: 1))
        .background {
          Rectangle().fill(.terminalSurfaceBackground)
        }
        .overlay {
          Rectangle().strokeBorder(
            .terminalBorder(.accent),
            style: item.descriptor.borderStyle
          )
        }
        .semanticMetadata(
          presentationSemanticMetadata
        )
    case .dropdown:
      // Full-width, top-aligned strip. Dropdowns are command-palette-style
      // surfaces: no title row or close button, just the supplied content.
      contentBody
        .frame(
          maxWidth: .infinity,
          alignment: .topLeading
        )
        .background {
          Rectangle().fill(.terminalSurfaceBackground)
        }
        .overlay(alignment: .bottom) {
          Divider()
            .foregroundStyle(.separator)
            .drawMetadata(.init(opacity: 0.6))
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .semanticMetadata(
          presentationSemanticMetadata
        )
    }
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
              PortalPayloadGroupView(
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
        PortalPayloadGroupView(
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

  /// Menu rendering body — intrinsic-sized VStack of items with no
  /// scrolling chrome. The menu sizes to its longest item; the
  /// `scrollMaxHeight` from the descriptor is ignored intentionally so
  /// short menus don't reserve extra empty rows below their last item.
  ///
  /// Iterates payloads via `ForEach` + per-item `PortalPayloadView`
  /// rather than `PortalPayloadGroupView`. The group view returns a
  /// single intrinsic-layout node when there are multiple payloads,
  /// which would let menu items overlap in one row. Iterating gives
  /// the VStack its own children to lay out vertically.
  private var menuContentBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(item.contentPayloads.indices, id: \.self) { index in
        PortalPayloadView(payload: item.contentPayloads[index])
      }
    }
  }

  private var presentationActions: some View {
    HStack(spacing: 1) {
      ForEach(item.actionPayloads.indices, id: \.self) { index in
        PortalPayloadView(payload: item.actionPayloads[index])
          .fixedSize()
      }
    }
    .fixedSize()
    .padding(.init(horizontal: 1, vertical: 0))
  }
}

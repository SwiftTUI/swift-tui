public import Core

extension View {
  /// Attaches an auto-derived help strip to this subtree.
  ///
  /// The strip reads commands from the subtree's ``CommandPreferenceKey``
  /// reduction (plus any scene-level commands declared via
  /// ``Scene/commands(_:)``), filters to only the commands that declare
  /// a ``KeyPress`` binding, dedupes by ``Command/id`` with innermost
  /// wins, and renders each surviving entry as a `[key] title` token.
  ///
  /// Tokens are separated by a dim `" • "` divider. When the strip
  /// would exceed the proposed width, trailing tokens are dropped and
  /// replaced with an ellipsis.
  ///
  /// The modifier must be applied at or above the level where commands
  /// are declared. Preferences flow bottom-up, so a help strip placed
  /// *above* a `.command(...)` modifier will not see it. Scene-level
  /// commands authored via ``Scene/commands(_:)`` flow downward through
  /// an environment value, so they are visible to a `.help()` that
  /// lives inside the scene's content even when scene injection
  /// resolves outside the content subtree.
  ///
  /// Commands without a key binding are not shown in the strip — they
  /// have no glyph to render — but remain discoverable in the command
  /// palette and help sheet.
  ///
  /// - Parameters:
  ///   - style: How the strip attaches to its host. Only
  ///     ``HelpStripStyle/bottomBar`` is fully implemented in v1;
  ///     the other cases silently fall back to the bottom-bar layout.
  ///   - overflow: What to do when tokens exceed available width.
  ///     Only ``HelpStripOverflow/truncate`` is fully implemented in
  ///     v1; the other cases silently fall back to truncation.
  public func help(
    _ style: HelpStripStyle = .bottomBar,
    overflow: HelpStripOverflow = .truncate
  ) -> some View {
    HelpStripModifier(
      content: self,
      style: style,
      overflow: overflow
    )
  }
}

// MARK: - Dedup

/// Returns the innermost-wins deduped list of keyed commands in the
/// order they were declared, merging view-level and scene-level sources.
///
/// The rules, pinned by ``HelpStripDedupTests``:
///
/// * Scene-level registrations (outermost authoring site) appear
///   *after* the view-level registrations in the merged flat list, so
///   first-occurrence dedup keeps the innermost entry.
/// * Only commands that declare a key are considered for the strip;
///   keyless commands are palette-only. Filtering happens *before*
///   dedup so a keyless override does not shadow a keyed parent.
/// * Two distinct `id`s with the same key are both kept. Disambiguation
///   is the author's problem.
///
/// Package-visible so tests can exercise the pure-function path without
/// going through view rendering.
package func helpStripDedupedRegistrations(
  viewLevel: [CommandRegistration],
  sceneLevel: [CommandRegistration]
) -> [CommandRegistration] {
  let merged = viewLevel + sceneLevel
  var seenIDs: Set<String> = []
  var deduped: [CommandRegistration] = []
  deduped.reserveCapacity(merged.count)
  for registration in merged {
    guard registration.command.key != nil else {
      continue
    }
    let (inserted, _) = seenIDs.insert(registration.command.id)
    guard inserted else {
      continue
    }
    deduped.append(registration)
  }
  return deduped
}

// MARK: - Modifier

/// The resolve-time wrapper that reads the command preference value and
/// the scene-commands environment, builds a deferred help-strip view,
/// and attaches it to the content with a decoration-style overlay.
package struct HelpStripModifier<Content: View>: View, ResolvableView {
  package var content: Content
  package var style: HelpStripStyle
  package var overflow: HelpStripOverflow
  private let authoringScope: AuthoringContext?

  package init(
    content: Content,
    style: HelpStripStyle,
    overflow: HelpStripOverflow
  ) {
    self.content = content
    self.style = style
    self.overflow = overflow
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let capturedAuthoringScope = authoringScope

    // Stage 4: the help strip cooperates with the toolbar host
    // composition. If this modifier is nested inside an outer
    // toolbar host composer (signalled by
    // ``EnvironmentValues/isInsideToolbarHost``), it publishes a
    // ``HelpStripRequestPreferenceKey`` entry and returns the
    // content unchanged — the outer composer will merge the help
    // strip's tokens into its own bottom row.
    if context.environmentValues.isInsideToolbarHost {
      var node = content.resolve(in: context)
      node.preferenceValues.merge(
        HelpStripRequestPreferenceKey.self,
        value: HelpStripRequestPreferenceValue(
          style: style,
          overflow: overflow,
          isRequested: true
        )
      )
      return [node]
    }

    // Outermost-composer path: resolve the base once to read the
    // reduced preference value, then construct the strip view from
    // the combined view-level + scene-level registrations, and hand
    // the whole thing to a VStack-based layout so the bottom row is
    // *reserved* for the strip rather than overdrawn on top of the
    // content.
    //
    // The base is resolved a second time when the VStack walks its
    // children; that's intentional — the resolved tree the layout
    // engine consumes is produced by the VStack composition below,
    // and the first `baseNode` here is discarded after its preference
    // value has been read. A future pass could dedupe the double-
    // resolve by caching, but for v1 clarity wins over one redundant
    // traversal.
    let baseContext =
      context
      .settingEnvironment(\.isInsideToolbarHost, to: true)
      .child(component: .named("base"))
    let baseNode = content.resolve(in: baseContext)

    let viewLevelRegistrations =
      baseNode.preferenceValues[CommandPreferenceKey.self].registrations
    let sceneLevelRegistrations = context.environmentValues.sceneCommandRegistrations

    // Stage 4: read any toolbar records an inner `.toolbar { }` may
    // have contributed, so the outermost `.help()` can compose a
    // combined bottom row.
    let toolbarRecords =
      baseNode.preferenceValues[ToolbarItemsPreferenceKey.self].records

    let proposedWidth = context.environmentValues.terminalSize.width

    // v1 fallback: every ``HelpStripStyle`` renders as `.bottomBar`.
    // Unused parameters are captured in the modifier so authors can
    // declare intent today; Stage 3.1 will differentiate layouts.
    let resolvedStyle = style
    let resolvedOverflow = overflow

    /// AnyView policy: erasure is required to avoid parameterizing the whole file.
    let bottomRow: AnyView
    if toolbarRecords.isEmpty {
      // No toolbar items: the help strip is the entire bottom row,
      // same as Stage 3. Preserve the existing shape for backward
      // compatibility with Stage 3 tests and layouts.
      let tokens = helpStripTokens(
        from: helpStripDedupedRegistrations(
          viewLevel: viewLevelRegistrations,
          sceneLevel: sceneLevelRegistrations
        )
      )
      let stripView = HelpStripView(
        tokens: tokens,
        proposedWidth: proposedWidth,
        authoringScope: capturedAuthoringScope
      )
      bottomRow = scopedAnyView(authoringContext: capturedAuthoringScope) {
        stripView
      }
    } else {
      // Inner `.toolbar { }` items exist: compose a joint bottom row
      // using the shared ``toolbarHostBottomRow(…)`` builder so the
      // strip sits in the same row as the toolbar items.
      let request = HelpStripRequestPreferenceValue(
        style: resolvedStyle,
        overflow: resolvedOverflow,
        isRequested: true
      )
      let row = toolbarHostBottomRow(
        records: toolbarRecords,
        helpRequest: request,
        viewLevelCommands: viewLevelRegistrations,
        sceneLevelCommands: sceneLevelRegistrations,
        proposedWidth: proposedWidth,
        authoringScope: capturedAuthoringScope
      )
      bottomRow = scopedAnyView(authoringContext: capturedAuthoringScope) {
        row
      }
    }

    _ = resolvedStyle
    _ = resolvedOverflow

    let composed = VStack(alignment: .leading, spacing: 0) {
      HelpStripContentHost(content: content)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      bottomRow
    }
    return [
      composed.resolve(
        in:
          context
          .settingEnvironment(\.isInsideToolbarHost, to: true)
          .child(component: .named("helpStripHost"))
      )
    ]
  }
}

/// A tiny pass-through wrapper around the help strip's primary content
/// so the VStack-based composition can give it a stable child identity.
///
/// The outer ``HelpStripModifier`` routes the user's view through this
/// wrapper and lets the normal resolve pipeline handle body / preference
/// reduction again — we already read the preference value once up front
/// to build the strip's token list, and the second resolve here is the
/// one whose ResolvedNode actually reaches the layout engine.
private struct HelpStripContentHost<Content: View>: View, ResolvableView {
  var content: Content

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [content.resolve(in: context)]
  }
}

// MARK: - Token building

/// A single `[key] title` token in the help strip, pre-flattened from a
/// ``CommandRegistration`` so the view layer can lay it out without
/// re-reading the command record.
package struct HelpStripToken: Equatable, Sendable {
  package var commandID: String
  package var key: KeyPress
  package var title: String
  package var isDisabled: Bool
}

package func helpStripTokens(
  from registrations: [CommandRegistration]
) -> [HelpStripToken] {
  registrations.compactMap { registration -> HelpStripToken? in
    guard let key = registration.command.key else {
      return nil
    }
    return HelpStripToken(
      commandID: registration.command.id,
      key: key,
      title: registration.command.title,
      isDisabled: registration.command.isDisabled
    )
  }
}

// MARK: - Truncation

/// Chooses how many tokens fit within `proposedWidth` by naively summing
/// the display length of each `[key] title` run plus the separator
/// between tokens. Returns the surviving prefix along with whether an
/// ellipsis is required.
///
/// The estimate is deliberately conservative — the goal is "fits in the
/// row without wrapping", not "every cell is perfectly packed." A more
/// sophisticated measurement-aware pass is a Stage 3.1 follow-up.
package func helpStripTruncation(
  tokens: [HelpStripToken],
  proposedWidth: Int
) -> (visible: [HelpStripToken], needsEllipsis: Bool) {
  guard proposedWidth > 0 else {
    return (tokens, false)
  }
  var usedWidth = 0
  var visible: [HelpStripToken] = []
  visible.reserveCapacity(tokens.count)
  let separatorWidth = 3  // " • "
  let ellipsisWidth = 1  // "…"
  for (index, token) in tokens.enumerated() {
    let glyph = keyDisplayString(for: token.key)
    let tokenWidth = glyph.count + 1 + token.title.count  // "[…] title"
    let separatorCost = visible.isEmpty ? 0 : separatorWidth
    let remainingAfter = usedWidth + separatorCost + tokenWidth
    let hasMore = index + 1 < tokens.count
    let ellipsisReserve = hasMore ? separatorWidth + ellipsisWidth : 0
    if remainingAfter + ellipsisReserve > proposedWidth {
      return (visible, needsEllipsis: true)
    }
    usedWidth = remainingAfter
    visible.append(token)
  }
  return (visible, false)
}

// MARK: - Strip view

/// The presentation-layer view that draws the help strip row. It is
/// decoupled from ``HelpStripModifier`` so the modifier can compose it
/// at resolve time and the rendered output can be inspected in tests
/// via either the ResolvedNode tree or the raster surface.
package struct HelpStripView: View {
  package var tokens: [HelpStripToken]
  package var proposedWidth: Int
  package var authoringScope: AuthoringContext?

  package init(
    tokens: [HelpStripToken],
    proposedWidth: Int,
    authoringScope: AuthoringContext?
  ) {
    self.tokens = tokens
    self.proposedWidth = proposedWidth
    self.authoringScope = authoringScope
  }

  package var body: some View {
    let (visible, needsEllipsis) = helpStripTruncation(
      tokens: tokens,
      proposedWidth: proposedWidth
    )
    HStack(alignment: .center, spacing: 0) {
      ForEach(visible.indices, id: \.self) { index in
        if index > 0 {
          Text(" • ")
            .foregroundStyle(.separator)
        }
        HelpStripTokenView(token: visible[index])
      }
      if needsEllipsis {
        Text(visible.isEmpty ? "…" : " …")
          .foregroundStyle(.separator)
      }
    }
  }
}

/// A single `[key] title` token rendered in the help strip.
///
/// The token wraps its key glyph in a ``PointerRouteView`` so that a
/// pointer click on the visible glyph dispatches the corresponding
/// ``KeyPress`` through the ``HotkeyRegistry``, reusing the same path
/// a physical key press would take.
package struct HelpStripTokenView: View, ResolvableView {
  package var token: HelpStripToken
  private let authoringScope: AuthoringContext?

  package init(token: HelpStripToken) {
    self.token = token
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let capturedAuthoringScope = authoringScope
    let capturedKey = token.key
    let glyphRouteIdentity = context.identity.child(
      .named("HelpStripGlyph")
    )
    let routeID = primaryRouteID(for: glyphRouteIdentity)

    if let hotkeyRegistry = context.hotkeyRegistry,
      let pointerRegistry = context.localPointerHandlerRegistry
    {
      pointerRegistry.register(routeID: routeID) { event in
        guard case .down(.primary) = event.kind else {
          return false
        }
        return withAuthoringContext(capturedAuthoringScope) {
          hotkeyRegistry.dispatch(capturedKey)
        }
      }
    }

    let content = HStack(alignment: .center, spacing: 1) {
      PointerRouteView(
        identity: glyphRouteIdentity,
        content: KeyGlyphView(token.key)
      )
      Text(token.title)
    }
    .drawMetadata(.init(opacity: token.isDisabled ? 0.6 : 1))

    let resolvedContent = withAuthoringContext(capturedAuthoringScope) {
      content.resolve(in: context.child(component: .named("content")))
    }
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("HelpStripToken"),
        children: [resolvedContent],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

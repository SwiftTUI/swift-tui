public import Core

// MARK: - Public API

extension View {
  /// Attaches a toolbar to the nearest enclosing toolbar host.
  ///
  /// Items declared inside `content` are flattened into a flat
  /// `[ToolbarItemRecord]` list, written into the package-internal
  /// ``ToolbarItemsPreferenceKey`` preference channel, and rendered in
  /// the toolbar host's reserved row.
  ///
  /// The default host is implicit at every ``WindowGroup`` root, so
  /// authors do not need to wrap their content in an explicit host to
  /// use the toolbar.
  ///
  /// When both ``View/toolbar(content:)`` and ``View/help(_:overflow:)``
  /// are applied to the same subtree, the outermost of the two owns
  /// the bottom-row composition (see ``ToolbarHostEnvironmentKey``).
  /// The inner modifier contributes its items via preference channels;
  /// the outer one reads the combined state and composes the VStack.
  public func toolbar<Content: ToolbarContent>(
    @ToolbarContentBuilder content: () -> Content
  ) -> some View {
    ToolbarModifier(content: self, toolbarContent: content())
  }

  /// Sets toolbar visibility for the named bar(s) on this subtree.
  ///
  /// v1 note: this modifier captures the authored intent into a
  /// package-internal preference channel, but the default toolbar host
  /// does not yet apply it at render time. Tracking as a Stage 5
  /// follow-up.
  public func toolbar(
    _ visibility: Visibility,
    for bars: ToolbarPlacement...
  ) -> some View {
    ToolbarVisibilityModifier(
      content: self,
      visibility: visibility,
      bars: bars
    )
  }

  /// Sets the background style for the named bar(s) on this subtree.
  ///
  /// v1 note: this modifier captures the authored intent into a
  /// package-internal preference channel, but the default toolbar host
  /// does not yet apply it at render time. Tracking as a Stage 5
  /// follow-up.
  public func toolbarBackground<S: ShapeStyle>(
    _ style: S,
    for bars: ToolbarPlacement...
  ) -> some View {
    ToolbarBackgroundModifier(
      content: self,
      style: style.eraseToAnyShapeStyle(),
      bars: bars
    )
  }
}

// MARK: - Record types

/// A single toolbar item flattened from a ``ToolbarContent`` tree and
/// ready for rendering by a host.
///
/// Records are the concrete value type the package-internal
/// ``ToolbarItemsPreferenceKey`` carries. Using a concrete record type
/// rather than existential `any ToolbarContent` lets us dedupe, sort,
/// and layout items without re-traversing the authored builder tree.
package struct ToolbarItemRecord: Sendable {
  /// What shape this record takes in the bottom-row layout.
  package enum Shape: Sendable {
    /// A free-form or command-bound ``ToolbarItem`` that renders a
    /// view body. `hasCustomBody` is `true` when the author supplied
    /// a body closure explicitly, and `false` when the body is the
    /// placeholder from the Text-specialized command-bound overload.
    case item(body: AnyView, hasCustomBody: Bool)
    /// A ``ToolbarSpacer`` that claims flexible or fixed space.
    case spacer(sizing: ToolbarSpacer.Sizing)
  }

  package var placement: ToolbarItemPlacement
  package var shape: Shape
  /// The id of the registered command this record surfaces, if any.
  /// Non-nil only for command-bound ``ToolbarItem`` values.
  package var commandID: String?
  /// A stable authoring path used for dedupe and diagnostics. The host
  /// does not currently dedupe on this (v1), but records are kept in
  /// declaration order so resolution is deterministic.
  package var stableID: String

  package init(
    placement: ToolbarItemPlacement,
    shape: Shape,
    commandID: String? = nil,
    stableID: String
  ) {
    self.placement = placement
    self.shape = shape
    self.commandID = commandID
    self.stableID = stableID
  }
}

/// The reduced value the ``ToolbarItemsPreferenceKey`` carries up the
/// resolved tree.
package struct ToolbarItemsPreferenceValue: Sendable {
  package var records: [ToolbarItemRecord] = []

  package init(records: [ToolbarItemRecord] = []) {
    self.records = records
  }
}

/// Preference key carrying flattened ``ToolbarItemRecord`` values up
/// the resolved tree.
///
/// Toolbar items reduce innermost-first to match the convention used
/// by ``CommandPreferenceKey`` and the help strip — the innermost
/// ``View/toolbar(content:)`` modifier resolves first, and each outer
/// layer appends its own records on top.
package enum ToolbarItemsPreferenceKey: PreferenceKey {
  package static let defaultValue = ToolbarItemsPreferenceValue()

  package static func reduce(
    value: inout ToolbarItemsPreferenceValue,
    nextValue: () -> ToolbarItemsPreferenceValue
  ) {
    value.records.append(contentsOf: nextValue().records)
  }
}

// MARK: - Help-strip-request preference key

/// The reduced value the ``HelpStripRequestPreferenceKey`` carries up
/// the resolved tree.
///
/// When a subtree declares `.help(...)`, it writes its style and
/// overflow settings into this key so an outer toolbar host can
/// compose a single bottom row with both toolbar items and the help
/// strip. Innermost wins: only the innermost request is kept, since
/// nested help strips on the same subtree are pathological.
package struct HelpStripRequestPreferenceValue: Sendable {
  package var style: HelpStripStyle?
  package var overflow: HelpStripOverflow?
  package var isRequested: Bool

  package init(
    style: HelpStripStyle? = nil,
    overflow: HelpStripOverflow? = nil,
    isRequested: Bool = false
  ) {
    self.style = style
    self.overflow = overflow
    self.isRequested = isRequested
  }
}

package enum HelpStripRequestPreferenceKey: PreferenceKey {
  package static let defaultValue = HelpStripRequestPreferenceValue()

  package static func reduce(
    value: inout HelpStripRequestPreferenceValue,
    nextValue: () -> HelpStripRequestPreferenceValue
  ) {
    let next = nextValue()
    // Innermost wins: the first non-empty request reached during
    // reduction is the innermost one, and it should not be overwritten
    // by an outer declaration on the same subtree.
    guard next.isRequested else {
      return
    }
    if !value.isRequested {
      value = next
    }
  }
}

// MARK: - Toolbar visibility / background preferences (v1 capture-only)

package struct ToolbarVisibilityPreferenceValue: Sendable {
  package struct Entry: Sendable {
    package var bar: ToolbarPlacement
    package var visibility: Visibility
  }

  package var entries: [Entry] = []
}

package enum ToolbarVisibilityPreferenceKey: PreferenceKey {
  package static let defaultValue = ToolbarVisibilityPreferenceValue()

  package static func reduce(
    value: inout ToolbarVisibilityPreferenceValue,
    nextValue: () -> ToolbarVisibilityPreferenceValue
  ) {
    value.entries.append(contentsOf: nextValue().entries)
  }
}

package struct ToolbarBackgroundPreferenceValue: Sendable {
  package struct Entry: Sendable {
    package var bar: ToolbarPlacement
    package var style: AnyShapeStyle
  }

  package var entries: [Entry] = []
}

package enum ToolbarBackgroundPreferenceKey: PreferenceKey {
  package static let defaultValue = ToolbarBackgroundPreferenceValue()

  package static func reduce(
    value: inout ToolbarBackgroundPreferenceValue,
    nextValue: () -> ToolbarBackgroundPreferenceValue
  ) {
    value.entries.append(contentsOf: nextValue().entries)
  }
}

// MARK: - Toolbar host environment flag

/// Environment flag set to `true` on the subtree beneath the outermost
/// toolbar host composer (either ``ToolbarModifier`` or
/// ``HelpStripModifier``).
///
/// Nested ``View/toolbar(content:)`` and ``View/help(_:overflow:)``
/// modifiers check this flag. When it is `false`, the modifier
/// composes its own bottom-row VStack and sets the flag to `true` on
/// children. When it is `true`, the modifier only contributes to
/// preferences and returns its content unchanged — an outer layer
/// will compose the VStack reading the combined preference state.
package enum IsInsideToolbarHostKey: EnvironmentKey {
  package static let defaultValue: Bool = false
}

extension EnvironmentValues {
  package var isInsideToolbarHost: Bool {
    get { self[IsInsideToolbarHostKey.self] }
    set { self[IsInsideToolbarHostKey.self] = newValue }
  }
}

// MARK: - Flatten toolbar content into records

/// Walks a ``ToolbarContent`` tree and flattens it into a flat
/// `[ToolbarItemRecord]` list in declaration order.
///
/// Items and spacers are captured with type-erased `AnyView` bodies so
/// the outer preference channel can carry heterogeneous content
/// without leaking the authored generic types. `ToolbarItemGroup`
/// flattens through — all children inherit the group's placement only
/// when their own placement is ``ToolbarItemPlacement/automatic``.
@MainActor
package func flattenToolbarContent<C: ToolbarContent>(
  _ content: C,
  stableIDPrefix: String = "",
  inheritedPlacement: ToolbarItemPlacement? = nil,
  records: inout [ToolbarItemRecord]
) {
  let erased: Any = content

  if let empty = erased as? EmptyToolbarContent {
    _ = empty
    return
  }

  if let item = erased as? any AnyToolbarItemProtocol {
    let resolvedPlacement = resolvePlacement(
      declared: item.anyPlacement,
      inherited: inheritedPlacement
    )
    let stableID = "\(stableIDPrefix)item[\(records.count)]"
    records.append(
      ToolbarItemRecord(
        placement: resolvedPlacement,
        shape: .item(
          body: item.anyContent,
          hasCustomBody: item.anyHasCustomBody
        ),
        commandID: item.anyCommandID,
        stableID: stableID
      )
    )
    return
  }

  if let spacer = erased as? ToolbarSpacer {
    let resolvedPlacement = resolvePlacement(
      declared: spacer.placement,
      inherited: inheritedPlacement
    )
    let stableID = "\(stableIDPrefix)spacer[\(records.count)]"
    records.append(
      ToolbarItemRecord(
        placement: resolvedPlacement,
        shape: .spacer(sizing: spacer.sizing),
        commandID: nil,
        stableID: stableID
      )
    )
    return
  }

  if let group = erased as? any AnyToolbarItemGroupProtocol {
    group.flattenInto(
      stableIDPrefix: "\(stableIDPrefix)group/",
      inheritedPlacement: group.anyPlacement,
      records: &records
    )
    return
  }

  if let tuple = erased as? any AnyTupleToolbarContentProtocol {
    tuple.flattenInto(
      stableIDPrefix: stableIDPrefix,
      inheritedPlacement: inheritedPlacement,
      records: &records
    )
    return
  }

  if let optional = erased as? any AnyOptionalToolbarContentProtocol {
    optional.flattenInto(
      stableIDPrefix: "\(stableIDPrefix)if/",
      inheritedPlacement: inheritedPlacement,
      records: &records
    )
    return
  }

  if let conditional = erased as? any AnyConditionalToolbarContentProtocol {
    conditional.flattenInto(
      stableIDPrefix: "\(stableIDPrefix)cond/",
      inheritedPlacement: inheritedPlacement,
      records: &records
    )
    return
  }

  // User-defined `ToolbarContent` with a composed body. Descend into
  // the body as a fresh flatten pass.
  let mirrorID = "\(stableIDPrefix)body/"
  flattenToolbarContent(
    content.body,
    stableIDPrefix: mirrorID,
    inheritedPlacement: inheritedPlacement,
    records: &records
  )
}

private func resolvePlacement(
  declared: ToolbarItemPlacement,
  inherited: ToolbarItemPlacement?
) -> ToolbarItemPlacement {
  switch declared {
  case .automatic:
    return inherited ?? .automatic
  default:
    return declared
  }
}

// MARK: - Existential-shaped protocols for flatten dispatch

/// Existential-shaped protocol that lets ``flattenToolbarContent(_:…)``
/// operate on the erased ``ToolbarItem`` without binding to the
/// generic `Content` type parameter.
@MainActor
package protocol AnyToolbarItemProtocol {
  var anyPlacement: ToolbarItemPlacement { get }
  var anyCommandID: String? { get }
  var anyHasCustomBody: Bool { get }
  var anyContent: AnyView { get }
}

extension ToolbarItem: AnyToolbarItemProtocol {
  package var anyPlacement: ToolbarItemPlacement { placement }
  package var anyCommandID: String? { commandID }
  package var anyHasCustomBody: Bool { hasCustomBody }
  package var anyContent: AnyView {
    scopedAnyView { content }
  }
}

/// Existential-shaped protocol for flattening ``ToolbarItemGroup``.
@MainActor
package protocol AnyToolbarItemGroupProtocol {
  var anyPlacement: ToolbarItemPlacement { get }
  func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  )
}

extension ToolbarItemGroup: AnyToolbarItemGroupProtocol {
  package var anyPlacement: ToolbarItemPlacement { placement }

  package func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  ) {
    flattenToolbarContent(
      content,
      stableIDPrefix: stableIDPrefix,
      inheritedPlacement: inheritedPlacement,
      records: &records
    )
  }
}

/// Existential-shaped protocol for flattening ``TupleToolbarContent``.
@MainActor
package protocol AnyTupleToolbarContentProtocol {
  func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  )
}

extension TupleToolbarContent: AnyTupleToolbarContentProtocol {
  package func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  ) {
    var index = 0
    for child in repeat each value {
      flattenToolbarContent(
        child,
        stableIDPrefix: "\(stableIDPrefix)[\(index)]/",
        inheritedPlacement: inheritedPlacement,
        records: &records
      )
      index += 1
    }
  }
}

/// Existential-shaped protocol for flattening
/// ``OptionalToolbarContent``.
@MainActor
package protocol AnyOptionalToolbarContentProtocol {
  func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  )
}

extension OptionalToolbarContent: AnyOptionalToolbarContentProtocol {
  package func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  ) {
    guard let value else {
      return
    }
    flattenToolbarContent(
      value,
      stableIDPrefix: stableIDPrefix,
      inheritedPlacement: inheritedPlacement,
      records: &records
    )
  }
}

/// Existential-shaped protocol for flattening
/// ``ConditionalToolbarContent``.
@MainActor
package protocol AnyConditionalToolbarContentProtocol {
  func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  )
}

extension ConditionalToolbarContent: AnyConditionalToolbarContentProtocol {
  package func flattenInto(
    stableIDPrefix: String,
    inheritedPlacement: ToolbarItemPlacement?,
    records: inout [ToolbarItemRecord]
  ) {
    switch storage {
    case .trueContent(let content):
      flattenToolbarContent(
        content,
        stableIDPrefix: "\(stableIDPrefix)true/",
        inheritedPlacement: inheritedPlacement,
        records: &records
      )
    case .falseContent(let content):
      flattenToolbarContent(
        content,
        stableIDPrefix: "\(stableIDPrefix)false/",
        inheritedPlacement: inheritedPlacement,
        records: &records
      )
    }
  }
}

// MARK: - The ToolbarModifier

/// The view modifier produced by ``View/toolbar(content:)``.
///
/// Resolve-time behavior:
///
/// 1. Flatten the authored ``ToolbarContent`` tree into a flat
///    `[ToolbarItemRecord]` list.
/// 2. Resolve the base content once, so the reduced preference value
///    reaches the modifier with all nested toolbar items, help strip
///    requests, and command registrations already merged.
/// 3. If `environmentValues.isInsideToolbarHost == true`, this
///    modifier is nested under an outer composer. Merge its own items
///    into the preference value and return the content unchanged.
/// 4. Otherwise, compose a VStack with the content on top and the
///    toolbar host bottom row below, and set the environment flag to
///    `true` on children so inner copies of this modifier and
///    ``HelpStripModifier`` know an outer composer exists.
package struct ToolbarModifier<Content: View, TBContent: ToolbarContent>: View,
  ResolvableView
{
  package var content: Content
  package var toolbarContent: TBContent
  private let authoringScope: AuthoringContext?

  package init(
    content: Content,
    toolbarContent: TBContent
  ) {
    self.content = content
    self.toolbarContent = toolbarContent
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    // Flatten the authored items once, up front, so the same list can
    // be merged into preferences (for outer composers) and into the
    // bottom row (for the outermost composer here).
    var ownRecords: [ToolbarItemRecord] = []
    flattenToolbarContent(
      toolbarContent,
      stableIDPrefix: "",
      inheritedPlacement: nil,
      records: &ownRecords
    )

    let alreadyInsideHost = context.environmentValues.isInsideToolbarHost
    if alreadyInsideHost {
      return inner(
        in: context,
        ownRecords: ownRecords
      )
    }

    return outermost(
      in: context,
      ownRecords: ownRecords
    )
  }

  /// Inner-modifier path: only publish items to the preference channel
  /// and return the content unchanged. The outer composer will read
  /// the merged value when it resolves its own bottom row.
  private func inner(
    in context: ResolveContext,
    ownRecords: [ToolbarItemRecord]
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    if !ownRecords.isEmpty {
      node.preferenceValues.merge(
        ToolbarItemsPreferenceKey.self,
        value: ToolbarItemsPreferenceValue(records: ownRecords)
      )
    }
    return [node]
  }

  /// Outermost-composer path: set the environment flag on children,
  /// resolve once to read their preference values, merge this
  /// modifier's own records, and build the bottom row VStack.
  private func outermost(
    in context: ResolveContext,
    ownRecords: [ToolbarItemRecord]
  ) -> [ResolvedNode] {
    let capturedAuthoringScope = authoringScope

    // Resolve the base once to read the reduced preference values
    // from inner modifiers. The resolved node here is discarded
    // after inspection; the VStack's own resolve pass below
    // constructs the actual node the layout engine consumes.
    let baseContext =
      context
      .settingEnvironment(\.isInsideToolbarHost, to: true)
      .child(component: .named("baseProbe"))
    let baseNode = content.resolve(in: baseContext)

    let innerRecords =
      baseNode.preferenceValues[ToolbarItemsPreferenceKey.self].records
    let combinedRecords = innerRecords + ownRecords

    let helpRequest =
      baseNode.preferenceValues[HelpStripRequestPreferenceKey.self]

    let viewLevelCommandRegistrations =
      baseNode.preferenceValues[CommandPreferenceKey.self].registrations
    let sceneLevelCommandRegistrations =
      context.environmentValues.sceneCommandRegistrations

    let proposedWidth = context.environmentValues.terminalSize.width

    let bottomRow = toolbarHostBottomRow(
      records: combinedRecords,
      helpRequest: helpRequest,
      viewLevelCommands: viewLevelCommandRegistrations,
      sceneLevelCommands: sceneLevelCommandRegistrations,
      proposedWidth: proposedWidth,
      authoringScope: capturedAuthoringScope
    )

    let hostedContent = ToolbarHostContentWrapper(
      content: content,
      ownRecords: ownRecords
    )

    let composed = VStack(alignment: .leading, spacing: 0) {
      hostedContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      bottomRow
    }

    return [
      composed.resolve(
        in:
          context
          .settingEnvironment(\.isInsideToolbarHost, to: true)
          .child(component: .named("toolbarHost"))
      )
    ]
  }
}

/// A thin pass-through wrapper around the toolbar host's primary
/// content so the VStack composition can give it a stable child
/// identity and inject the host's own items into the preference
/// channel a second time (the outer composer already consumed them
/// when probing the base, but downstream readers of the final
/// resolved tree — the app graph, diagnostics — still expect them in
/// the preference value on the hosted node).
private struct ToolbarHostContentWrapper<Content: View>: View, ResolvableView {
  var content: Content
  var ownRecords: [ToolbarItemRecord]

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    if !ownRecords.isEmpty {
      node.preferenceValues.merge(
        ToolbarItemsPreferenceKey.self,
        value: ToolbarItemsPreferenceValue(records: ownRecords)
      )
    }
    return [node]
  }
}

// MARK: - Visibility & background modifiers (capture-only)

private struct ToolbarVisibilityModifier<Content: View>: View, ResolvableView {
  var content: Content
  var visibility: Visibility
  var bars: [ToolbarPlacement]

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let effectiveBars: [ToolbarPlacement] = bars.isEmpty ? [.automatic] : bars
    let entries = effectiveBars.map { bar in
      ToolbarVisibilityPreferenceValue.Entry(
        bar: bar,
        visibility: visibility
      )
    }
    node.preferenceValues.merge(
      ToolbarVisibilityPreferenceKey.self,
      value: ToolbarVisibilityPreferenceValue(entries: entries)
    )
    return [node]
  }
}

private struct ToolbarBackgroundModifier<Content: View>: View, ResolvableView {
  var content: Content
  var style: AnyShapeStyle
  var bars: [ToolbarPlacement]

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let effectiveBars: [ToolbarPlacement] = bars.isEmpty ? [.automatic] : bars
    let entries = effectiveBars.map { bar in
      ToolbarBackgroundPreferenceValue.Entry(
        bar: bar,
        style: style
      )
    }
    node.preferenceValues.merge(
      ToolbarBackgroundPreferenceKey.self,
      value: ToolbarBackgroundPreferenceValue(entries: entries)
    )
    return [node]
  }
}

// MARK: - Bottom row composition

/// Builds the view that occupies the toolbar host's reserved bottom
/// row.
///
/// The row is composed as a three-section `HStack`:
///
/// * left — status items and leading secondary actions
/// * center — help strip tokens (if requested) and secondary actions
/// * right — primary actions and trailing items
///
/// `confirmationAction`, `cancellationAction`, `destructiveAction`,
/// and `title` placements are no-ops in the default host — they only
/// apply to modal-specific or title-row hosts, which v1 does not yet
/// render.
@MainActor
package func toolbarHostBottomRow(
  records: [ToolbarItemRecord],
  helpRequest: HelpStripRequestPreferenceValue,
  viewLevelCommands: [CommandRegistration],
  sceneLevelCommands: [CommandRegistration],
  proposedWidth: Int,
  authoringScope: AuthoringContext?
) -> some View {
  let layout = classifyToolbarRecords(records)
  let tokens: [HelpStripToken]
  if helpRequest.isRequested {
    tokens = helpStripTokens(
      from: helpStripDedupedRegistrations(
        viewLevel: viewLevelCommands,
        sceneLevel: sceneLevelCommands
      )
    )
  } else {
    tokens = []
  }

  let commandLookup = buildCommandLookup(
    viewLevel: viewLevelCommands,
    sceneLevel: sceneLevelCommands
  )

  return ToolbarHostBottomRow(
    layout: layout,
    helpStripTokens: tokens,
    helpStripRequested: helpRequest.isRequested,
    proposedWidth: proposedWidth,
    commandLookup: commandLookup,
    authoringScope: authoringScope
  )
}

/// The classification of toolbar records into layout sections.
package struct ToolbarLayoutSections: Sendable {
  package var leading: [ToolbarItemRecord] = []
  package var center: [ToolbarItemRecord] = []
  package var trailing: [ToolbarItemRecord] = []
}

/// Sorts toolbar records into the three bottom-row sections by
/// placement.
///
/// * `.status` and leading items → leading
/// * `.secondaryAction` → center (alongside the help strip)
/// * `.primaryAction` → trailing
/// * `.automatic`, `.bottomBar` → leading by default
/// * modal-only placements and `.title` → dropped (the default host
///   does not render them)
package func classifyToolbarRecords(
  _ records: [ToolbarItemRecord]
) -> ToolbarLayoutSections {
  var sections = ToolbarLayoutSections()
  for record in records {
    switch record.placement {
    case .status:
      sections.leading.append(record)
    case .secondaryAction:
      sections.center.append(record)
    case .primaryAction:
      sections.trailing.append(record)
    case .automatic, .bottomBar:
      sections.leading.append(record)
    case .confirmationAction, .cancellationAction, .destructiveAction, .title:
      // No-op in the default host. Modal / title-row hosts are
      // tracked as Stage 5 follow-ups.
      continue
    }
  }
  return sections
}

/// Builds a lookup table from command id to the registered
/// ``Command`` value, merging view-level and scene-level sources with
/// innermost-wins precedence.
@MainActor
package func buildCommandLookup(
  viewLevel: [CommandRegistration],
  sceneLevel: [CommandRegistration]
) -> [String: Command] {
  var result: [String: Command] = [:]
  // View-level is innermost-first, so earlier entries win.
  for registration in viewLevel {
    if result[registration.command.id] == nil {
      result[registration.command.id] = registration.command
    }
  }
  for registration in sceneLevel {
    if result[registration.command.id] == nil {
      result[registration.command.id] = registration.command
    }
  }
  return result
}

// MARK: - Bottom row view

/// The presentation-layer view that renders the toolbar host's
/// reserved bottom row.
package struct ToolbarHostBottomRow: View {
  package var layout: ToolbarLayoutSections
  package var helpStripTokens: [HelpStripToken]
  package var helpStripRequested: Bool
  package var proposedWidth: Int
  package var commandLookup: [String: Command]
  package var authoringScope: AuthoringContext?

  package init(
    layout: ToolbarLayoutSections,
    helpStripTokens: [HelpStripToken],
    helpStripRequested: Bool,
    proposedWidth: Int,
    commandLookup: [String: Command],
    authoringScope: AuthoringContext?
  ) {
    self.layout = layout
    self.helpStripTokens = helpStripTokens
    self.helpStripRequested = helpStripRequested
    self.proposedWidth = proposedWidth
    self.commandLookup = commandLookup
    self.authoringScope = authoringScope
  }

  package var body: some View {
    HStack(alignment: .center, spacing: 0) {
      ToolbarSectionView(
        records: layout.leading,
        commandLookup: commandLookup,
        authoringScope: authoringScope
      )
      if !layout.leading.isEmpty
        && (!layout.center.isEmpty || helpStripRequested || !layout.trailing.isEmpty)
      {
        Text(" ")
      }
      ToolbarSectionView(
        records: layout.center,
        commandLookup: commandLookup,
        authoringScope: authoringScope
      )
      if helpStripRequested {
        if !layout.center.isEmpty {
          Text(" ")
        }
        HelpStripView(
          tokens: helpStripTokens,
          proposedWidth: proposedWidth,
          authoringScope: authoringScope
        )
      }
      Spacer(minLength: 0)
      ToolbarSectionView(
        records: layout.trailing,
        commandLookup: commandLookup,
        authoringScope: authoringScope
      )
    }
  }
}

/// Lays out the records inside a single toolbar section as a
/// space-separated `HStack` of per-record views.
package struct ToolbarSectionView: View {
  package var records: [ToolbarItemRecord]
  package var commandLookup: [String: Command]
  package var authoringScope: AuthoringContext?

  package init(
    records: [ToolbarItemRecord],
    commandLookup: [String: Command],
    authoringScope: AuthoringContext?
  ) {
    self.records = records
    self.commandLookup = commandLookup
    self.authoringScope = authoringScope
  }

  package var body: some View {
    HStack(alignment: .center, spacing: 1) {
      ForEach(records.indices, id: \.self) { index in
        ToolbarRecordView(
          record: records[index],
          commandLookup: commandLookup,
          authoringScope: authoringScope
        )
      }
    }
  }
}

/// Renders a single ``ToolbarItemRecord`` as either a free-form body,
/// a command-bound `[key] title` affordance, or a spacer.
///
/// Command-bound records consult `commandLookup`; unresolved ids are
/// silently omitted (rendered as ``EmptyView``). Resolved records with
/// a key render `[key] title`; resolved records without a key render
/// just the title.
package struct ToolbarRecordView: View {
  package var record: ToolbarItemRecord
  package var commandLookup: [String: Command]
  package var authoringScope: AuthoringContext?

  package init(
    record: ToolbarItemRecord,
    commandLookup: [String: Command],
    authoringScope: AuthoringContext?
  ) {
    self.record = record
    self.commandLookup = commandLookup
    self.authoringScope = authoringScope
  }

  public var body: some View {
    switch record.shape {
    case .item(let body, let hasCustomBody):
      if let commandID = record.commandID {
        if let command = commandLookup[commandID] {
          commandBoundView(
            command: command,
            customBody: hasCustomBody ? body : nil
          )
        } else {
          EmptyView()
        }
      } else {
        body
      }
    case .spacer(let sizing):
      switch sizing {
      case .flexible:
        Spacer(minLength: 0)
      case .fixed(let width):
        Spacer(minLength: width)
      }
    }
  }

  @ViewBuilder
  private func commandBoundView(
    command: Command,
    customBody: AnyView?
  ) -> some View {
    HStack(alignment: .center, spacing: 1) {
      if let key = command.key {
        KeyGlyphView(key)
      }
      if let customBody {
        customBody
      } else {
        Text(command.title)
      }
    }
    .drawMetadata(.init(opacity: command.isDisabled ? 0.6 : 1))
  }
}

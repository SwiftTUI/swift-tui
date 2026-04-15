public import Core

extension View {
  /// Attaches an expandable help sheet to this subtree, presented when
  /// the user presses `key`.
  ///
  /// The sheet reads the same ``CommandPreferenceKey`` reduction the
  /// help strip and command palette read, groups the surviving commands
  /// by ``Command/group`` — one section per non-nil group, plus a
  /// trailing "Other" section for ungrouped entries — and renders each
  /// row as `[key] Title` with a trailing detail string (if present).
  ///
  /// Escape dismisses the sheet. The trigger key defaults to `?` but
  /// can be customised for "space mode" and similar patterns.
  ///
  /// Scene-level commands declared via ``Scene/commands(_:)`` appear in
  /// the sheet alongside view-level commands, following the same
  /// innermost-wins dedup rule the strip uses.
  public func helpSheet(
    triggeredBy key: KeyPress = KeyPress(.character("?"))
  ) -> some View {
    HelpSheetModifier(
      content: self,
      triggerKey: key,
      externalIsPresented: nil
    )
  }

  /// Testing seam: attaches the help sheet with a caller-owned
  /// ``Binding<Bool>`` in place of the default internal presentation
  /// state.
  ///
  /// Declared `package` so integration tests can bypass the hotkey
  /// dispatch round-trip when verifying the sheet's rendered layout.
  /// Production authors should use ``View/helpSheet(triggeredBy:)``.
  package func _helpSheet(
    isPresented: Binding<Bool>,
    triggeredBy key: KeyPress = KeyPress(.character("?"))
  ) -> some View {
    HelpSheetModifier(
      content: self,
      triggerKey: key,
      externalIsPresented: isPresented
    )
  }
}

// MARK: - Grouping

package struct HelpSheetSection: Equatable, Sendable {
  package var title: String
  package var rows: [HelpSheetRow]
}

package struct HelpSheetRow: Equatable, Sendable {
  package var commandID: String
  package var title: String
  package var detail: String?
  package var key: KeyPress?
  package var isDisabled: Bool
  package var kindSymbol: String
}

/// Build the grouped section list the help sheet renders, applying the
/// same innermost-wins dedup the help strip uses.
///
/// Sections appear in the order in which their `group` name first shows
/// up in the deduped stream of surviving registrations; the trailing
/// "Other" section holds commands whose `group` is nil and is appended
/// last. Commands without a key are included in the sheet (unlike the
/// strip) — the sheet is a cheatsheet, and an unbound command is still
/// a useful reference entry.
///
/// Package-visible so tests can exercise the pure-function path.
package func helpSheetSections(
  viewLevel: [CommandRegistration],
  sceneLevel: [CommandRegistration]
) -> [HelpSheetSection] {
  // Flatten into innermost-first order, then first-wins dedup by id.
  // Unlike the strip, keyless commands are kept — the sheet is the
  // "every command, grouped" lens, not the "every bound shortcut" lens.
  let merged = viewLevel + sceneLevel
  var seenIDs: Set<String> = []
  var deduped: [Command] = []
  deduped.reserveCapacity(merged.count)
  for registration in merged {
    let (inserted, _) = seenIDs.insert(registration.command.id)
    guard inserted else {
      continue
    }
    deduped.append(registration.command)
  }

  var groupOrder: [String] = []
  var grouped: [String: [HelpSheetRow]] = [:]
  var otherRows: [HelpSheetRow] = []

  for command in deduped {
    let row = HelpSheetRow(
      commandID: command.id,
      title: command.title,
      detail: command.detail,
      key: command.key,
      isDisabled: command.isDisabled,
      kindSymbol: command.kind.symbol
    )
    if let group = command.group, !group.isEmpty {
      if grouped[group] == nil {
        groupOrder.append(group)
      }
      grouped[group, default: []].append(row)
    } else {
      otherRows.append(row)
    }
  }

  var sections: [HelpSheetSection] = []
  sections.reserveCapacity(groupOrder.count + 1)
  for group in groupOrder {
    sections.append(
      HelpSheetSection(
        title: group,
        rows: grouped[group] ?? []
      )
    )
  }
  if !otherRows.isEmpty {
    sections.append(
      HelpSheetSection(title: "Other", rows: otherRows)
    )
  }
  return sections
}

// MARK: - Modifier

/// A reference-type holder for the help sheet's `isPresented` flag.
///
/// Stored inside a ``@State`` slot on ``HelpSheetModifier`` so the same
/// instance persists across renders — the modifier struct itself is
/// re-constructed every render, but ``@State`` initializes this class
/// exactly once per view-node identity and re-uses that instance on
/// subsequent resolves.
///
/// Using a reference avoids the ``ResolvableView`` limitation where
/// directly setting a ``@State`` `Bool` from a hotkey handler goes
/// through the unbound-fallback path, and lets the handler explicitly
/// notify the view graph to re-evaluate the modifier after the flag
/// flips. The referenced ``Core/ViewNode`` is used so `requestInvalidation`
/// marks the owning graph dirty *and* calls any external invalidator —
/// whichever path the hosting runtime uses to trigger the next frame.
@MainActor
package final class HelpSheetPresentationState {
  package var isPresented: Bool = false
  weak var viewNode: Core.ViewNode?

  package init() {}

  package func toggle(to newValue: Bool) {
    guard isPresented != newValue else { return }
    isPresented = newValue
    viewNode?.requestInvalidation()
  }
}

private struct HelpSheetModifier<Content: View>: View, ResolvableView {
  var content: Content
  var triggerKey: KeyPress
  var externalIsPresented: Binding<Bool>?

  @State private var presentationState = HelpSheetPresentationState()

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)

    // ResolvableView bypasses the normal body-evaluation path that
    // installs an ``AuthoringContext``, so we install one manually to
    // pull the persistent ``HelpSheetPresentationState`` instance out
    // of the ``@State`` slot. Without this step, the @State would fall
    // through to the seed-value path and return a fresh (unbound)
    // instance on every render.
    let authoringContext = dynamicPropertyAuthoringContext(for: context)
    let localState: HelpSheetPresentationState = withAuthoringContext(
      authoringContext
    ) {
      presentationState
    }
    localState.viewNode = ViewNodeContext.current

    let getIsPresented: @MainActor @Sendable () -> Bool
    let setIsPresented: @MainActor @Sendable (Bool) -> Void
    if let externalIsPresented {
      getIsPresented = { externalIsPresented.wrappedValue }
      setIsPresented = { externalIsPresented.wrappedValue = $0 }
    } else {
      getIsPresented = { localState.isPresented }
      setIsPresented = { localState.toggle(to: $0) }
    }

    let currentIsPresented = getIsPresented()
    let localTriggerKey = triggerKey

    // Register the trigger hotkey whenever the sheet is currently
    // dismissed, so pressing the configured key toggles it into view.
    // Matches the command palette's trigger-registration shape at
    // Sources/View/Presentation/CommandPalette.swift:769-784.
    if !currentIsPresented {
      let binding = HotkeyBinding(key: localTriggerKey)
      context.hotkeyRegistry?.register(
        identity: context.identity,
        binding: binding
      ) { localKeyPress in
        guard localKeyPress == localTriggerKey else {
          return false
        }
        setIsPresented(true)
        return true
      }
    }

    guard currentIsPresented else {
      return [node]
    }

    let sourceIdentity = node.identity
    let viewLevelRegistrations =
      node.preferenceValues[CommandPreferenceKey.self].registrations
    let sceneLevelRegistrations = context.environmentValues.sceneCommandRegistrations
    let sections = helpSheetSections(
      viewLevel: viewLevelRegistrations,
      sceneLevel: sceneLevelRegistrations
    )

    let item = helpSheetPresentationItem(
      for: sections,
      sourceIdentity: sourceIdentity,
      setIsPresented: setIsPresented
    )
    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            registry.sheet.sync(
              sourceIdentity: sourceIdentity,
              items: [item]
            )
          }
        ]
      )
    )

    return [node]
  }

  private func helpSheetPresentationItem(
    for sections: [HelpSheetSection],
    sourceIdentity: Identity,
    setIsPresented: @escaping @MainActor @Sendable (Bool) -> Void
  ) -> PromptPresentationItem {
    let spec = sheetPromptPresentationSpec()
    let dismiss: @MainActor @Sendable () -> Void = {
      setIsPresented(false)
    }
    return PromptPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: "helpSheet"
      ),
      title: "Help",
      descriptor: spec.descriptor,
      actionPayloads: [],
      messagePayloads: [],
      contentPayloads: deferredDeclaredBuilderChildren(
        from: HelpSheetView(
          sections: sections,
          onDismiss: dismiss
        )
      ),
      dismiss: dismiss
    )
  }
}

// MARK: - View

/// The presentation-layer view rendered inside the help sheet's
/// content slot. Decoupled from ``HelpSheetModifier`` so test
/// harnesses can inspect the rendered output and so the modifier
/// stays small.
package struct HelpSheetView: View {
  package var sections: [HelpSheetSection]
  package var onDismiss: @MainActor @Sendable () -> Void

  package init(
    sections: [HelpSheetSection],
    onDismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.sections = sections
    self.onDismiss = onDismiss
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      ForEach(sections.indices, id: \.self) { sectionIndex in
        helpSheetSectionView(sections[sectionIndex])
      }
      Text("Press Esc to dismiss")
        .foregroundStyle(.separator)
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }

  @ViewBuilder
  private func helpSheetSectionView(
    _ section: HelpSheetSection
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(section.title)
        .bold()
      ForEach(section.rows.indices, id: \.self) { rowIndex in
        helpSheetRowView(section.rows[rowIndex])
      }
    }
  }

  @ViewBuilder
  private func helpSheetRowView(
    _ row: HelpSheetRow
  ) -> some View {
    HStack(alignment: .center, spacing: 1) {
      if let key = row.key {
        KeyGlyphView(key)
      } else {
        Text(row.kindSymbol)
          .foregroundStyle(.separator)
      }
      Text(row.title)
      Spacer(minLength: 0)
      if let detail = row.detail, !detail.isEmpty {
        Text(detail)
          .foregroundStyle(.separator)
      }
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .drawMetadata(.init(opacity: row.isDisabled ? 0.6 : 1))
  }
}

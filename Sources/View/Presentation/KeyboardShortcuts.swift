public import Core

// MARK: - Model

/// A keyboard shortcut registration that pairs a typed key combination with a
/// human-readable label.
public struct KeyboardShortcut: Hashable, Sendable, Identifiable {
  public var key: KeyEvent
  public var modifiers: EventModifiers
  public var label: String
  public var group: String?

  public var id: String {
    [
      formattedKeyboardShortcutKey(
        key,
        modifiers: modifiers
      ),
      label,
      group ?? "",
    ].joined(separator: "\u{001F}")
  }

  public init(
    _ key: KeyEvent,
    modifiers: EventModifiers = [],
    label: String,
    group: String? = nil
  ) {
    self.key = key
    self.modifiers = modifiers
    self.label = label
    self.group = group
  }
}

/// A cluster of related keyboard shortcuts with an optional title.
public struct KeyboardShortcutGroup: Hashable, Sendable, Identifiable {
  public var title: String?
  public var shortcuts: [KeyboardShortcut]

  public var id: String {
    [title ?? "", shortcuts.map(\.id).joined(separator: "|")].joined(
      separator: "\u{001F}"
    )
  }

  public init(
    _ title: String? = nil,
    shortcuts: [KeyboardShortcut]
  ) {
    self.title = title
    self.shortcuts = shortcuts
  }
}

// MARK: - Formatting

package func formattedKeyboardShortcutKey(
  _ key: KeyEvent,
  modifiers: EventModifiers = []
) -> String {
  var parts: [String] = []
  if modifiers.contains(.ctrl) {
    parts.append("Ctrl")
  }
  if modifiers.contains(.alt) {
    parts.append("Alt")
  }
  if modifiers.contains(.shift) {
    parts.append("Shift")
  }
  parts.append(formattedKeyboardShortcutBaseKey(key))
  return parts.joined(separator: "+")
}

private func formattedKeyboardShortcutBaseKey(
  _ key: KeyEvent
) -> String {
  switch key {
  case .character(let character):
    String(character)
  case .return:
    "Return"
  case .space:
    "Space"
  case .tab:
    "Tab"
  case .arrowLeft:
    "Left"
  case .arrowRight:
    "Right"
  case .arrowUp:
    "Up"
  case .arrowDown:
    "Down"
  case .backspace:
    "Backspace"
  case .escape:
    "Escape"
  case .home:
    "Home"
  case .end:
    "End"
  }
}

// MARK: - Preference Key

private struct KeyboardShortcutPreferenceValue: Equatable, Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var shortcuts: [KeyboardShortcut] = []

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    shortcuts.map {
      "\(formattedKeyboardShortcutKey($0.key, modifiers: $0.modifiers)):\($0.label)"
    }.joined(separator: ", ")
  }
}

private enum KeyboardShortcutPreferenceKey: PreferenceKey {
  static let defaultValue = KeyboardShortcutPreferenceValue()

  static func reduce(
    value: inout KeyboardShortcutPreferenceValue,
    nextValue: () -> KeyboardShortcutPreferenceValue
  ) {
    value.shortcuts.append(contentsOf: nextValue().shortcuts)
  }
}

// MARK: - View Modifier

extension View {
  /// Registers a keyboard shortcut for display in help views.
  ///
  /// When `action` is provided, the shortcut both displays in help views
  /// and dispatches on key press (regardless of focus). When `action` is
  /// `nil`, the shortcut is display-only.
  ///
  /// ```swift
  /// Button("Save") { save() }
  ///   .keyboardShortcut(.character("s"), modifiers: .ctrl, label: "Save file") {
  ///     save()
  ///   }
  /// ```
  public func keyboardShortcut(
    _ key: KeyEvent,
    modifiers: EventModifiers = [],
    label: String,
    group: String? = nil,
    action: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View {
    KeyboardShortcutModifier(
      content: self,
      shortcut: KeyboardShortcut(
        key,
        modifiers: modifiers,
        label: label,
        group: group
      ),
      action: action
    )
  }
}

private struct KeyboardShortcutModifier<Content: View>: View, ResolvableView {
  var content: Content
  var shortcut: KeyboardShortcut
  var action: (@MainActor @Sendable () -> Void)?

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.merge(
      KeyboardShortcutPreferenceKey.self,
      value: .init(shortcuts: [shortcut])
    )

    if let action {
      let dynamicPropertyScope = currentDynamicPropertyScope()
      let binding = HotkeyBinding(
        key: KeyPress(
          shortcut.key,
          modifiers: shortcut.modifiers
        ),
        label: shortcut.label,
        group: shortcut.group
      )
      context.hotkeyRegistry?.register(identity: context.identity, binding: binding) { keyPress in
        guard keyPress == binding.key else {
          return false
        }

        if let dynamicPropertyScope {
          withDynamicPropertyScope(dynamicPropertyScope) {
            action()
          }
        } else {
          action()
        }
        return true
      }
    }

    return [node]
  }
}

// MARK: - Help View

/// Reads all keyboard shortcuts registered via `.keyboardShortcut()` in the
/// subtree and renders a compact, horizontally scrollable help strip.
///
/// Place this view as an overlay or at the bottom of your layout. It uses
/// `overlayPreferenceValue` internally to read the collected shortcuts.
///
/// ```swift
/// VStack {
///   // ... app content with .keyboardShortcut() modifiers ...
/// }
/// .keyboardShortcutHelp()
/// ```
public struct KeyboardShortcutHelpView: View {
  private let shortcuts: [KeyboardShortcut]

  public init(shortcuts: [KeyboardShortcut]) {
    self.shortcuts = shortcuts
  }

  public var body: some View {
    let groups = groupedShortcuts(from: shortcuts)
    ScrollView(.horizontal) {
      HStack(alignment: .center, spacing: 2) {
        ForEach(groups) { group in
          KeyboardShortcutHelpGroupView(group: group)
        }
      }
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(1),
      idealHeight: .finite(1),
      maxHeight: .finite(1),
      alignment: .leading
    )
  }
}

private struct KeyboardShortcutHelpGroupView: View {
  let group: KeyboardShortcutGroup

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      if let title = group.title, !title.isEmpty {
        Text(title)
          .foregroundStyle(.separator)
      }
      ForEach(group.shortcuts) { shortcut in
        KeyboardShortcutHelpToken(shortcut: shortcut)
      }
    }
  }
}

private struct KeyboardShortcutHelpToken: View {
  let shortcut: KeyboardShortcut

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      Text("[\(formattedKeyboardShortcutKey(shortcut.key, modifiers: shortcut.modifiers))]")
        .bold()
      Text(shortcut.label)
    }
  }
}

private func groupedShortcuts(
  from shortcuts: [KeyboardShortcut]
) -> [KeyboardShortcutGroup] {
  var groups: [(String?, [KeyboardShortcut])] = []
  var seen: [String?: Int] = [:]

  for shortcut in shortcuts {
    let groupKey = shortcut.group
    if let index = seen[groupKey] {
      groups[index].1.append(shortcut)
    } else {
      seen[groupKey] = groups.count
      groups.append((groupKey, [shortcut]))
    }
  }

  return groups.map { KeyboardShortcutGroup($0.0, shortcuts: $0.1) }
}

// MARK: - Convenience Modifier

extension View {
  /// Attaches a keyboard shortcut help strip to this view,
  /// auto-populated from all `.keyboardShortcut()` registrations in the subtree.
  public func keyboardShortcutHelp(
    position: Alignment = .bottomLeading
  ) -> some View {
    overlayPreferenceValue(KeyboardShortcutPreferenceKey.self, alignment: position) {
      preference in
      if !preference.shortcuts.isEmpty {
        KeyboardShortcutHelpView(shortcuts: preference.shortcuts)
      }
    }
  }
}

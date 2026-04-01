public import Core

// MARK: - Model

/// A keyboard shortcut registration that pairs a key description with a human-readable label.
public struct KeyboardShortcut: Hashable, Sendable, Identifiable {
  /// Display string for the key (e.g. "q", "Ctrl+S", "Tab", "?").
  public var key: String
  /// Human-readable label describing the action (e.g. "Quit", "Save", "Help").
  public var label: String
  /// Optional group name for clustering related shortcuts (e.g. "File", "Navigation").
  public var group: String?

  public var id: String {
    [key, label, group ?? ""].joined(separator: "\u{001F}")
  }

  public init(
    _ key: String,
    label: String,
    group: String? = nil
  ) {
    self.key = key
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
    shortcuts.map { "\($0.key):\($0.label)" }.joined(separator: ", ")
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

// MARK: - Shortcut String Parser

/// Parses a human-readable shortcut string into a ``LocalKeyPress``.
///
/// Supported formats: `"Ctrl+S"`, `"Alt+X"`, `"Shift+Tab"`, `"Ctrl+Shift+A"`,
/// `"q"`, `"?"`, `"Enter"`, `"Escape"`, `"Space"`.
package func parseShortcutKey(_ description: String) -> LocalKeyPress? {
  let components = description.split(separator: "+").map { part in
    String(part.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
  }
  guard !components.isEmpty else {
    return nil
  }

  var modifiers: EventModifiers = []
  var keyComponent: String?

  for component in components {
    switch component.lowercased() {
    case "ctrl", "control":
      modifiers.insert(.control)
    case "alt", "option", "opt":
      modifiers.insert(.option)
    case "shift":
      modifiers.insert(.shift)
    default:
      keyComponent = component
    }
  }

  guard let keyString = keyComponent else {
    return nil
  }

  guard let key = parseKeyName(keyString) else {
    return nil
  }

  return LocalKeyPress(key, modifiers: modifiers)
}

private func parseKeyName(_ name: String) -> LocalKeyEvent? {
  switch name.lowercased() {
  case "enter", "return":
    return .enter
  case "space":
    return .space
  case "tab":
    return .tab
  case "esc", "escape":
    return .escape
  case "backspace", "delete":
    return .backspace
  case "up", "arrowup":
    return .arrowUp
  case "down", "arrowdown":
    return .arrowDown
  case "left", "arrowleft":
    return .arrowLeft
  case "right", "arrowright":
    return .arrowRight
  default:
    // Single character
    if name.count == 1, let character = name.first {
      return .character(character)
    }
    return nil
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
  ///   .keyboardShortcut("Ctrl+S", label: "Save file") {
  ///     save()
  ///   }
  /// ```
  public func keyboardShortcut(
    _ key: String,
    label: String,
    group: String? = nil,
    action: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View {
    KeyboardShortcutModifier(
      content: self,
      shortcut: KeyboardShortcut(key, label: label, group: group),
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

    if let action, let parsed = parseShortcutKey(shortcut.key) {
      let dynamicPropertyScope = currentDynamicPropertyScope()
      let binding = HotkeyBinding(
        key: parsed,
        label: shortcut.label,
        group: shortcut.group
      )
      context.hotkeyRegistry?.register(binding: binding) { _ in
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
      Text("[\(shortcut.key)]")
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

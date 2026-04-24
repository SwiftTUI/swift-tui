import Layouts
import TerminalUI

/// Full-screen detail host for one ``LayoutEntry``. Renders
/// `entry.makeView()` occupying the body, with a 1-row footer and an
/// Esc key command that calls `onBack`.
///
/// The host deliberately owns no sheet / alert / other presentation
/// seam; individual layouts that demo presentations own their own Esc
/// handling. See `project_presentation_escape_dismiss.md`.
///
/// Esc-binding limitation: `.keyCommand(...)` requires a non-empty
/// `modifiers:` set; modifier-less registrations (including
/// `modifiers: []`) are silently dropped at resolve time —
/// single-key bindings for Esc/Tab/Enter/arrows/typing are reserved
/// for framework-internal dispatch. See
/// `Sources/View/ActionScopes/KeyCommandModifier.swift` for the
/// enforcement site. We register the binding anyway so that the
/// declaration reads as intended and so behaviour upgrades for free
/// if the framework later routes bare Esc through consumer key
/// commands; today `onBack` from this site will not fire and the
/// detail host has no dismissal keystroke of its own.
struct LayoutDetailHost: View {
  let entry: LayoutEntry
  let onBack: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      entry.makeView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      Text("esc back  ·  ⌃C quit  ·  \(entry.category.rawValue) / \(entry.title)")
        .foregroundStyle(.muted)
        .padding(.horizontal, 1)
    }
    .panel(id: "layouts.detail.\(entry.id)")
    .keyCommand(
      "Back",
      key: .escape,
      modifiers: [],
      action: onBack
    )
  }
}

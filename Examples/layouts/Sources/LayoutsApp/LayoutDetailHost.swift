import Layouts
import TerminalUI

/// Full-screen detail host for one ``LayoutEntry``. Renders
/// `entry.makeView()` filling the available space, with a 1-row
/// footer and a ⌃B key command that calls `onBack` to return to the
/// picker.
///
/// The host deliberately owns no sheet / alert / other presentation
/// seam; individual layouts that demo presentations own their own
/// dismiss handling. See `project_presentation_escape_dismiss.md`.
///
/// Why ⌃B instead of Esc: the framework reserves Esc (and other
/// unmodified navigation keys) for presentation dismissal in
/// `KeyCommandModifier`; consumer-bound single-key commands are
/// silently dropped. ⌃B is the nearest idiomatic "back" chord in
/// terminal UIs. See the open design question at
/// `docs/proposals/layout/BEHAVIOUR_FINDINGS.md` finding #2.
struct LayoutDetailHost: View {
  let entry: LayoutEntry
  let onBack: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      entry.makeView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      Text("⌃B back  ·  ⌃C quit  ·  \(entry.category.rawValue) / \(entry.title)")
        .foregroundStyle(.muted)
        .padding(.horizontal, 1)
    }
    .panel(id: "layouts.detail.\(entry.id)")
    .keyCommand(
      "Back",
      key: .character("b"),
      modifiers: .ctrl,
      action: onBack
    )
  }
}

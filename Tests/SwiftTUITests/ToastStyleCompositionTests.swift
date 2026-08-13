import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A3's toast half: the style argument survives portal hosting, and a toast
/// resolves its style at *composition* time so it can see its own position
/// in the visible stack.
@MainActor
@Suite(.serialized)
struct ToastStyleCompositionTests {
  /// Reports the stack shape it was resolved against by painting it, so a
  /// rendered frame shows whether composition-time inputs arrived.
  private struct StackReportingToastStyle: ToastStyle {
    var snapshotLabel: String { "StackReportingToastStyle" }

    func resolvePresentation(
      for configuration: ToastStyleConfiguration
    ) -> ToastStylePresentation {
      ToastStylePresentation(
        icon: "\(configuration.stackIndex)of\(configuration.stackCount)",
        minWidth: 24,
        maxWidth: 48
      )
    }
  }

  private struct ToastRoot: View {
    let styles: [AnyToastStyle]

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("base")
      }
      .toast("first", isPresented: .constant(true), style: styles[0], duration: nil)
      .toast("second", isPresented: .constant(true), style: styles[1], duration: nil)
    }
  }

  private func surface(_ view: some View, identity: String) -> String {
    DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity(identity)),
      proposal: .init(width: 60, height: 20)
    ).rasterSurface.lines.joined(separator: "\n")
  }

  @Test("each toast resolves against its own position in the visible stack")
  func stackPositionReachesEachStyle() {
    let rendered = surface(
      ToastRoot(
        styles: [
          AnyToastStyle(StackReportingToastStyle()),
          AnyToastStyle(StackReportingToastStyle()),
        ]
      ),
      identity: "ToastStackPosition"
    )
    // Two toasts are visible, so the stack count is 2 and the indices are
    // distinct — the inputs that only exist after composition.
    #expect(rendered.contains("0of2"))
    #expect(rendered.contains("1of2"))
  }

  @Test("a declaration's style argument survives portal hosting")
  func declaredStyleSurvivesPortalHosting() {
    let rendered = surface(
      ToastRoot(styles: [.success, .danger]),
      identity: "ToastDeclaredStyles"
    )
    // The two built-ins keep their distinct icons through the portal.
    #expect(rendered.contains("✓"))
    #expect(rendered.contains("✗"))
  }

  @Test("built-in toast styles compare equal for reuse; distinct tones do not")
  func toastStylesCompareForReuse() {
    #expect(AnyToastStyle.info.isEqualForReuse(to: AnyToastStyle.info))
    #expect(!AnyToastStyle.info.isEqualForReuse(to: AnyToastStyle.danger))
  }
}

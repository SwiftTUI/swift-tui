import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Toast presentations pass through the shared misuse channel: an invalid
/// value reports one `style.invalidPresentation` issue and the info
/// presentation renders for that resolve, while a valid custom value is
/// honored as resolved.
@MainActor
@Suite(.serialized)
struct ToastStyleValidationTests {
  /// Width bounds out of order: the surface must fall back rather than hand
  /// layout an inverted frame.
  private struct InvertedWidthToastStyle: ToastStyle {
    var snapshotLabel: String { "InvertedWidthToastStyle" }

    func resolvePresentation(
      for _: ToastStyleConfiguration
    ) -> ToastStylePresentation {
      ToastStylePresentation(icon: "!", minWidth: 40, maxWidth: 10)
    }
  }

  private struct StarToastStyle: ToastStyle {
    var snapshotLabel: String { "StarToastStyle" }

    func resolvePresentation(
      for _: ToastStyleConfiguration
    ) -> ToastStylePresentation {
      ToastStylePresentation(icon: "★", minWidth: 24, maxWidth: 48)
    }
  }

  private struct ToastRoot: View {
    let style: AnyToastStyle

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("base")
      }
      .toast("hello", isPresented: .constant(true), style: style, duration: nil)
    }
  }

  private func render(_ style: AnyToastStyle, identity: String) -> RenderSnapshot {
    DefaultRenderer().render(
      ToastRoot(style: style),
      context: .init(identity: testIdentity(identity)),
      proposal: .init(width: 60, height: 20)
    )
  }

  private func surface(of artifacts: RenderSnapshot) -> String {
    artifacts.rasterSurface.lines.joined(separator: "\n")
  }

  private func styleIssues(in artifacts: RenderSnapshot) -> [RuntimeIssue] {
    artifacts.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }
  }

  @Test("inverted width bounds render the info presentation and report one issue")
  func invertedWidthsFallBackAndReport() throws {
    let artifacts = render(
      AnyToastStyle(InvertedWidthToastStyle()),
      identity: "ToastInvertedWidths"
    )
    let rendered = surface(of: artifacts)
    #expect(rendered.contains("hello"))
    #expect(rendered.contains("ℹ"))
    #expect(!rendered.contains("!"))
    let issues = styleIssues(in: artifacts)
    let issue = try #require(issues.first)
    #expect(issues.count == 1)
    #expect(issue.message.contains("ToastStyle InvertedWidthToastStyle"))
    #expect(issue.message.contains("widths"))
  }

  @Test("a valid custom presentation is honored without an issue")
  func validCustomPresentationIsHonored() {
    let artifacts = render(AnyToastStyle(StarToastStyle()), identity: "ToastValidCustom")
    let rendered = surface(of: artifacts)
    #expect(rendered.contains("hello"))
    #expect(rendered.contains("★"))
    #expect(!rendered.contains("ℹ"))
    #expect(styleIssues(in: artifacts).isEmpty)
  }

  @Test("validation names each rule the value breaks")
  func validationProblemsCoverEachRule() {
    let terminal = CellSize(width: 80, height: 24)
    #expect(ToastStylePresentation().validationProblems(fitting: terminal).isEmpty)
    #expect(ToastStylePresentation(contentPadding: .init(top: -1)).validationProblems.count == 1)
    #expect(ToastStylePresentation(minWidth: 40, maxWidth: 10).validationProblems.count == 1)
    #expect(ToastStylePresentation(maxWidth: 0).validationProblems.count == 1)
    #expect(ToastStylePresentation(minHeight: 4, idealHeight: 3).validationProblems.count == 1)
    #expect(ToastStylePresentation(idealHeight: 6, maxHeight: 5).validationProblems.count == 1)
    #expect(ToastStylePresentation(icon: "").validationProblems.count == 1)
    #expect(ToastStylePresentation(icon: "a\nb").validationProblems.count == 1)
    #expect(ToastStylePresentation(icon: "★").validationProblems.isEmpty)
    // Padding larger than the terminal is only misuse once a terminal is
    // known; the terminal-independent rules pass it.
    let wide = ToastStylePresentation(contentPadding: .init(horizontal: 40))
    #expect(wide.validationProblems.isEmpty)
    #expect(wide.validationProblems(fitting: terminal).count == 1)
    let tall = ToastStylePresentation(contentPadding: .init(vertical: 12))
    #expect(tall.validationProblems(fitting: terminal).count == 1)
    #expect(tall.validationProblems(fitting: .init(width: 0, height: 0)).isEmpty)
  }
}

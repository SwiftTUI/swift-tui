import Testing

@_spi(StyleFixtures) @testable import SwiftTUIViews

/// Compile fixtures for the Phase A break inventory (control-style plan
/// 2026-08-12-002). Each case is a *positive* fixture: it compiles only
/// against the end-state API, so a reintroduced legacy overload that
/// shadowed the replacement would surface here. Absence of the removed
/// declarations themselves is proved by the symbol-graph baselines
/// (`docs/public_api_overrides.yml` `removed:`) and the org-root sweep
/// script, which fail if a retired name reappears.
@MainActor
@Suite("Control style API removals")
struct ControlStyleAPIRemovalTests {
  @Test("the only spinner initializer is style-free")
  func spinnerIsStyleFree() {
    _ = Spinner()
    _ = Spinner(stage: .finished)
    // Frames and cadence now come from a style, not the declaration.
    _ = Spinner()
      .spinnerStyle(
        GlyphSpinnerStyle(activeFrames: ["◡", "◟"], interval: .milliseconds(120))
      )
    _ = Spinner().spinnerStyle(.moonPhase)
    _ = Spinner().spinnerStyle(AnySpinnerStyle.moonPhase)
  }

  @Test("spinner styles apply at a surface and at an ancestor")
  func spinnerStyleAppliesAtBothScopes() {
    _ = VStack {
      Spinner().spinnerStyle(.globe)
      Spinner()
    }
    .spinnerStyle(.clockFace)
  }

  @Test("tables style through tableStyle and lists through listStyle")
  func collectionStylesAreSeparate() {
    _ = Table(0..<1, id: \.self, columns: [.init("V", width: 4)]) { _ in
      Text("x")
    }
    .tableStyle(.bordered)
    _ = Table(0..<1, id: \.self, columns: [.init("V", width: 4)]) { _ in
      Text("x")
    }
    .tableStyle(AnyTableStyle.inset)
    _ = List { Text("x") }.listStyle(.plain)
    _ = List { Text("x") }.listStyle(AnyListStyle.insetGrouped)
  }

  @Test("toolbars declare style-free and take their style from the environment")
  func toolbarsAreStyleFree() {
    _ = Panel(id: "scope") { Text("content") }
      .toolbar()
      .toolbarStyle(.defaultBottom)
    _ = Panel(id: "scope") { Text("content") }
      .toolbar()
      .toolbarStyle(AnyToolbarStyle.defaultTop)
    // An ancestor may set it too, since the host reads the nearest value.
    _ = VStack {
      Panel(id: "scope") { Text("content") }.toolbar()
    }
    .toolbarStyle(.defaultTop)
  }

  @Test("toast styling stays declaration-scoped")
  func toastStylingStaysDeclarationScoped() {
    // `.toast(..., style:)` is the only toast styling path: there is
    // deliberately no toast environment key and no `toastStyle(_:)`
    // modifier, so a toast's tone cannot become modifier-order-sensitive
    // environment chaining. Absence is proved by the symbol-graph
    // baselines; this fixture pins that the declaration path compiles with
    // a built-in and with a custom style.
    struct PlainToastStyle: ToastStyle {
      func resolvePresentation(
        for configuration: ToastStyleConfiguration
      ) -> ToastStylePresentation {
        ToastStylePresentation(icon: configuration.stackIndex == 0 ? "*" : "-")
      }
    }
    _ = Text("x").toast("m", isPresented: .constant(true), style: .success)
    _ = Text("x").toast("m", isPresented: .constant(true), style: PlainToastStyle())
  }

  @Test("outline styles resolve through the configuration entry point")
  func outlineStylesUseResolvePresentation() {
    let resolved = AnyOutlineStyle.rounded.presentation(
      for: OutlineStyleConfiguration(styleEnvironment: StyleEnvironmentSnapshot())
    )
    #expect(resolved.leafConnector == "╰─ ")
    #expect(resolved.snapshotLabel == "OutlineStyle.rounded")
  }
}

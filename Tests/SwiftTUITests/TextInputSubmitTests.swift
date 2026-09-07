import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TextInputSubmitTests {
  private final class SubmitLog {
    var events: [String] = []
    var text = ""
  }

  private func renderField(
    _ log: SubmitLog,
    identity: Identity,
    registry: LocalKeyHandlerRegistry,
    @ViewBuilder content: @MainActor (Binding<String>) -> some View
  ) -> DefaultRenderer {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity
    let renderer = DefaultRenderer()
    _ = renderer.render(
      content(
        Binding(
          get: { log.text },
          set: { log.text = $0 }
        )
      ),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )
    return renderer
  }

  @Test("Return in a TextField runs the enclosing onSubmit action and is consumed")
  func textFieldReturnRunsOnSubmitAndIsConsumed() {
    let log = SubmitLog()
    let identity = testIdentity("SubmitTextField")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      TextField("Name", text: text)
        .id(identity)
        .textFieldStyle(.plain)
        .onSubmit { log.events.append("submit") }
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("a"))))
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.return)))
    #expect(log.events == ["submit"])
    #expect(log.text == "a")
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("b"))))
    #expect(log.text == "ab")
  }

  @Test("nested onSubmit actions all run, innermost first")
  func nestedOnSubmitActionsRunInnermostFirst() {
    let log = SubmitLog()
    let identity = testIdentity("NestedSubmitField")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      VStack {
        TextField("Name", text: text)
          .id(identity)
          .textFieldStyle(.plain)
          .onSubmit { log.events.append("inner") }
      }
      .onSubmit { log.events.append("outer") }
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.return)))
    #expect(log.events == ["inner", "outer"])
  }

  @Test("submitScope stops submissions from reaching enclosing onSubmit actions")
  func submitScopeBlocksOuterActions() {
    let log = SubmitLog()
    let identity = testIdentity("ScopedSubmitField")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      VStack {
        TextField("Name", text: text)
          .id(identity)
          .textFieldStyle(.plain)
          .onSubmit { log.events.append("inner") }
          .submitScope()
      }
      .onSubmit { log.events.append("outer") }
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.return)))
    #expect(log.events == ["inner"])
  }

  @Test("a non-blocking submitScope leaves the chain intact")
  func nonBlockingSubmitScopeLeavesChainIntact() {
    let log = SubmitLog()
    let identity = testIdentity("PassthroughScopeField")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      VStack {
        TextField("Name", text: text)
          .id(identity)
          .textFieldStyle(.plain)
          .submitScope(false)
      }
      .onSubmit { log.events.append("outer") }
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.return)))
    #expect(log.events == ["outer"])
  }

  @Test("Return in a SecureField submits")
  func secureFieldReturnSubmits() {
    let log = SubmitLog()
    let identity = testIdentity("SubmitSecureField")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      SecureField("Password", text: text)
        .id(identity)
        .textFieldStyle(.plain)
        .onSubmit { log.events.append("submit") }
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.return)))
    #expect(log.events == ["submit"])
  }

  @Test("Return in a TextEditor inserts a newline and never submits")
  func textEditorReturnInsertsNewlineNotSubmit() {
    let log = SubmitLog()
    log.text = "line"
    let identity = testIdentity("SubmitTextEditor")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      TextEditor(text: text)
        .id(identity)
        .onSubmit { log.events.append("submit") }
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.return)))
    #expect(log.events.isEmpty)
    #expect(log.text.contains("\n"))
  }

  @Test("Return without an enclosing onSubmit keeps its default routing")
  func returnWithoutOnSubmitKeepsDefaultRouting() {
    let log = SubmitLog()
    let identity = testIdentity("PlainTextField")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      TextField("Name", text: text)
        .id(identity)
        .textFieldStyle(.plain)
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(!registry.dispatch(identity: identity, keyPress: KeyPress(.return)))
  }

  @Test("modified Return does not submit")
  func modifiedReturnDoesNotSubmit() {
    let log = SubmitLog()
    let identity = testIdentity("ModifiedReturnField")
    let registry = LocalKeyHandlerRegistry()
    let renderer = renderField(log, identity: identity, registry: registry) { text in
      TextField("Name", text: text)
        .id(identity)
        .textFieldStyle(.plain)
        .onSubmit { log.events.append("submit") }
    }
    defer { withExtendedLifetime(renderer) {} }

    #expect(
      !registry.dispatch(
        identity: identity,
        keyPress: KeyPress(.return, modifiers: [.shift])
      )
    )
    #expect(log.events.isEmpty)
  }
}

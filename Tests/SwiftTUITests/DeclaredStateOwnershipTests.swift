@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// State a view declares belongs to the node that evaluates it, not to the
/// view whose scope its body runs under.
///
/// Two seams evaluate authored content under the enclosing view's authoring
/// scope, so that state the enclosing view captured and the handlers it
/// registered stay on their owner: a style body, and an authored label or
/// content slot. The content's own dynamic properties once bound to that
/// enclosing owner as well. Every control of one view shares it, and a slot
/// is keyed by declaration site alone. Two buttons with one style therefore
/// shared each `@State` the style declared, and two buttons whose labels were
/// one view type shared that view's state: the second read the first one's
/// value. A style body that re-resolved without the enclosing view also
/// claimed its slots against a record only that view's evaluation reset, and
/// reported `state.duplicateSlotClaim` for a single wrapper (opening the
/// gallery's command palette).
@MainActor
@Suite(.serialized)
struct DeclaredStateOwnershipTests {
  private let root = testIdentity("DeclaredStateRoot")

  private func render<V: View>(
    _ view: V,
    with renderer: DefaultRenderer = DefaultRenderer(),
    invalidating invalidated: Set<Identity> = []
  ) -> RenderSnapshot {
    renderer.render(
      view,
      context: .init(identity: root, invalidatedIdentities: invalidated),
      proposal: .init(width: 40, height: 6)
    )
  }

  private func text(_ snapshot: RenderSnapshot) -> String {
    snapshot.rasterSurface.lines.joined(separator: "|")
  }

  private func duplicateClaims(_ snapshot: RenderSnapshot) -> [RuntimeIssue] {
    snapshot.diagnostics.runtime.issues.filter { $0.typedCode == .State.duplicateSlotClaim }
  }

  @Test("two buttons with one style each own the state its body declares")
  func buttonsOwnStyleBodyState() {
    let snapshot = render(
      StyledControlsHost {
        Button("A") {}.buttonStyle(SeededBodyButtonStyle(tag: 1))
        Button("B") {}.buttonStyle(SeededBodyButtonStyle(tag: 2))
      })

    #expect(text(snapshot).contains("v1=1"))
    #expect(text(snapshot).contains("v2=2"), "the second button read the first one's slot")
    #expect(duplicateClaims(snapshot).isEmpty)
  }

  @Test("two buttons with one style each own the state the style itself declares")
  func buttonsOwnStyleStructState() {
    let snapshot = render(
      StyledControlsHost {
        Button("A") {}.buttonStyle(SeededButtonStyle(tag: 1))
        Button("B") {}.buttonStyle(SeededButtonStyle(tag: 2))
      })

    #expect(text(snapshot).contains("s1=1"))
    #expect(text(snapshot).contains("s2=2"), "the second button read the first one's slot")
    #expect(duplicateClaims(snapshot).isEmpty)
  }

  @Test("two toggles with one style each own the state its body declares")
  func togglesOwnStyleBodyState() {
    let snapshot = render(
      StyledControlsHost {
        Toggle("A", isOn: .constant(true)).toggleStyle(SeededBodyToggleStyle(tag: 1))
        Toggle("B", isOn: .constant(false)).toggleStyle(SeededBodyToggleStyle(tag: 2))
      })

    #expect(text(snapshot).contains("v1=1"))
    #expect(text(snapshot).contains("v2=2"), "the second toggle read the first one's slot")
    #expect(duplicateClaims(snapshot).isEmpty)
  }

  @Test("a write to one styled control's state leaves its sibling's alone and survives a re-render")
  func writeReachesOnlyItsOwnControl() throws {
    let renderer = DefaultRenderer()
    let writers = StyleStateWriters()
    let view = StyledControlsHost {
      Button("A") {}.buttonStyle(WritableBodyButtonStyle(tag: 1, writers: writers))
      Button("B") {}.buttonStyle(WritableBodyButtonStyle(tag: 2, writers: writers))
    }

    let first = render(view, with: renderer)
    #expect(text(first).contains("w1=0"))
    #expect(text(first).contains("w2=0"))

    let writeFirst = try #require(writers.write[1])
    writeFirst(7)
    let second = render(view, with: renderer, invalidating: [root])

    #expect(text(second).contains("w1=7"), "the write did not reach the control that made it")
    #expect(text(second).contains("w2=0"), "the write leaked into the sibling control")
    #expect(duplicateClaims(second).isEmpty)
  }

  @Test(
    "two controls of one kind each own the state their label or content declares",
    arguments: AuthoredSlot.allCases
  )
  func authoredSlotsOwnTheirState(slot: AuthoredSlot) {
    let snapshot = render(StyledControlsHost { AuthoredSlotControls(slot: slot) })

    #expect(text(snapshot).contains("v1=1"), "\(slot): \(text(snapshot))")
    #expect(
      text(snapshot).contains("v2=2"),
      "\(slot): the second slot read the first one's state: \(text(snapshot))")
    #expect(duplicateClaims(snapshot).isEmpty, "\(slot)")
  }

  @Test("a write to one button label's state leaves the other label's alone")
  func labelWriteReachesOnlyItsOwnLabel() throws {
    let renderer = DefaultRenderer()
    let writers = StyleStateWriters()
    let view = StyledControlsHost {
      Button {
      } label: {
        WritableBody(tag: 1, writers: writers)
      }
      Button {
      } label: {
        WritableBody(tag: 2, writers: writers)
      }
    }

    let first = render(view, with: renderer)
    #expect(text(first).contains("w1=0"))
    #expect(text(first).contains("w2=0"))

    let writeFirst = try #require(writers.write[1])
    writeFirst(7)
    let second = render(view, with: renderer, invalidating: [root])

    #expect(text(second).contains("w1=7"), "the write did not reach the label that made it")
    #expect(text(second).contains("w2=0"), "the write leaked into the sibling label")
    #expect(duplicateClaims(second).isEmpty)
  }

  @Test(
    "state declared under a control ends with the control",
    arguments: [DeclaredStateSite.styleBody, .label]
  )
  func declaredStateEndsWithItsControl(site: DeclaredStateSite) throws {
    let renderer = DefaultRenderer()
    let writers = StyleStateWriters()
    func frame(showsControl: Bool) -> String {
      text(
        render(
          RemovableControlHost(showsControl: showsControl, site: site, writers: writers),
          with: renderer, invalidating: [root]))
    }

    #expect(frame(showsControl: true).contains("w1=0"))
    let write = try #require(writers.write[1])
    write(7)
    #expect(frame(showsControl: true).contains("w1=7"), "the state did not survive a re-render")

    #expect(!frame(showsControl: false).contains("w1="))
    // The enclosing view stayed mounted throughout. The state belonged to the
    // control, so a new control starts from the declared initial value.
    #expect(
      frame(showsControl: true).contains("w1=0"),
      "the removed control's state outlived it on the enclosing view")
  }

  @Test("two availability-gated views of one type each own their state")
  func availabilityGatedViewsOwnTheirState() {
    // `if #available` content is stored through a scoped `AnyView`, which
    // resolves its payload under the enclosing view's scope like a style body.
    let snapshot = render(
      StyledControlsHost {
        if #available(macOS 26, *) {
          SeededBody(tag: 1)
        }
        if #available(macOS 26, *) {
          SeededBody(tag: 2)
        }
      })

    #expect(text(snapshot).contains("v1=1"))
    #expect(text(snapshot).contains("v2=2"), "the second view read the first one's slot")
    #expect(duplicateClaims(snapshot).isEmpty)
  }

  @Test(
    "an open command palette filters on its own state and reports no shared slot",
    arguments: [RuntimeRenderMode.sync, .async, .asyncNoCancel, .asyncNoDrop]
  )
  func commandPaletteOwnsItsState(mode: RuntimeRenderMode) async throws {
    let harness = try await RuntimeIssueJourneyHarness.start(
      named: "PaletteOwnershipRoot", mode: mode, showing: "shell page"
    ) {
      PaletteOwnershipShell()
    }
    defer { harness.stop() }

    // Opening the palette re-resolves its body without the view that hosts
    // the sheet: the body's own `onAppear` and `onChange` write its state.
    try harness.click("Palette")
    try await harness.waitForScreen("the open palette") {
      $0.contains("Filter commands") && $0.contains("Alpha") && $0.contains("Bravo")
    }
    // The filter field is bound to the body's state; typing narrows the rows.
    harness.type("br")
    try await harness.waitForScreen("the filtered palette") {
      $0.contains("Bravo") && !$0.contains("Alpha")
    }
    try await harness.finish()

    #expect(
      harness.duplicateSlotClaims.isEmpty,
      "one wrapper was reported as two sharing a slot: \(harness.duplicateSlotClaims)")
  }
}

/// The authored slots a control hands its style: each case mounts two
/// controls of one kind whose slot content is one stateful view type.
enum AuthoredSlot: String, CaseIterable, Sendable {
  case buttonLabel
  case toggleLabel
  case labelTitle
  case labelTitleAndIcon
  case menuLabel
  case pickerLabel
  case sliderLabel
  case labeledContent
  case groupBoxContent
}

private struct AuthoredSlotControls: View {
  let slot: AuthoredSlot

  var body: some View {
    switch slot {
    case .buttonLabel:
      Button {
      } label: {
        SeededBody(tag: 1)
      }
      Button {
      } label: {
        SeededBody(tag: 2)
      }
    case .toggleLabel:
      Toggle(isOn: .constant(true)) { SeededBody(tag: 1) }
      Toggle(isOn: .constant(false)) { SeededBody(tag: 2) }
    case .labelTitle:
      Label {
        SeededBody(tag: 1)
      } icon: {
        Text("*")
      }
      Label {
        SeededBody(tag: 2)
      } icon: {
        Text("*")
      }
    case .labelTitleAndIcon:
      Label {
        SeededBody(tag: 1)
      } icon: {
        SeededBody(tag: 2)
      }
    case .menuLabel:
      Menu {
        SeededBody(tag: 1)
      } content: {
        Text("x")
      }
      Menu {
        SeededBody(tag: 2)
      } content: {
        Text("y")
      }
    case .pickerLabel:
      Picker(selection: .constant(0)) {
        Text("o").tag(0)
      } label: {
        SeededBody(tag: 1)
      }
      Picker(selection: .constant(0)) {
        Text("o").tag(0)
      } label: {
        SeededBody(tag: 2)
      }
    case .sliderLabel:
      Slider(value: .constant(1), in: 0...2, step: 1) { SeededBody(tag: 1) }
      Slider(value: .constant(1), in: 0...2, step: 1) { SeededBody(tag: 2) }
    case .labeledContent:
      LabeledContent("one") { SeededBody(tag: 1) }
      LabeledContent("two") { SeededBody(tag: 2) }
    case .groupBoxContent:
      GroupBox { SeededBody(tag: 1) }
      GroupBox { SeededBody(tag: 2) }
    }
  }
}

/// A composite view around the styled controls. A control is a primitive, so
/// the authoring scope ambient at its style seam is this view's.
private struct StyledControlsHost<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
  }
}

/// A view whose state is seeded from its tag, so an instance that reads
/// another instance's slot shows that instance's seed.
private struct SeededBody: View {
  let tag: Int
  @State private var value: Int

  init(tag: Int) {
    self.tag = tag
    _value = State(wrappedValue: tag)
  }

  var body: some View {
    Text("v\(tag)=\(value)")
  }
}

private struct SeededBodyButtonStyle: ButtonStyle {
  let tag: Int

  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    SeededBody(tag: tag)
  }
}

private struct SeededBodyToggleStyle: ToggleStyle {
  let tag: Int

  @MainActor
  func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    SeededBody(tag: tag)
  }
}

/// A style that declares the state itself, seeded from its tag.
@MainActor
private struct SeededButtonStyle: ButtonStyle {
  let tag: Int
  @State private var value: Int

  init(tag: Int) {
    self.tag = tag
    _value = State(wrappedValue: tag)
  }

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    Text("s\(tag)=\(value)")
  }
}

@MainActor
private final class StyleStateWriters {
  var write: [Int: @MainActor (Int) -> Void] = [:]
}

private struct WritableBody: View {
  let tag: Int
  let writers: StyleStateWriters
  @State private var value = 0

  var body: some View {
    writers.write[tag] = { value = $0 }
    return Text("w\(tag)=\(value)")
  }
}

private struct WritableBodyButtonStyle: ButtonStyle {
  let tag: Int
  let writers: StyleStateWriters

  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    WritableBody(tag: tag, writers: writers)
  }
}

/// Where the control's state is declared: in the view its style returns, or
/// in the view its label slot holds.
enum DeclaredStateSite: String, Sendable {
  case styleBody
  case label
}

/// A view that stays mounted while the control it declares comes and goes.
private struct RemovableControlHost: View {
  let showsControl: Bool
  let site: DeclaredStateSite
  let writers: StyleStateWriters

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("host")
      if showsControl {
        switch site {
        case .styleBody:
          Button("A") {}.buttonStyle(WritableBodyButtonStyle(tag: 1, writers: writers))
        case .label:
          Button {
          } label: {
            WritableBody(tag: 1, writers: writers)
          }
        }
      }
    }
  }
}

/// The gallery's shell in miniature: a toolbar item presents a palette of
/// the commands the scope contributes.
private struct PaletteOwnershipShell: View {
  @State private var showsPalette = false

  var body: some View {
    Text("shell page")
      .toolbarItem(.init(title: "Palette", action: { showsPalette = true }))
      .panel(id: "palette-ownership")
      .paletteCommand(name: "Alpha", action: {})
      .paletteCommand(name: "Bravo", action: {})
      .toolbar().toolbarStyle(.defaultBottom)
      .paletteSheet("Command palette", isPresented: $showsPalette)
  }
}

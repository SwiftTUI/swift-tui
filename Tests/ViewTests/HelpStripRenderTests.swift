import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct HelpStripRenderTests {
  @Test(".help() with no commands still renders the primary body")
  func helpWithNoCommandsRendersEmptyStrip() {
    let context = makeResolveContext("Empty")
    let node =
      Text("Body")
      .help()
      .resolve(in: context)

    // The modifier composes the primary content and the strip under a
    // VStack so the strip reserves its row at the bottom. Without any
    // commands the strip emits no tokens and no " • " separators.
    let helpTexts = collectRenderedText(in: node)
    #expect(helpTexts.contains("Body"))
    #expect(!helpTexts.contains(where: { $0.contains(" • ") }))
  }

  @Test(".help() with one keyed command renders its glyph and title")
  func helpWithOneKeyedCommandRendersBoth() {
    let context = makeResolveContext("OneKeyed")
    let node =
      Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s")
      ) {}
      .help()
      .resolve(in: context)

    let helpTexts = collectRenderedText(in: node)
    let joined = helpTexts.joined(separator: " ")
    #expect(joined.contains("[^S]"))
    #expect(joined.contains("Save"))
  }

  @Test(".help() with one keyless command renders an empty strip")
  func helpWithOneKeylessCommandRendersEmpty() {
    let context = makeResolveContext("Keyless")
    let node =
      Text("Body")
      .command(id: "open-file", title: "Open File")
      .help()
      .resolve(in: context)

    let helpTexts = collectRenderedText(in: node)
    let joined = helpTexts.joined(separator: " ")
    #expect(!joined.contains("Open File"))
  }

  @Test(".help() with two keyed commands renders both separated by a bullet")
  func helpWithTwoKeyedCommandsRendersSeparator() {
    let context = makeResolveContext("TwoKeyed")
    let node =
      Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s")
      ) {}
      .command(
        id: "quit",
        title: "Quit",
        key: .ctrl("q")
      ) {}
      .help()
      .resolve(in: context)

    let helpTexts = collectRenderedText(in: node)
    let joined = helpTexts.joined(separator: " ")
    #expect(joined.contains("Save"))
    #expect(joined.contains("Quit"))
    #expect(joined.contains("•"))
  }

  @Test(".help() node composes under a VStack so the strip row is reserved")
  func helpUsesReservedVStackLayout() {
    // This test pins the layout contract: `.help` must *reserve* a
    // bottom row by composing content + strip under a VStack, not
    // overdraw the strip on top of content. A previous draft used
    // `.decoration(primaryIndex: 0, alignment: .bottom)`, which
    // overdraws — the integration tests caught that regression.
    //
    // We assert the resolved node is a stack laid out along the
    // vertical axis; the unit test deliberately skips running the
    // full layout pass (see HelpStripIntegrationTests for the
    // end-to-end pipeline exercise).
    let context = makeResolveContext("LayoutContract")
    let node =
      Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s")
      ) {}
      .help()
      .resolve(in: context)

    if case .stack(let axis, _, _, _) = node.layoutBehavior {
      #expect(axis == .vertical)
    } else {
      Issue.record("Expected vertical stack layout, got \(node.layoutBehavior)")
    }
  }
}

// MARK: - Helpers

@MainActor
private func makeResolveContext(
  _ suffix: String
) -> ResolveContext {
  var context = ResolveContext(
    identity: testIdentity("HelpStripRenderTests", suffix),
    applyEnvironmentValues: true
  )
  context.hotkeyRegistry = HotkeyRegistry()
  return context
}

/// Walks the resolved subtree collecting every text fragment emitted
/// by ``Text`` leaves. Used by the strip tests to assert visible
/// content without round-tripping through the full render pipeline.
@MainActor
private func collectRenderedText(
  in node: ResolvedNode
) -> [String] {
  var collected: [String] = []
  walk(node, into: &collected)
  return collected
}

@MainActor
private func walk(
  _ node: ResolvedNode,
  into collected: inout [String]
) {
  if case .text(let content) = node.drawPayload {
    collected.append(content)
  }
  if case .richText(let payload) = node.drawPayload {
    collected.append(payload.visibleText)
  }
  for child in node.children {
    walk(child, into: &collected)
  }
}

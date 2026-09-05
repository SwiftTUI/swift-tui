import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

@MainActor
struct ScrollLinkStyleTests {
  @Test("link presentation merges before its label without splitting the rich payload")
  func richMergeOrder() throws {
    let link = Link(
      Text("Docs").foregroundStyle(.yellow).underline(false),
      destination: "https://example.com")
    let frame = DefaultRenderer().render(
      Text("Before \(link) after")
        .foregroundStyle(.red).bold().opacity(0.5)
        .linkStyle(
          ConsumerLinkStyle(
            underline: .visible(.init(pattern: .solid)),
            foreground: .color(.green), opacity: 0.5)),
      context: .init(identity: testIdentity("RichStyle")), proposal: .init(width: 30, height: 3))
    let links = allLinkRuns(in: frame.resolvedTree)
    let run = try #require(links.first)
    #expect(links.count == 1)
    #expect(run.text == "Docs")
    #expect(run.style.foregroundStyle == .color(.yellow))
    #expect(run.style.emphasis.contains([.bold, .italic]))
    #expect(run.style.underlineStyle == nil)
    #expect(run.destination?.rawValue == "https://example.com")
    #expect(run.linkIdentifier == "InlineLink[0]")
    #expect(frame.semanticSnapshot.focusRegions.count == 1)
  }

  @Test(
    "link underline distinguishes inherited, hidden, and explicitly visible",
    arguments: [LinkUnderlineStyle.inherited, .hidden, .visible(.init(pattern: .dotted))])
  func underlinePolicy(_ underline: LinkUnderlineStyle) throws {
    let frame = DefaultRenderer().render(
      Text("\(Link("Docs", destination: "https://example.com"))").underline()
        .linkStyle(ConsumerLinkStyle(underline: underline)),
      context: .init(identity: testIdentity("Underline")))
    let run = try #require(allLinkRuns(in: frame.resolvedTree).first)
    switch underline {
    case .inherited: #expect(run.style.underlineStyle == .init(pattern: .solid))
    case .hidden: #expect(run.style.underlineStyle == nil)
    case .visible(let expected): #expect(run.style.underlineStyle == expected)
    }
  }

  @Test(
    "invalid indicator glyphs fall back independently and retain valid appearance",
    arguments: ["界", "", "ab", "\n"])
  func invalidGlyphs(glyph: String) {
    let frame = DefaultRenderer().render(
      ScrollView([.horizontal, .vertical]) {
        Text("01234567890123456789\nsecond row\nthird row\nfourth row\nfifth row")
      }.scrollViewStyle(ConsumerScrollViewStyle(verticalGlyph: glyph, horizontalGlyph: "=")),
      context: .init(identity: testIdentity("InvalidGlyphs")), proposal: .init(width: 10, height: 4)
    )
    let issues = frame.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }
    #expect(issues.count == 1)
    let text = frame.rasterSurface.lines.joined()
    #expect(text.contains("▐"))
    #expect(text.contains("="))
    #expect(!text.contains("界"))
  }

  @Test("custom scroll styling retains the host's press-capture policy", arguments: [false, true])
  func hostCapability(supportsPanning: Bool) throws {
    let identity = testIdentity("StyledHostCapability")
    var environment = EnvironmentValues()
    environment.pointerInputCapabilities = .init(supportsScrollPanning: supportsPanning)
    let snapshot = DefaultRenderer().render(
      ScrollView { Text(String(repeating: "content\n", count: 20)) }
        .id(identity).scrollViewStyle(ConsumerScrollViewStyle()),
      context: .init(identity: testIdentity("Root"), environmentValues: environment),
      proposal: .init(width: 12, height: 8))
    let region = try #require(
      snapshot.semanticSnapshot.interactionRegions.first { $0.identity == identity })
    #expect(region.captureOnPress == supportsPanning)
  }

  @Test("invalid scroll geometry and opacity preserve independent valid fields")
  func invalidFields() {
    let configuration = ScrollViewStyleConfiguration(
      axes: .vertical, visibleIndicatorAxes: .vertical, focusedIndicatorAxes: [],
      allowsDirectManipulation: false, isEnabled: true, styleEnvironment: .init())
    let presentation = validatedScrollPresentation(
      .init(
        snapshotLabel: "invalid", contentInsets: .init(all: Int.max),
        verticalIndicatorGlyph: "|", horizontalIndicatorGlyph: "=",
        indicatorStyle: .color(.red), opacity: .nan, reservesIndicatorSpace: false),
      configuration: configuration, styleLabel: "invalid", identity: testIdentity("InvalidFields"))
    let issues = ImperativeRuntimeIssueQueue.drain()
    #expect(issues.filter { $0.code == "style.invalidPresentation" }.count == 1)
    #expect(presentation.contentInsets == .zero)
    #expect(presentation.opacity == 1)
    #expect(presentation.verticalIndicatorGlyph == "|")
    #expect(presentation.horizontalIndicatorGlyph == "=")
    #expect(presentation.indicatorStyle == .color(.red))
    #expect(!presentation.reservesIndicatorSpace)
  }

  @Test("overlay indicators use the entire content viewport when calculating scroll range")
  func overlayMetrics() throws {
    let viewport = CellRect(origin: .zero, size: .init(width: 10, height: 8))
    let content = CellRect(origin: .zero, size: .init(width: 24, height: 24))
    let vertical = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: viewport, contentBounds: content, axes: [.horizontal, .vertical],
        axis: .vertical, reservesSpace: false))
    let horizontal = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: viewport, contentBounds: content, axes: [.horizontal, .vertical],
        axis: .horizontal, reservesSpace: false))
    #expect(vertical.viewportLength == 8)
    #expect(vertical.maxOffset == 16)
    #expect(horizontal.viewportLength == 10)
    #expect(horizontal.maxOffset == 14)
  }

  @Test(
    "styled scroll routes agree with insets, wheel clamping, and indicator dragging",
    arguments: [false, true])
  func styledGeometry(reservesSpace: Bool) throws {
    let box = StyledScrollPosition()
    let registry = LocalPointerHandlerRegistry()
    let identity = testIdentity("StyledScroll")
    var context = ResolveContext(identity: testIdentity("ScrollRoot"))
    context.localPointerHandlerRegistry = registry
    let snapshot = DefaultRenderer().render(
      ScrollView(
        [.horizontal, .vertical],
        position: .init(
          get: { box.offset }, set: { box.offset = $0 })
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<24) { _ in Text(String(repeating: "X", count: 30)) }
        }
      }
      .id(identity)
      .scrollViewStyle(ConsumerScrollViewStyle(reservesSpace: reservesSpace))
      .frame(width: 12, height: 8),
      context: context, proposal: .init(width: 12, height: 8))
    let route = try #require(
      snapshot.semanticSnapshot.scrollRoutes.first { $0.identity == identity })
    let viewportWidth = reservesSpace ? 9 : 10
    let viewportHeight = reservesSpace ? 5 : 6
    #expect(route.viewportRect.origin == .init(x: 1, y: 1))
    #expect(route.viewportRect.size == .init(width: viewportWidth, height: viewportHeight))
    #expect(route.contentBounds.size == .init(width: 30, height: 24))
    let scrollContext = LocalPointerScrollContext(
      viewportRect: route.viewportRect, contentBounds: route.contentBounds)
    let body = try #require(
      snapshot.semanticSnapshot.interactionRegions.first { $0.identity == identity })
    #expect(
      registry.dispatch(
        routeID: body.routeID,
        event: .init(
          kind: .scrolled(deltaX: 1000, deltaY: 1000),
          location: .cellFallback(.init(x: 2, y: 2)), targetRect: body.rect,
          scrollContext: scrollContext)
      ).wantsPointerStream)
    #expect(box.offset == .init(x: 30 - viewportWidth, y: 24 - viewportHeight))
    for axis in [ScrollIndicatorAxis.vertical, .horizontal] {
      let indicatorID =
        axis == .vertical
        ? verticalScrollIndicatorIdentity(for: identity)
        : horizontalScrollIndicatorIdentity(for: identity)
      let region = try #require(
        snapshot.semanticSnapshot.interactionRegions.first { $0.identity == indicatorID })
      #expect(region.rect.origin == (axis == .vertical ? .init(x: 10, y: 1) : .init(x: 1, y: 6)))
      #expect(
        registry.dispatch(
          routeID: region.routeID,
          event: .init(
            kind: .dragged(.primary), location: .cellFallback(region.rect.origin),
            targetRect: region.rect, scrollContext: scrollContext)
        ).wantsPointerStream)
    }
    #expect(box.offset == .zero)
    let text = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("|"))
    #expect(text.contains("-"))
    #expect(snapshot.rasterSurface.lines.first?.allSatisfy { $0 == " " } == true)
  }

  @Test("a scroll style cannot reveal indicators hidden by policy", arguments: [false, true])
  func hiddenIndicators(reservesSpace: Bool) throws {
    let identity = testIdentity("HiddenStyledScroll")
    let snapshot = DefaultRenderer().render(
      ScrollView([.horizontal, .vertical]) {
        Text(String(repeating: "long content line\n", count: 12))
      }.id(identity)
        .scrollViewStyle(ConsumerScrollViewStyle(reservesSpace: reservesSpace))
        .scrollIndicators(.hidden),
      context: .init(identity: testIdentity("Root")), proposal: .init(width: 12, height: 8))
    let route = try #require(
      snapshot.semanticSnapshot.scrollRoutes.first { $0.identity == identity })
    #expect(route.viewportRect.size == .init(width: 10, height: 6))
    #expect(
      !snapshot.semanticSnapshot.interactionRegions.contains {
        $0.identity == verticalScrollIndicatorIdentity(for: identity)
          || $0.identity == horizontalScrollIndicatorIdentity(for: identity)
      })
    #expect(!snapshot.rasterSurface.lines.joined().contains("|"))
  }

  @Test("automatic reserved tracks cannot be erased by overflowing content")
  func automaticTrackClipping() {
    let snapshot = DefaultRenderer().render(
      ScrollView([.horizontal, .vertical]) {
        VStack(spacing: 0) { ForEach(0..<24) { _ in Text(String(repeating: "X", count: 30)) } }
      }, context: .init(identity: testIdentity("AutomaticTrack")),
      proposal: .init(width: 12, height: 8))
    let text = snapshot.rasterSurface.lines.joined()
    #expect(text.contains("▐"))
    #expect(text.contains("▂"))
    #expect(snapshot.rasterSurface.lines.last?.contains("X") == false)
    #expect(snapshot.rasterSurface.cells.allSatisfy { $0.last?.character != "X" })
  }

  @Test("rich link styling preserves literals, wrapping, and distinct action regions")
  func multipleRichLinks() throws {
    let first = Link("First docs", destination: "https://example.com/first")
    let second = Link("Second docs", destination: "https://example.com/second")
    let content = Text("Read \(first) and \(second) now").foregroundStyle(.red).opacity(0.5)
    let context = ResolveContext(identity: testIdentity("RichLinks"))
    let proposal = ProposedViewSize(width: 12, height: 8)
    let baseline = DefaultRenderer().render(content, context: context, proposal: proposal)
    let styled = DefaultRenderer().render(
      content.linkStyle(
        ConsumerLinkStyle(underline: .hidden, foreground: .color(.green), opacity: 0.5)),
      context: context, proposal: proposal)
    #expect(styled.rasterSurface.lines == baseline.rasterSurface.lines)
    #expect(styled.rasterSurface.lines.count > 1)
    let runs = allRichRuns(in: styled.resolvedTree)
    let links = runs.filter { $0.destination != nil }
    #expect(links.count == 2)
    #expect(Set(links.compactMap(\.linkIdentifier)).count == 2)
    #expect(
      links.allSatisfy { $0.style.foregroundStyle == .color(.green) && $0.style.opacity == 0.5 })
    #expect(
      runs.filter { $0.destination == nil }.allSatisfy {
        $0.style.foregroundStyle == .color(.red) && $0.style.opacity == 1
      })
    // View.opacity compounds at draw time. Rasterization then bakes that
    // opacity into the color and resets the stored cell opacity to one.
    let drawn = drawnRichRuns(in: styled.drawTree)
    #expect(drawn.count == runs.count)
    #expect(drawn.filter { $0.destination != nil }.allSatisfy { $0.style.opacity == 0.25 })
    #expect(drawn.filter { $0.destination == nil }.allSatisfy { $0.style.opacity == 0.5 })
    #expect(styled.semanticSnapshot.focusRegions.count == 2)
    #expect(Set(styled.semanticSnapshot.interactionRegions.map(\.identity)).count == 2)
  }

  @Test("custom scroll insets preserve wheel chaining at a nested boundary")
  func nestedWheelChaining() throws {
    let outer = StyledScrollPosition()
    let inner = StyledScrollPosition()
    inner.offset.y = 5
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StyledNestedWheel"), size: .init(width: 40, height: 12)
    ) {
      ScrollView(.vertical, position: .init(get: { outer.offset }, set: { outer.offset = $0 })) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Outer header")
          ScrollView(.vertical, position: .init(get: { inner.offset }, set: { inner.offset = $0 }))
          {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<8) { Text("Inner \($0)") }
            }
          }.scrollIndicators(.hidden).frame(width: 24, height: 5)
          ForEach(0..<10) { Text("Outer tail \($0)") }
        }
      }.scrollIndicators(.hidden).frame(width: 28, height: 8)
        .scrollViewStyle(ConsumerScrollViewStyle())
    }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "Inner 6"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    #expect(inner.offset.y == 5)
    #expect(outer.offset.y == 1)
  }

  @Test(
    "custom link styles preserve pointer, keyboard, and disabled action routing",
    arguments: [false, true])
  func linkActions(inline: Bool) throws {
    let probe = StyledLinkProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StyledLinkJourney"), size: .init(width: 40, height: 8)
    ) {
      VStack {
        if inline {
          Text("See \(Link("Docs", destination: "https://example.com")) now")
        } else {
          Link("Docs", destination: "https://example.com")
        }
        Link("Disabled", destination: "https://example.org").disabled(true)
      }
      .linkStyle(ConsumerLinkStyle(underline: .hidden, foreground: .color(.yellow)))
      .environment(
        \.openLinkAction,
        OpenLinkAction { destination in
          probe.destinations.append(destination)
          return true
        })
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Docs")
    #expect(probe.destinations == ["https://example.com"])
    let identity = try harness.focusIdentity(forText: "Docs")
    _ = try harness.focus(identity)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(probe.destinations == ["https://example.com", "https://example.com"])
    _ = try harness.clickText("Disabled")
    #expect(probe.destinations.count == 2)
  }

  private func allLinkRuns(in node: ResolvedNode) -> [RichTextRun] {
    allRichRuns(in: node).filter { $0.destination != nil }
  }

  private func allRichRuns(in node: ResolvedNode) -> [RichTextRun] {
    let own: [RichTextRun]
    if case .richText(let payload) = node.drawPayload {
      own = payload.runs
    } else {
      own = []
    }
    return own + node.children.flatMap { allRichRuns(in: $0) }
  }

  private func drawnRichRuns(in node: DrawNode) -> [RichTextRun] {
    node.commands.flatMap { command -> [RichTextRun] in
      if case .richText(_, let payload, _, _, _) = command { return payload.runs }
      return []
    } + node.children.flatMap { drawnRichRuns(in: $0) }
  }
}

@MainActor
private final class StyledScrollPosition {
  var offset = ScrollCellOffset.zero
}

@MainActor
private final class StyledLinkProbe {
  var destinations: [LinkDestination] = []
}

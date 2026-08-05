import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Ambient-propagation contract, Stage 0 (org root
// docs/plans/2026-08-04-001-ambient-propagation-contract-plan.md): rendered
// pins for the target semantics.
//
// - `lineLimit`/`truncationMode` are environment-backed: a container write
//   reaches every descendant text run, the innermost write wins, and `nil`
//   clears. Verified against real SwiftUI on macOS (2026-08-05).
// - `.opacity` is a multiplicative draw cascade: the effective opacity of any
//   emitted command is the product of the `.opacity` factors on its ancestor
//   chain, so an explicit reset is impossible.
// - `View.underline()`/`.strikethrough()` propagate to descendant text with
//   node-over-environment precedence; an explicit `Text.underline(false)`
//   wins over the inherited style (verified against real SwiftUI).
@MainActor
@Suite
struct AmbientPropagationContractTests {
  private struct EmittedText {
    var content: String
    var style: TextStyle
    var lineLimit: Int?
    var truncationMode: TextTruncationMode
  }

  private func flattenedCommands(in root: DrawNode) -> [DrawCommand] {
    var commands: [DrawCommand] = []
    func visit(_ command: DrawCommand) {
      switch command {
      case .group(_, let children):
        for child in children {
          visit(child)
        }
      case .clip(_, let child):
        visit(child)
      default:
        commands.append(command)
      }
    }
    func walk(_ node: DrawNode) {
      for command in node.commands {
        visit(command)
      }
      for command in node.postCommands {
        visit(command)
      }
      for child in node.children {
        walk(child)
      }
    }
    walk(root)
    return commands
  }

  private func emittedTexts(in root: DrawNode) -> [EmittedText] {
    flattenedCommands(in: root).compactMap { command in
      guard
        case .text(_, let content, let style, let lineLimit, let truncationMode, _) = command
      else {
        return nil
      }
      return EmittedText(
        content: content,
        style: style,
        lineLimit: lineLimit,
        truncationMode: truncationMode
      )
    }
  }

  private func fillStyles(in root: DrawNode) -> [AnyShapeStyle] {
    flattenedCommands(in: root).compactMap { command in
      guard case .fill(_, _, _, let style, _) = command else {
        return nil
      }
      return style
    }
  }

  // MARK: - Text-layout attributes

  @Test("container lineLimit reaches every descendant text command")
  func containerLineLimitReachesDescendantTextCommands() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma")
        Text("one two three")
      }
      .lineLimit(1),
      context: .init(identity: testIdentity("ContainerLimit"))
    )

    let texts = emittedTexts(in: artifacts.drawTree)
    #expect(texts.count == 2)
    #expect(texts.allSatisfy { $0.lineLimit == 1 })
  }

  @Test("container lineLimit clamps wrapped descendant text in the rendered surface")
  func containerLineLimitClampsRenderedText() {
    let unlimited = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma delta")
      },
      context: .init(identity: testIdentity("Unlimited")),
      proposal: .init(width: .finite(8), height: .unspecified)
    )
    let clamped = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma delta")
      }
      .lineLimit(1),
      context: .init(identity: testIdentity("Clamped")),
      proposal: .init(width: .finite(8), height: .unspecified)
    )

    #expect(unlimited.rasterSurface.lines.count > 1)
    #expect(clamped.rasterSurface.lines.count == 1)
  }

  @Test("truncationMode inherits from a container onto descendant text commands")
  func truncationModeInheritsFromContainer() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma")
      }
      .truncationMode(.head),
      context: .init(identity: testIdentity("TruncationInherits"))
    )

    #expect(emittedTexts(in: artifacts.drawTree).first?.truncationMode == .head)
  }

  private struct AmbientLimitRoot: View {
    let dynamic: String
    let limit: Int?

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Header")
        Text(dynamic)
      }
      .lineLimit(limit)
    }
  }

  @Test("unchanged ambient lineLimit keeps memo reuse; a changed value re-resolves the subtree")
  func ambientLineLimitReuseBehavior() {
    func secondFrame(limit1: Int?, limit2: Int?) -> RenderSnapshot {
      let renderer = DefaultRenderer(
        layoutEngine: .init(cache: MeasurementCache())
      )
      let root = testIdentity("ReuseRoot")
      _ = renderer.render(
        AmbientLimitRoot(dynamic: "v1", limit: limit1),
        context: .init(identity: root)
      )
      return renderer.render(
        AmbientLimitRoot(dynamic: "v2", limit: limit2),
        context: .init(identity: root, invalidatedIdentities: [root])
      )
    }

    // Same ambient value on both frames: the unchanged `Text("Header")` is
    // the tree's one memo candidate and must keep reusing — the environment
    // write may not poison snapshot equality.
    let unchanged = secondFrame(limit1: 2, limit2: 2)
    #expect(unchanged.diagnostics.work.resolvedNodesReused == 1)

    // A changed ambient value re-resolves the writer's whole subtree (the
    // coarse snapshot gate) and the new value reaches every text leaf.
    let changed = secondFrame(limit1: 2, limit2: 3)
    #expect(changed.diagnostics.work.resolvedNodesReused == 0)
    #expect(emittedTexts(in: changed.drawTree).allSatisfy { $0.lineLimit == 3 })
  }

  // MARK: - Opacity cascade

  @Test("container opacity fades every descendant draw command")
  func containerOpacityFadesDescendantCommands() {
    let plain = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Hi")
        Rectangle().fill(Color.red).frame(width: 3, height: 1)
      },
      context: .init(identity: testIdentity("PlainFade"))
    )
    let faded = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Hi")
        Rectangle().fill(Color.red).frame(width: 3, height: 1)
      }
      .opacity(0.5),
      context: .init(identity: testIdentity("ContainerFade"))
    )

    #expect(emittedTexts(in: plain.drawTree).first?.style.opacity == 1.0)
    #expect(emittedTexts(in: faded.drawTree).first?.style.opacity == 0.5)

    let plainFills = fillStyles(in: plain.drawTree)
    let fadedFills = fillStyles(in: faded.drawTree)
    #expect(!plainFills.isEmpty)
    #expect(fadedFills == plainFills.map { $0.opacity(0.5) })
  }

  @Test("nested container opacities multiply")
  func nestedContainerOpacitiesMultiply() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Hi")
        }
        .opacity(0.5)
      }
      .opacity(0.4),
      context: .init(identity: testIdentity("NestedFade"))
    )

    let opacity = emittedTexts(in: artifacts.drawTree).first?.style.opacity
    #expect(opacity != nil)
    if let opacity {
      #expect(abs(opacity - 0.2) < 0.0001)
    }
  }

  @Test("an explicit opacity reset multiplies instead of replacing")
  func explicitOpacityResetMultiplies() {
    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .opacity(0.4)
        .opacity(1.0),
      context: .init(identity: testIdentity("ResetFade"))
    )

    #expect(emittedTexts(in: artifacts.drawTree).first?.style.opacity == 0.4)
  }

  @Test("an ancestor-only opacity change repaints descendants through the retained pipeline")
  func ancestorOnlyOpacityChangeRepaintsDescendants() {
    let renderer = DefaultRenderer()
    let root = testIdentity("FadeRoot")

    let first = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Steady")
      }
      .opacity(1.0),
      context: .init(identity: root)
    )
    let second = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Steady")
      }
      .opacity(0.5),
      context: .init(identity: root, invalidatedIdentities: [root])
    )

    // The draw tree is the retained-extraction product: a stale reuse of the
    // descendant subtree would keep serving the frame-one command.
    #expect(emittedTexts(in: first.drawTree).first?.style.opacity == 1.0)
    #expect(emittedTexts(in: second.drawTree).first?.style.opacity == 0.5)
    // The committed surface must repaint the faded text: fractional opacity is
    // baked into the foreground color as a dedicated style run.
    #expect(!second.rasterSurface.styleRuns.isEmpty)
  }

  // MARK: - Underline / strikethrough propagation

  @Test("ancestor underline reaches descendant text")
  func ancestorUnderlineReachesDescendantText() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Hi")
      }
      .underline(),
      context: .init(identity: testIdentity("AmbientUnderline"))
    )

    #expect(emittedTexts(in: artifacts.drawTree).first?.style.underlineStyle != nil)
  }

  @Test("an explicitly cleared text underline wins over an inherited one")
  func explicitlyClearedTextUnderlineWinsOverInherited() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Hi").underline(false)
      }
      .underline(),
      context: .init(identity: testIdentity("ClearedUnderline"))
    )

    #expect(emittedTexts(in: artifacts.drawTree).first?.style.underlineStyle == nil)
  }

  @Test("a directly styled text underline wins over the inherited style")
  func directlyStyledTextUnderlineWinsOverInherited() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Hi").underline(pattern: .dash, color: .yellow)
      }
      .underline(color: .red),
      context: .init(identity: testIdentity("DirectUnderline"))
    )

    #expect(
      emittedTexts(in: artifacts.drawTree).first?.style.underlineStyle
        == .init(pattern: .dash, color: .yellow)
    )
  }

  @Test("ancestor strikethrough reaches descendant text")
  func ancestorStrikethroughReachesDescendantText() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Hi")
      }
      .strikethrough(),
      context: .init(identity: testIdentity("AmbientStrikethrough"))
    )

    #expect(emittedTexts(in: artifacts.drawTree).first?.style.strikethroughStyle != nil)
  }
}

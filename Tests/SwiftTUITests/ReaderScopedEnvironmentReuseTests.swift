import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The reader-scoped environment toleration: a reuse door may serve a subtree
/// across an `.environment` change when the changed key is reader-attributed
/// only and nothing in the subtree reads or writes it.
///
/// The fixture key is declared in the *test* module on purpose — that is what
/// makes it reader-attributed-only. Keys declared inside the framework are also
/// read *without* attribution (style extraction, the `[untracked:]` text
/// attributes), so the classification excludes them by default and the
/// toleration must never fire for them. The individually *certified* framework
/// keys (button style, the scroll-indicator visibility pair) are the
/// exception — every consumer reads them through the tracked subscript at
/// resolve — and they are pinned in their own section below.
private enum ReaderScopedThemeKey: EnvironmentKey {
  static let defaultValue = "base"
}

extension EnvironmentValues {
  fileprivate var readerScopedTheme: String {
    get { self[ReaderScopedThemeKey.self] }
    set { self[ReaderScopedThemeKey.self] = newValue }
  }
}

/// Flips a body between reading and not reading the themed key.
///
/// Deliberately a plain class, not `@Observable`: reading it records no
/// dependency at all, which is the exact shape of the hole under test. The
/// first resolve records *no* environment read for the theme key, so the reader
/// index cannot deny the serve — and a later re-run reads the key for the first
/// time.
@MainActor
private final class ConditionalReadToggle {
  var readsTheme = false
}

private struct ThemeReader: View {
  @Environment(\.readerScopedTheme) private var theme

  var body: some View {
    Text("theme:\(theme)")
  }
}

/// A conditional read: `@Environment` wrappers update unconditionally, so the
/// only way a body can read a key it did not read before is for the reading
/// *view* to appear. That is what makes the read invisible to the reader index
/// that authorized the serve.
private struct ConditionalReader: View {
  let toggle: ConditionalReadToggle

  var body: some View {
    if toggle.readsTheme {
      ThemeReader()
    } else {
      Text("theme:unread")
    }
  }
}

/// A button style whose body stamps a recognizable tag, so a rendered frame
/// shows *which* style resolved a button — the observable a stale serve would
/// corrupt.
private struct TaggedButtonStyle: ButtonStyle {
  let tag: String

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack(spacing: 0) {
      Text("style[\(tag)]")
      configuration.label
    }
  }
}

/// A read-free `Equatable` memo boundary whose value never changes across the
/// frames under test, so the gate's value compare always passes and the
/// environment verdict is the only thing that can deny the serve.
private struct Boundary<Content: View>: View, Equatable {
  let content: Content

  // The memo comparator runs off the authoring actor, so the conformance must
  // be `nonisolated`.
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    true
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("boundary")
      content
    }
  }
}

@MainActor
@Suite("Reader-scoped environment reuse")
struct ReaderScopedEnvironmentReuseTests {
  @Test("prompt declarations read style even while closed", arguments: [false, true])
  func promptStyleReaderIsDenied(presented: Bool) {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      let presented: Bool
      var body: some View {
        VStack {
          Boundary(content: Text("anchor").alert("Title", isPresented: .constant(presented)))
          Text(tag)
        }
        .promptStyle(TaggedPortalStyle(tag: tag))
      }
    }
    _ = renderer.render(
      Root(tag: "a", presented: presented), context: .init(identity: rootIdentity))
    _ = renderer.render(
      Root(tag: "b", presented: presented),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(!toleratedBoundary(in: renderer))
  }

  @Test("fullScreenCover declarations read style even while closed", arguments: [false, true])
  func fullScreenCoverStyleReaderIsDenied(presented: Bool) {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      let presented: Bool
      var body: some View {
        VStack {
          Boundary(
            content: Text("anchor").fullScreenCover(isPresented: .constant(presented)) {
              Text("Cover")
            })
          Text(tag)
        }
        .fullScreenCoverStyle(TaggedPortalStyle(tag: tag))
      }
    }
    _ = renderer.render(
      Root(tag: "a", presented: presented), context: .init(identity: rootIdentity))
    _ = renderer.render(
      Root(tag: "b", presented: presented),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(!toleratedBoundary(in: renderer))
  }

  @Test("popover declarations read style even while closed", arguments: [false, true])
  func popoverStyleReaderIsDenied(presented: Bool) {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      let presented: Bool
      var body: some View {
        VStack {
          Boundary(
            content: Text("anchor").popover(isPresented: .constant(presented)) { Text("Details") })
          Text(tag)
        }
        .popoverStyle(TaggedPortalStyle(tag: tag))
      }
    }
    _ = renderer.render(
      Root(tag: "a", presented: presented), context: .init(identity: rootIdentity))
    _ = renderer.render(
      Root(tag: "b", presented: presented),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(!toleratedBoundary(in: renderer))
  }

  @Test("prompt style unread change is tolerated")
  func promptStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      var body: some View {
        VStack {
          Boundary(content: Text("plain"))
          Text(tag)
        }
        .promptStyle(TaggedPortalStyle(tag: tag))
      }
    }
    _ = renderer.render(Root(tag: "a"), context: .init(identity: rootIdentity))
    _ = renderer.render(
      Root(tag: "b"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("fullScreenCover style unread change is tolerated")
  func fullScreenCoverStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      var body: some View {
        VStack {
          Boundary(content: Text("plain"))
          Text(tag)
        }
        .fullScreenCoverStyle(TaggedPortalStyle(tag: tag))
      }
    }
    _ = renderer.render(Root(tag: "a"), context: .init(identity: rootIdentity))
    _ = renderer.render(
      Root(tag: "b"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("popover style unread change is tolerated")
  func popoverStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      var body: some View {
        VStack {
          Boundary(content: Text("plain"))
          Text(tag)
        }
        .popoverStyle(TaggedPortalStyle(tag: tag))
      }
    }
    _ = renderer.render(Root(tag: "a"), context: .init(identity: rootIdentity))
    _ = renderer.render(
      Root(tag: "b"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("menu style unread change is tolerated")
  func menuStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      var body: some View {
        VStack {
          Boundary(content: Text("plain"))
          Text(tag)
        }
        .menuStyle(TaggedMenuStyle(tag: tag))
      }
    }
    _ = renderer.render(Root(tag: "OldStyle"), context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(tag: "NewStyle"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("NewStyle"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("menu style reader restyles")
  func menuStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      var body: some View {
        VStack {
          Boundary(content: Menu("Commands") { Text("Item") })
          Text("tail")
        }
        .menuStyle(TaggedMenuStyle(tag: tag))
      }
    }
    _ = renderer.render(Root(tag: "OldStyle"), context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(tag: "NewStyle"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let text = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("NewStyle"))
    #expect(!text.contains("OldStyle"))
    #expect(!toleratedBoundary(in: renderer))
  }

  @Test("control group style unread change is tolerated")
  func controlGroupStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      var body: some View {
        VStack {
          Boundary(content: Text("plain"))
          Text(tag)
        }
        .controlGroupStyle(TaggedControlGroupStyle(tag: tag))
      }
    }
    _ = renderer.render(Root(tag: "OldStyle"), context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(tag: "NewStyle"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("NewStyle"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("control group style reader restyles")
  func controlGroupStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let tag: String
      var body: some View {
        VStack {
          Boundary(content: ControlGroup { Text("Item") })
          Text("tail")
        }
        .controlGroupStyle(TaggedControlGroupStyle(tag: tag))
      }
    }
    _ = renderer.render(Root(tag: "OldStyle"), context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(tag: "NewStyle"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let text = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("NewStyle"))
    #expect(!text.contains("OldStyle"))
    #expect(!toleratedBoundary(in: renderer))
  }

  @Test("slider style unread change is tolerated")
  func sliderStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnySliderStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }.sliderStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerSliderStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerSliderStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("slider style reader restyles")
  func sliderStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnySliderStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Slider("Level", value: .constant(5), in: 0...10))
          Text(dynamic)
        }.sliderStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerSliderStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerSliderStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("stepper style unread change is tolerated")
  func stepperStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyStepperStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }.stepperStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerStepperStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerStepperStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("stepper style reader restyles")
  func stepperStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyStepperStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Stepper("Count", value: .constant(5), in: 0...10))
          Text(dynamic)
        }.stepperStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerStepperStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerStepperStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("toggle style unread change is tolerated")
  func toggleStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyToggleStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }.toggleStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerToggleStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerToggleStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("toggle style reader restyles")
  func toggleStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyToggleStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Toggle("Switch", isOn: .constant(false)))
          Text(dynamic)
        }.toggleStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerToggleStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerToggleStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("disclosureGroup style unread change is tolerated")
  func disclosureGroupStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyDisclosureGroupStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }.disclosureGroupStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerDisclosureGroupStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerDisclosureGroupStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("disclosureGroup style reader restyles")
  func disclosureGroupStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyDisclosureGroupStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(
            content: DisclosureGroup("Details", isExpanded: .constant(true)) { Text("Child") })
          Text(dynamic)
        }.disclosureGroupStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerDisclosureGroupStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerDisclosureGroupStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("textEditor style unread change is tolerated")
  func textEditorStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyTextEditorStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }.textEditorStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerTextEditorStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerTextEditorStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("textEditor style reader restyles")
  func textEditorStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyTextEditorStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: TextEditor(text: .constant("Text")))
          Text(dynamic)
        }.textEditorStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerTextEditorStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerTextEditorStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("progressView style unread change is tolerated")
  func progressViewStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyProgressViewStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }.progressViewStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerProgressViewStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerProgressViewStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("progressView style reader restyles")
  func progressViewStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyProgressViewStyle
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ProgressView(value: 0.5))
          Text(dynamic)
        }.progressViewStyle(style)
      }
    }
    _ = renderer.render(
      Root(style: .init(ConsumerProgressViewStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: .init(ConsumerProgressViewStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("a label-style change over a reader-free subtree is tolerated")
  func labelStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyLabelStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .labelStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: AnyLabelStyle(ConsumerLabelStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: AnyLabelStyle(ConsumerLabelStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("a label-style change with a reader restyles the subtree")
  func labelStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyLabelStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Label("Title") { Text("*") })
          Text(dynamic)
        }
        .labelStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: AnyLabelStyle(ConsumerLabelStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: AnyLabelStyle(ConsumerLabelStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("a labeledContent-style change over a reader-free subtree is tolerated")
  func labeledContentStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyLabeledContentStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .labeledContentStyle(style)
      }
    }

    _ = renderer.render(
      Root(
        style: AnyLabeledContentStyle(ConsumerLabeledContentStyle(prefix: "OldStyle")),
        dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(
        style: AnyLabeledContentStyle(ConsumerLabeledContentStyle(prefix: "NewStyle")),
        dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("a labeledContent-style change with a reader restyles the subtree")
  func labeledContentStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyLabeledContentStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: LabeledContent("Name", value: "Ada"))
          Text(dynamic)
        }
        .labeledContentStyle(style)
      }
    }

    _ = renderer.render(
      Root(
        style: AnyLabeledContentStyle(ConsumerLabeledContentStyle(prefix: "OldStyle")),
        dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(
        style: AnyLabeledContentStyle(ConsumerLabeledContentStyle(prefix: "NewStyle")),
        dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }

  @Test("a groupBox-style change over a reader-free subtree is tolerated")
  func groupBoxStyleUnreadChangeIsTolerated() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyGroupBoxStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .groupBoxStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: AnyGroupBoxStyle(ConsumerGroupBoxStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: AnyGroupBoxStyle(ConsumerGroupBoxStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("a groupBox-style change with a reader restyles the subtree")
  func groupBoxStyleReaderRestyles() {
    let renderer = makeRenderer()
    struct Root: View {
      let style: AnyGroupBoxStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: GroupBox("Group") { Text("Value") })
          Text(dynamic)
        }
        .groupBoxStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: AnyGroupBoxStyle(ConsumerGroupBoxStyle(prefix: "OldStyle")), dynamic: "v1"),
      context: .init(identity: rootIdentity))
    let frame = renderer.render(
      Root(style: AnyGroupBoxStyle(ConsumerGroupBoxStyle(prefix: "NewStyle")), dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity]))

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("v2"))
    #expect(!toleratedBoundary(in: renderer))
    #expect(rendered.contains("NewStyle"))
    #expect(!rendered.contains("OldStyle"))
  }
  private let rootIdentity = testIdentity("Root")
  /// Every fixture below puts `Boundary` in the root stack's first slot, so the
  /// boundary under test always resolves here.
  private let boundaryIdentity = testIdentity("Root", "VStack[0]")

  private func makeRenderer() -> DefaultRenderer {
    DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
  }

  /// Whether the boundary was served *by toleration* — the only externally
  /// visible difference between "the door matched" and "the door tolerated".
  /// Aggregate reuse counts cannot tell them apart: a denied boundary's
  /// read-free siblings are tolerated regardless.
  private func toleratedBoundary(in renderer: DefaultRenderer) -> Bool {
    renderer.viewGraph.environmentDriftBoundaryIdentities.contains(boundaryIdentity)
  }

  // MARK: - The win

  /// A themed `.environment` write above a read-free boundary changes value.
  /// Nothing under the boundary reads the key, so the whole subtree is served
  /// instead of re-descending.
  @Test("an unread environment change no longer denies the memo door")
  func unreadEnvironmentChangeServesTheSubtree() {
    let renderer = makeRenderer()
    let toggle = ConditionalReadToggle()

    struct Root: View {
      let theme: String
      let toggle: ConditionalReadToggle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ConditionalReader(toggle: toggle))
          Text(dynamic)
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base", toggle: toggle, dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(theme: "dark", toggle: toggle, dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("boundary"))
    #expect(rendered.contains("theme:unread"))
    #expect(rendered.contains("v2"))
    #expect(!rendered.contains("v1"))
    // The boundary's whole subtree is served across the environment change.
    #expect(toleratedBoundary(in: renderer))
    #expect(frame.diagnostics.work.resolvedNodesReused > 1)
  }

  // MARK: - Soundness

  /// The reader index is what authorizes the serve. A subtree that *does* read
  /// the changed key must be denied and must show the new value.
  @Test("a subtree that reads the changed key is denied")
  func readerInSubtreeDeniesTheServe() {
    let renderer = makeRenderer()

    struct Root: View {
      let theme: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ThemeReader())
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(theme: "dark"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("theme:dark"))
    #expect(!rendered.contains("theme:base"))
    #expect(!toleratedBoundary(in: renderer))
  }

  /// An interior writer makes its subtree's value authored rather than
  /// inherited, so the boundary's change says nothing about it — including the
  /// case no diff can see, where the interior write authors the boundary's
  /// prior value.
  @Test("an interior writer of the changed key denies the serve")
  func interiorWriterDeniesTheServe() {
    let renderer = makeRenderer()

    struct Root: View {
      let theme: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(
            content: Text("inner")
              .environment(\.readerScopedTheme, "interior")
          )
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base"),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(theme: "dark"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(!toleratedBoundary(in: renderer))
  }

  /// Uncertified framework-declared keys are consumed without read
  /// attribution — `lineLimit` is read through `[untracked:]` by the text
  /// pipeline — so no reader-set argument holds for them and the toleration
  /// must never fire.
  @Test("an uncertified framework-declared key change is never tolerated")
  func frameworkKeyChangeIsNeverTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let limit: Int

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("inner"))
        }
        .lineLimit(limit)
      }
    }

    _ = renderer.render(
      Root(limit: 1),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(limit: 2),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(renderer.viewGraph.environmentDriftBoundaryIdentities.isEmpty)
  }

  // MARK: - The conditional-read repair

  /// The hole the drift repair exists to close.
  ///
  /// Frame 1 resolves a subtree that does not read the themed key, so no reader
  /// edge is recorded. Frame 2 changes the key above it; the memo door sees no
  /// reader and serves — stranding every evaluator closure captured inside the
  /// subtree on the prior value. Frame 3 re-runs one of those closures on the
  /// dirty frontier, and its body reads the key *for the first time*. It must
  /// observe the current value; the reader index that authorized the serve
  /// could never have predicted this read.
  @Test("a first-time read after a tolerated serve observes the current value")
  func conditionalReadAfterToleratedServeObservesCurrentValue() throws {
    let renderer = makeRenderer()
    let toggle = ConditionalReadToggle()
    var rootBodyEvaluations = 0

    struct Root: View {
      let theme: String
      let toggle: ConditionalReadToggle
      let onBodyEvaluation: () -> Void

      var body: some View {
        let _ = onBodyEvaluation()
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ConditionalReader(toggle: toggle))
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base", toggle: toggle, onBodyEvaluation: { rootBodyEvaluations += 1 }),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(theme: "dark", toggle: toggle, onBodyEvaluation: { rootBodyEvaluations += 1 }),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )
    // Frame 2 must actually have tolerated the boundary, or frame 3 proves
    // nothing about the repair.
    #expect(toleratedBoundary(in: renderer))

    // The `false` arm of `ConditionalReader`'s builder condition — the node
    // whose re-run flips the branch and performs the first read.
    let readerIdentity = try #require(
      renderer.viewGraph.debugTotalStateSnapshot().identityByNodeID.values
        .first { $0.components.last == "false" },
      "could not locate the conditional reader's branch node"
    )

    toggle.readsTheme = true
    renderer.enableSelectiveEvaluation()
    let evaluationsBeforeFrameThree = rootBodyEvaluations
    let frame = renderer.render(
      Root(theme: "dark", toggle: toggle, onBodyEvaluation: { rootBodyEvaluations += 1 }),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [readerIdentity]
      )
    )

    // Guard against a vacuous pass: if the root body re-ran, the reader would
    // have been rebuilt from a fresh context and the repair never exercised.
    #expect(rootBodyEvaluations == evaluationsBeforeFrameThree)

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("theme:dark"))
    #expect(!rendered.contains("theme:base"))
  }

  // MARK: - Certified framework keys

  /// `ButtonStyleKey` is certified: its only consumer is `Button`'s resolve,
  /// a tracked read. A style change above a button-free subtree is therefore
  /// exactly the reader-scoped win — the subtree is served, not re-descended.
  @Test("a button-style change over a button-free subtree is tolerated")
  func buttonStyleChangeOverButtonFreeSubtreeIsTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let tag: String
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .buttonStyle(TaggedButtonStyle(tag: tag))
      }
    }

    _ = renderer.render(
      Root(tag: "a", dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(tag: "b", dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("boundary"))
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
    #expect(frame.diagnostics.work.resolvedNodesReused > 1)
  }

  /// The soundness half of the certification: a subtree that *contains* a
  /// button reads the key at the button's resolve, so the door must deny and
  /// the button must visibly restyle.
  @Test("a button-style change with a button in the subtree is denied and restyles")
  func buttonStyleChangeWithButtonInSubtreeRestyles() {
    let renderer = makeRenderer()

    struct Root: View {
      let tag: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Button("press") {})
        }
        .buttonStyle(TaggedButtonStyle(tag: tag))
      }
    }

    _ = renderer.render(
      Root(tag: "a"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(tag: "b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("style[b]"))
    #expect(!rendered.contains("style[a]"))
    #expect(!toleratedBoundary(in: renderer))
  }

  /// The scroll-indicator pair travels together: `scrollIndicators(_:axes:)`
  /// writes both axis keys by default, so the diff carries both and the serve
  /// requires both to be certified.
  @Test("a scroll-indicator visibility change over a scroll-free subtree is tolerated")
  func scrollIndicatorVisibilityChangeOverScrollFreeSubtreeIsTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let visibility: ScrollIndicatorVisibility
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .scrollIndicators(visibility)
      }
    }

    _ = renderer.render(
      Root(visibility: .visible, dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(visibility: .hidden, dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("boundary"))
    #expect(rendered.contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  /// A scroll view inside the boundary reads the vertical indicator key at
  /// its resolve, so the visibility flip must re-descend the subtree.
  @Test("a scroll-indicator visibility change with a scroll view in the subtree is denied")
  func scrollIndicatorVisibilityChangeWithScrollViewIsDenied() {
    let renderer = makeRenderer()

    struct Root: View {
      let visibility: ScrollIndicatorVisibility

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ScrollView { Text("inner") })
        }
        .scrollIndicators(visibility)
      }
    }

    _ = renderer.render(
      Root(visibility: .visible),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(visibility: .hidden),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(!toleratedBoundary(in: renderer))
  }

  /// `ListStyleKey` and `TableStyleKey` are certified on the same shape as
  /// `ButtonStyleKey`: one tracked read at `List`/`Table` resolve, with the
  /// resolved presentation carried in the draw payload rather than re-read
  /// from the environment.
  @Test("a list-style change over a collection-free subtree is tolerated")
  func listStyleChangeOverCollectionFreeSubtreeIsTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnyListStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .listStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .plain, dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(style: .insetGrouped, dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  /// The soundness half: a subtree containing a `List` reads the key at the
  /// list's resolve, so the door must deny and the chrome must visibly change.
  @Test("a list-style change with a list in the subtree is denied and restyles")
  func listStyleChangeWithListInSubtreeRestyles() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnyListStyle

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: List { Text("row") })
        }
        .listStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .plain),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(style: .insetGrouped),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    // `.insetGrouped` paints the rounded container `.plain` does not.
    #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("╭"))
    #expect(!toleratedBoundary(in: renderer))
  }

  /// `SpinnerStyleKey` is certified on the same read shape, but unlike the
  /// keys above it has *no* denial population in the corpus — nothing there
  /// changes a spinner style across a boundary. These two cases are that
  /// certification's exercised evidence: the win, and its soundness half.
  @Test("a spinner-style change over a spinner-free subtree is tolerated")
  func spinnerStyleChangeOverSpinnerFreeSubtreeIsTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnySpinnerStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .spinnerStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .moonPhase, dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(style: .globe, dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  @Test("a spinner-style change with a spinner in the subtree is denied and restyles")
  func spinnerStyleChangeWithSpinnerInSubtreeRestyles() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnySpinnerStyle

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Spinner())
        }
        .spinnerStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .moonPhase),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(style: .globe),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("🌍"))
    #expect(!rendered.contains("🌑"))
    #expect(!toleratedBoundary(in: renderer))
  }

  /// `ToolbarStyleKey` is certified on the same shape: only a toolbar host
  /// reads it, at resolve.
  @Test("a toolbar-style change over a toolbar-free subtree is tolerated")
  func toolbarStyleChangeOverToolbarFreeSubtreeIsTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnyToolbarStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .toolbarStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .defaultTop, dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(style: .defaultBottom, dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  /// The soundness half: a subtree hosting a toolbar reads the key at the
  /// host's resolve, so the door must deny and the strip must move edges.
  @Test("a toolbar-style change with a toolbar host in the subtree is denied")
  func toolbarStyleChangeWithHostInSubtreeIsDenied() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnyToolbarStyle

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(
            content: Panel(id: "toolbar-host") {
              Text("inner").toolbarItem(
                .init(
                  title: "Act",
                  icon: nil,
                  position: .top,
                  isEnabled: true,
                  action: {}
                )
              )
            }
            .toolbar()
          )
        }
        .toolbarStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .defaultTop),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(style: .defaultBottom),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(!toleratedBoundary(in: renderer))
  }

  /// `SheetStyleKey` is certified on the same shape: only a sheet
  /// declaration reads it, at resolve.
  @Test("a sheet-style change over a sheet-free subtree is tolerated")
  func sheetStyleChangeOverSheetFreeSubtreeIsTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnySheetStyle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("plain"))
          Text(dynamic)
        }
        .sheetStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .automatic, dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(style: .dropdown, dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("v2"))
    #expect(toleratedBoundary(in: renderer))
  }

  /// The soundness half: a subtree declaring a presented sheet reads the
  /// key at that declaration's resolve, so the door must deny.
  @Test("a sheet-style change with a presented sheet in the subtree is denied")
  func sheetStyleChangeWithPresentedSheetIsDenied() {
    let renderer = makeRenderer()

    struct Root: View {
      let style: AnySheetStyle

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(
            content: Text("inner")
              .sheet("Title", isPresented: .constant(true)) {
                Text("sheet body")
              }
          )
        }
        .sheetStyle(style)
      }
    }

    _ = renderer.render(
      Root(style: .automatic),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(style: .dropdown),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(!toleratedBoundary(in: renderer))
  }

  /// Certified keys must also enter the writer index: an interior
  /// `.scrollIndicators` write decouples the subtree from the boundary's
  /// change, and only the setter's write attribution can see that.
  @Test("an interior writer of a certified framework key denies the serve")
  func interiorCertifiedKeyWriterDeniesTheServe() {
    let renderer = makeRenderer()

    struct Root: View {
      let visibility: ScrollIndicatorVisibility

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(
            content: Text("inner")
              .scrollIndicators(.hidden)
          )
        }
        .scrollIndicators(visibility)
      }
    }

    _ = renderer.render(
      Root(visibility: .visible),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(visibility: .hidden),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(!toleratedBoundary(in: renderer))
  }
}

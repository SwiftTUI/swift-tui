import SwiftTUICore
import Synchronization

/// A focusable multiline text editor that accepts terminal keyboard input.
public struct TextEditor: PrimitiveView, ResolvableView {
  public var text: Binding<String>
  @State private var scrollPosition = ScrollCellOffset.zero
  @State private var textInputValue = TextInputValue()
  // Transient for dormancy: the carrier is re-derived by the first layout pass
  // after a dormant tab returns, so the archive must neither keep the
  // reference nor report it as unsupported state.
  @State(dormantPolicy: .transient) private var measuredContentWidth =
    TextEditorMeasuredContentWidth()
  private let authoringScope: AuthoringContext?

  public init(text: Binding<String>) {
    self.text = text
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    return withDynamicPropertyUpdateScope(self, for: context) {
      [resolvedNode(in: context)]
    }
  }
}

extension TextEditor {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let cursorFollowsFocus = context.environmentValues.cursorFollowsFocus
    let chrome = textInputChrome(
      styleEnvironment: styleEnvironment,
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let synchronizedValue = textInputValue.synchronized(with: text.wrappedValue)

    // The movement layout map must wrap at the same width the inner `Text`
    // actually renders at, so Up/Down move the caret by VISUAL line. That width
    // is only known after layout places the editor, so a companion box captures
    // it during the layout-realization pass (see `TextEditorContentWidthProbe`)
    // and the closure — invoked at key-dispatch time, one full render after the
    // measurement — reads it live. It falls back to `nil` (unwrapped, one
    // visual line per logical line) only before the first measurement.
    let measuredContentWidth = measuredContentWidth
    registerTextInputBinding(
      text,
      value: $textInputValue,
      traits: .multiline,
      layout: { value in
        TextInputPresentation(
          value: value,
          traits: .multiline,
          prompt: nil,
          isFocused: isFocused,
          cursorFollowsFocus: cursorFollowsFocus,
          width: measuredContentWidth.value
        ).layoutMap
      },
      authoringScope: authoringScope,
      in: context
    )

    // DISPLAY presentation and the accessibility caret anchor stay on `width:
    // nil`: the visible wrapping is performed by the inner `Text`, so keeping
    // these unwrapped leaves rendered output (and its fixtures) unchanged.
    let presentation = TextInputPresentation(
      value: synchronizedValue,
      traits: .multiline,
      prompt: nil,
      isFocused: isFocused,
      cursorFollowsFocus: cursorFollowsFocus,
      width: nil
    )

    let ownerIdentity = context.identity
    let position = $scrollPosition
    let configuration = TextEditorStyleConfiguration(
      editorContent: .init(authoringContext: authoringScope) {
        ScrollView(.vertical, position: position) {
          VStack(alignment: .leading, spacing: 0) {
            TextInputContent(
              displayText: presentation.displayText,
              displayRuns: presentation.displayRuns,
              ownerIdentity: ownerIdentity,
              caretAnchor: presentation.caretAnchor
            )
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(chrome.foregroundStyle)
            .opacity(chrome.opacity)
          }
        }
        .focusable(false)
        // Wrapping, scrolling, and the caret map remain one protected slot.
        // Measuring this viewport directly also handles arbitrary style padding.
        .ambientTextAttributesReset()
        .background {
          TextEditorContentWidthProbe(measuredContentWidth: measuredContentWidth)
        }
      },
      isEnabled: isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      styleEnvironment: styleEnvironment
    )
    let child = context.environmentValues.textEditorStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("TextEditorBody"))
    )

    var metadata = focusableControlMetadata(
      focusInteractions: .edit,
      accessibilityRole: .textEditor
    )
    // The editor is ONE focus stop. Its body embeds a ScrollView, whose content
    // (and transient scroll indicator) would otherwise emit their own top-level
    // focus regions — putting the editor's internals on the Tab ring. Seal the
    // descendants: the editor's own region stays, wheel scrolling still routes
    // through the scroll role, and caret-driven scrolling uses the editor's own
    // scroll-position binding, none of which need descendant focus regions.
    metadata.sealsFocusDescendants = true
    return ResolvedNode(
      identity: context.identity,
      kind: .view("TextEditor"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: metadata
    )
  }
}

/// A stable, reference-typed carrier for the editor's last-measured content
/// width. It lives in `@State` so the same instance survives every re-render;
/// the layout-realization pass writes it and the key-dispatch closure reads it,
/// both on the main actor. Mutating `value` is deliberately not a `@State`
/// write — it must not itself schedule a frame.
final class TextEditorMeasuredContentWidth: Sendable {
  private let storage = Mutex<Int?>(nil)

  init() {}

  var value: Int? {
    get { storage.withLock { $0 } }
    set { storage.withLock { $0 = newValue } }
  }
}

/// A zero-output view that measures the width it is placed at and records the
/// editor's content width into
/// `measuredContentWidth`. Attached as a `.background`, it is sized to the
/// protected viewport without influencing its layout, and it draws
/// nothing. This is the channel that carries the realized wrap width back to
/// the movement layout map.
private struct TextEditorContentWidthProbe: PrimitiveView, ResolvableView {
  let measuredContentWidth: TextEditorMeasuredContentWidth

  func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let realizer = TextEditorContentWidthRealizer(measuredContentWidth: measuredContentWidth)
    let boundary = LayoutRealizedContentBoundary(
      identity: context.identity,
      sizingPolicy: .fillsProposal(unspecifiedIdeal: CellSize(width: 0, height: 0)),
      safeAreaInsets: context.environmentValues.safeAreaInsets,
      cellPixelMetrics: context.environmentValues.cellPixelMetrics,
      pointerInputCapabilities: context.environmentValues.pointerInputCapabilities,
      debugName: "TextEditorContentWidthProbe",
      handle: LayoutDependentContentHandle(realizer)
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("TextEditorContentWidthProbe"),
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutRealizedContent: boundary
      )
    ]
  }
}

@MainActor
private final class TextEditorContentWidthRealizer: LayoutDependentContentRealizer {
  let debugName = "TextEditorContentWidthProbe"
  private let measuredContentWidth: TextEditorMeasuredContentWidth

  init(
    measuredContentWidth: TextEditorMeasuredContentWidth
  ) {
    self.measuredContentWidth = measuredContentWidth
  }

  func realize(
    in context: LayoutRealizationContext
  ) -> [ResolvedNode] {
    measuredContentWidth.value = max(0, context.bounds.size.width)
    return []
  }
}

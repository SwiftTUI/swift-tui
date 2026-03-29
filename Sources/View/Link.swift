import Core

/// Displays focusable hyperlink text.
public struct Link: View, ResolvableView {
  public var label: Text
  public var destination: String

  public init(
    _ title: String,
    destination: String
  ) {
    label = Text(title)
    self.destination = destination
  }

  public init(
    _ label: Text,
    destination: String
  ) {
    self.label = label
    self.destination = destination
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Link {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    parallelRegisterOpenLinkAction(
      destination: destination,
      identity: context.identity,
      in: context
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Link"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      drawMetadata: .init(),
      semanticMetadata: parallelFocusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .link
      ),
      drawPayload: .richText(
        parallelResolvedRichTextPayload(
          for: self,
          in: context
        )
      )
    )
  }
}

package func parallelResolvedRichTextPayload(
  for text: Text,
  in context: ResolveContext
) -> RichTextPayload {
  var builder = ResolvedRichTextBuilder(
    context: context,
    rootIdentity: context.identity
  )
  let payload = RichTextPayload(
    runs: builder.runs(
      for: text,
      inheritedStyle: .init()
    )
  )
  builder.registerInlineLinkActions()
  return payload
}

package func parallelResolvedRichTextPayload(
  for link: Link,
  in context: ResolveContext
) -> RichTextPayload {
  var builder = ResolvedRichTextBuilder(
    context: context,
    rootIdentity: context.identity
  )
  let payload = RichTextPayload(
    runs: builder.runs(
      for: link,
      inheritedStyle: .init(),
      inlineIdentifier: nil,
      linkIdentity: context.identity
    )
  )
  builder.registerInlineLinkActions()
  return payload
}

package func parallelInlineTextStyle(
  from metadata: DrawMetadata
) -> TextStyle {
  TextStyle(
    foregroundStyle: metadata.foregroundStyle,
    backgroundStyle: metadata.backgroundStyle,
    emphasis: metadata.emphasis,
    underlineStyle: metadata.underlineStyle,
    strikethroughStyle: metadata.strikethroughStyle,
    opacity: metadata.opacity
  )
}

private struct ResolvedRichTextBuilder {
  let context: ResolveContext
  let rootIdentity: Identity
  var nextInlineLinkIndex = 0
  var inlineLinkActions: [(identifier: String, destination: String)] = []

  mutating func runs(
    for text: Text,
    inheritedStyle: TextStyle
  ) -> [RichTextRun] {
    let effectiveStyle = inheritedStyle.merging(
      parallelInlineTextStyle(from: text.drawMetadata)
    )

    switch text.storage {
    case .plain(let content):
      guard !content.isEmpty else {
        return []
      }
      return [
        .init(
          text: content,
          style: effectiveStyle
        )
      ]
    case .rich(let content):
      return runs(
        for: content,
        inheritedStyle: effectiveStyle
      )
    }
  }

  mutating func runs(
    for content: Text.RichContent,
    inheritedStyle: TextStyle
  ) -> [RichTextRun] {
    var resolvedRuns: [RichTextRun] = []

    for fragment in content.fragments {
      switch fragment {
      case .literal(let literal):
        guard !literal.isEmpty else {
          continue
        }
        resolvedRuns.append(
          .init(
            text: literal,
            style: inheritedStyle
          )
        )
      case .text(let text):
        resolvedRuns.append(
          contentsOf: runs(
            for: text,
            inheritedStyle: inheritedStyle
          )
        )
      case .link(let link):
        let inlineIdentifier = "InlineLink[\(nextInlineLinkIndex)]"
        nextInlineLinkIndex += 1
        let linkIdentity = parallelInlineLinkIdentity(
          parent: rootIdentity,
          identifier: inlineIdentifier
        )
        resolvedRuns.append(
          contentsOf: runs(
            for: link,
            inheritedStyle: inheritedStyle,
            inlineIdentifier: inlineIdentifier,
            linkIdentity: linkIdentity
          )
        )
      }
    }

    return resolvedRuns
  }

  mutating func runs(
    for link: Link,
    inheritedStyle: TextStyle,
    inlineIdentifier: String?,
    linkIdentity: Identity
  ) -> [RichTextRun] {
    let linkStyle = inheritedStyle.merging(
      parallelLinkTextStyle(
        for: linkIdentity,
        in: context
      )
    )

    let labeledRuns = runs(
      for: link.label,
      inheritedStyle: linkStyle
    )

    if let inlineIdentifier {
      inlineLinkActions.append(
        (identifier: inlineIdentifier, destination: link.destination)
      )
    }

    return labeledRuns.map { run in
      var run = run
      run.destination = link.destination
      run.linkIdentifier = inlineIdentifier
      return run
    }
  }

  mutating func registerInlineLinkActions() {
    for action in inlineLinkActions {
      parallelRegisterOpenLinkAction(
        destination: action.destination,
        identity: parallelInlineLinkIdentity(
          parent: rootIdentity,
          identifier: action.identifier
        ),
        in: context
      )
    }
  }
}

private func parallelLinkTextStyle(
  for identity: Identity,
  in context: ResolveContext
) -> TextStyle {
  let isFocused = context.environmentValues.parallelFocusedIdentity == identity
  let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
  let isPressed = context.environmentValues.parallelPressedIdentity == identity
  let chrome = context.environmentValues.terminalAppearance.buttonChrome(
    buttonStyle: .link,
    isEnabled: context.environmentValues.isEnabled,
    isFocused: isFocused && showsFocusEffect,
    isPressed: isPressed
  )

  var style = TextStyle(
    foregroundStyle: chrome.foregroundStyle,
    emphasis: [],
    underlineStyle: .init(pattern: .solid),
    opacity: chrome.opacity
  )

  if (isFocused && showsFocusEffect) || isPressed {
    style.backgroundStyle = chrome.backgroundStyle
  }

  return style
}

private func parallelRegisterOpenLinkAction(
  destination: String,
  identity: Identity,
  in context: ResolveContext
) {
  guard context.environmentValues.isEnabled,
    let localActionRegistry = context.localActionRegistry
  else {
    return
  }

  let openLinkAction = context.environmentValues.openLinkAction
  let dynamicPropertyScope = currentDynamicPropertyScope()
  localActionRegistry.register(identity: identity) {
    withDynamicPropertyScope(dynamicPropertyScope) {
      openLinkAction(destination)
    }
  }
}

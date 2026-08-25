import SwiftTUICore

@MainActor
package func registerTextInputBinding(
  _ binding: Binding<String>,
  value: Binding<TextInputValue>,
  traits: TextInputTraits,
  layout: @escaping @MainActor (TextInputValue) -> TextInputLayoutMap? = { _ in nil },
  authoringScope: AuthoringContext?,
  in context: ResolveContext
) {
  guard context.environmentValues.isEnabled else {
    return
  }

  let intake = HandlerDescriptorIntake(
    context: context,
    fallbackAuthoringScope: authoringScope
  )

  let submitAction = context.environmentValues.submitAction
  let applyEditingCommand: @MainActor (KeyPress) -> Bool = { keyPress in
    guard let command = textInputCommand(for: keyPress, traits: traits) else {
      return false
    }

    return applyTextInputCommand(
      command,
      binding: binding,
      value: value,
      traits: traits,
      layout: layout,
      clipboardWriteAction: context.environmentValues.clipboardWriteAction,
      clipboardReadAction: context.environmentValues.clipboardReadAction
    )
  }
  let handle: @MainActor (KeyPress) -> Bool = { keyPress in
    // Submit precedes editing-command resolution: it mutates no text, so it
    // must not reach the reducer's no-change bail, and consuming here keeps
    // Return from bubbling on to ancestor activation. Without an enclosing
    // `onSubmit` action Return keeps its default routing.
    if keyPress.key == .return,
      keyPress.modifiers.isEmpty,
      traits.submitBehavior == .submit,
      let submitAction
    {
      submitAction()
      return true
    }
    return applyEditingCommand(keyPress)
  }

  intake.registerKeyPressHandler(identity: context.identity, handler: handle)
  intake.registerPasteHandler(
    identity: context.identity,
    handler: { content in
      applyTextInputCommand(
        .insertText(content),
        binding: binding,
        value: value,
        traits: traits,
        layout: layout,
        clipboardWriteAction: context.environmentValues.clipboardWriteAction,
        clipboardReadAction: context.environmentValues.clipboardReadAction
      )
    })
}

@MainActor
private func applyTextInputCommand(
  _ command: TextInputCommand,
  binding: Binding<String>,
  value: Binding<TextInputValue>,
  traits: TextInputTraits,
  layout: @escaping @MainActor (TextInputValue) -> TextInputLayoutMap?,
  clipboardWriteAction: ClipboardWriteAction,
  clipboardReadAction: ClipboardReadAction
) -> Bool {
  let currentValue = value.wrappedValue.synchronized(with: binding.wrappedValue)
  let resolvedCommand: TextInputCommand
  if command == .pasteClipboard {
    guard let clipboardText = clipboardReadAction() else {
      return true
    }
    resolvedCommand = .insertText(clipboardText)
  } else {
    resolvedCommand = command
  }
  let mutation = TextInputReducer().reduce(
    currentValue,
    command: resolvedCommand,
    traits: traits,
    layout: layout(currentValue)
  )
  // Cut and paste consume their chord even when they change nothing (an
  // empty clipboard, a secure field), so the key never bubbles on as
  // unhandled. Copy is handled only when there was a selection to copy: a
  // `Ctrl+C` with a collapsed selection (or in a secure field) is not an
  // edit, and declining it lets the scene's exit binding — `Ctrl+C` by
  // default — take the key.
  let isClipboardCommand = command == .cutSelection || command == .pasteClipboard
  let copiedSelection = command == .copySelection && mutation.clipboardText != nil
  let didWriteClipboard: Bool
  if let clipboardText = mutation.clipboardText {
    guard clipboardWriteAction(clipboardText) else {
      return isClipboardCommand || copiedSelection
    }
    didWriteClipboard = true
  } else {
    didWriteClipboard = false
  }

  guard
    mutation.value != currentValue || mutation.shouldWriteBinding || didWriteClipboard
      || isClipboardCommand || copiedSelection
  else {
    return false
  }

  value.wrappedValue = mutation.value
  if mutation.shouldWriteBinding {
    binding.wrappedValue = mutation.value.text
  }
  return mutation.shouldRequestFrame || mutation.shouldWriteBinding || didWriteClipboard
    || isClipboardCommand || copiedSelection
}

package func textInputCommand(
  for keyPress: KeyPress,
  traits: TextInputTraits
) -> TextInputCommand? {
  var commandModifiers = keyPress.modifiers
  let isSelecting = commandModifiers.contains(.shift)
  commandModifiers.remove(.shift)

  if let modifiedCommand = modifiedTextInputCommand(
    for: keyPress.key,
    modifiers: commandModifiers,
    selecting: isSelecting
  ) {
    return modifiedCommand
  }

  guard commandModifiers.isEmpty else {
    return nil
  }

  switch keyPress.key {
  case .character(let character):
    guard !isSelecting else {
      return nil
    }
    return .insertText(String(character))
  case .space:
    guard !isSelecting else {
      return nil
    }
    return .insertText(" ")
  case .return where traits.isMultiline && traits.submitBehavior == .newline:
    guard !isSelecting else {
      return nil
    }
    return .insertText("\n")
  case .backspace:
    guard !isSelecting else {
      return nil
    }
    return .deleteBackward(granularity: .character)
  case .delete:
    guard !isSelecting else {
      return nil
    }
    return .deleteForward(granularity: .character)
  case .arrowLeft:
    return .move(.left, selecting: isSelecting)
  case .arrowRight:
    return .move(.right, selecting: isSelecting)
  case .arrowUp:
    return .move(.up, selecting: isSelecting)
  case .arrowDown:
    return .move(.down, selecting: isSelecting)
  case .home:
    return .move(.lineStart, selecting: isSelecting)
  case .end:
    return .move(.lineEnd, selecting: isSelecting)
  default:
    return nil
  }
}

private func modifiedTextInputCommand(
  for key: KeyEvent,
  modifiers: EventModifiers,
  selecting isSelecting: Bool
) -> TextInputCommand? {
  switch modifiers {
  case .alt:
    return altTextInputCommand(for: key, selecting: isSelecting)
  case .ctrl:
    return ctrlTextInputCommand(for: key, selecting: isSelecting)
  default:
    return nil
  }
}

private func altTextInputCommand(
  for key: KeyEvent,
  selecting isSelecting: Bool
) -> TextInputCommand? {
  switch key {
  case .arrowLeft:
    return .move(.wordBackward, selecting: isSelecting)
  case .arrowRight:
    return .move(.wordForward, selecting: isSelecting)
  case .backspace:
    guard !isSelecting else {
      return nil
    }
    return .deleteBackward(granularity: .word)
  default:
    return nil
  }
}

private func ctrlTextInputCommand(
  for key: KeyEvent,
  selecting isSelecting: Bool
) -> TextInputCommand? {
  switch key {
  case .character("a"), .character("A"):
    return .selectAll
  case .character("c"), .character("C"):
    guard !isSelecting else {
      return nil
    }
    return .copySelection
  case .character("x"), .character("X"):
    guard !isSelecting else {
      return nil
    }
    return .cutSelection
  case .character("v"), .character("V"):
    guard !isSelecting else {
      return nil
    }
    return .pasteClipboard
  case .arrowLeft:
    return .move(.wordBackward, selecting: isSelecting)
  case .arrowRight:
    return .move(.wordForward, selecting: isSelecting)
  case .backspace:
    guard !isSelecting else {
      return nil
    }
    return .deleteBackward(granularity: .word)
  default:
    return nil
  }
}

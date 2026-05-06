package import SwiftTUICore

@MainActor
package func registerTextInputBinding(
  _ binding: Binding<String>,
  value: Binding<TextInputValue>,
  traits: TextInputTraits,
  authoringContext: ImperativeAuthoringContextSnapshot?,
  in context: ResolveContext
) {
  guard context.environmentValues.isEnabled else {
    return
  }

  guard let keyHandlerRegistry = context.localKeyHandlerRegistry else {
    return
  }

  let handle: @MainActor (KeyPress) -> Bool = { keyPress in
    guard let command = textInputCommand(for: keyPress, traits: traits) else {
      return false
    }

    return withImperativeAuthoringContext(authoringContext) {
      let currentValue = value.wrappedValue.synchronized(with: binding.wrappedValue)
      let mutation = TextInputReducer().reduce(
        currentValue,
        command: command,
        traits: traits,
        layout: nil
      )
      guard mutation.value != currentValue || mutation.shouldWriteBinding else {
        return false
      }

      value.wrappedValue = mutation.value
      if mutation.shouldWriteBinding {
        binding.wrappedValue = mutation.value.text
      }
      return mutation.shouldRequestFrame || mutation.shouldWriteBinding
    }
  }

  keyHandlerRegistry.register(identity: context.identity, keyPressHandler: handle)
  keyHandlerRegistry.register(identity: context.identity) { event in
    handle(KeyPress(event))
  }
}

package func textInputCommand(
  for keyPress: KeyPress,
  traits: TextInputTraits
) -> TextInputCommand? {
  let isSelecting: Bool
  switch keyPress.modifiers {
  case []:
    isSelecting = false
  case .shift:
    isSelecting = true
  default:
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
  case .arrowLeft:
    return .move(.left, selecting: isSelecting)
  case .arrowRight:
    return .move(.right, selecting: isSelecting)
  case .home:
    return .move(.lineStart, selecting: isSelecting)
  case .end:
    return .move(.lineEnd, selecting: isSelecting)
  default:
    return nil
  }
}

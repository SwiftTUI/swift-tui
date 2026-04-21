#if canImport(UIKit) && !targetEnvironment(macCatalyst)
  import Ghostty
  import ObjectiveC.runtime
  import UIKit

  @MainActor
  enum GhosttyKeyboardPresentationController {
    fileprivate static var allowsExpandedKeyboardPresentationKey: UInt8 = 0
    fileprivate static var suppressingInputViewKey: UInt8 = 0

    private static let installSwizzle: Void = {
      let targetClass: AnyClass = UITerminalView.self
      let originalSelector = #selector(getter: UIResponder.inputView)
      let replacementSelector = #selector(UITerminalView.stui_keyboardManagedInputView)

      guard let replacementMethod = class_getInstanceMethod(targetClass, replacementSelector) else {
        assertionFailure("Missing Ghostty keyboard-management replacement method.")
        return
      }

      if class_addMethod(
        targetClass,
        originalSelector,
        method_getImplementation(replacementMethod),
        method_getTypeEncoding(replacementMethod)
      ) {
        guard let originalMethod = class_getInstanceMethod(UIResponder.self, originalSelector)
        else {
          assertionFailure("Missing UIResponder.inputView getter for Ghostty keyboard management.")
          return
        }
        class_replaceMethod(
          targetClass,
          replacementSelector,
          method_getImplementation(originalMethod),
          method_getTypeEncoding(originalMethod)
        )
      } else if let originalMethod = class_getInstanceMethod(targetClass, originalSelector) {
        method_exchangeImplementations(originalMethod, replacementMethod)
      } else {
        assertionFailure("Missing Ghostty inputView getter for keyboard management.")
      }
    }()

    static func setAllowsExpandedKeyboardPresentation(
      _ allowsExpandedKeyboardPresentation: Bool,
      for view: TerminalView
    ) {
      _ = installSwizzle
      view.stui_allowsExpandedKeyboardPresentation = allowsExpandedKeyboardPresentation
    }

    static func presentExpandedKeyboard(
      for view: TerminalView
    ) {
      setAllowsExpandedKeyboardPresentation(true, for: view)

      if view.isFirstResponder {
        view.reloadInputViews()
      } else {
        _ = view.becomeFirstResponder()
      }
    }

    static func suppressExpandedKeyboard(
      for view: TerminalView
    ) {
      setAllowsExpandedKeyboardPresentation(false, for: view)
      if view.isFirstResponder {
        view.reloadInputViews()
      }
    }
  }

  extension UITerminalView {
    fileprivate var stui_allowsExpandedKeyboardPresentation: Bool {
      get {
        (objc_getAssociatedObject(
          self,
          &GhosttyKeyboardPresentationController.allowsExpandedKeyboardPresentationKey
        ) as? NSNumber)?.boolValue ?? true
      }
      set {
        objc_setAssociatedObject(
          self,
          &GhosttyKeyboardPresentationController.allowsExpandedKeyboardPresentationKey,
          NSNumber(value: newValue),
          .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
      }
    }

    fileprivate var stui_suppressingInputView: UIView {
      if let view = objc_getAssociatedObject(
        self,
        &GhosttyKeyboardPresentationController.suppressingInputViewKey
      ) as? UIView {
        return view
      }

      let view = UIView(frame: .zero)
      view.isUserInteractionEnabled = false
      objc_setAssociatedObject(
        self,
        &GhosttyKeyboardPresentationController.suppressingInputViewKey,
        view,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
      return view
    }

    // Swap the inherited UIResponder.inputView getter on UITerminalView so the
    // host can suppress the software keyboard without blocking first responder.
    @objc fileprivate func stui_keyboardManagedInputView() -> UIView? {
      guard stui_allowsExpandedKeyboardPresentation == false else {
        return stui_keyboardManagedInputView()
      }
      return stui_suppressingInputView
    }
  }
#endif

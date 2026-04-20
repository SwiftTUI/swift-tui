#if canImport(UIKit) && !targetEnvironment(macCatalyst)
  import ObjectiveC.runtime
  import SwiftTerm
  import UIKit

  @MainActor
  enum SwiftTermKeyboardPresentationController {
    fileprivate static var allowsExpandedKeyboardPresentationKey: UInt8 = 0
    fileprivate static var suppressingInputViewKey: UInt8 = 0

    private static let installSwizzle: Void = {
      let targetClass: AnyClass = TerminalView.self
      let originalSelector = #selector(getter: UIResponder.inputView)
      let replacementSelector = #selector(TerminalView.stui_keyboardManagedInputView)

      guard let replacementMethod = class_getInstanceMethod(targetClass, replacementSelector) else {
        assertionFailure("Missing SwiftTerm keyboard-management replacement method.")
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
          assertionFailure(
            "Missing UIResponder.inputView getter for SwiftTerm keyboard management.")
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
        assertionFailure("Missing SwiftTerm inputView getter for keyboard management.")
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

  extension TerminalView {
    fileprivate var stui_allowsExpandedKeyboardPresentation: Bool {
      get {
        (objc_getAssociatedObject(
          self,
          &SwiftTermKeyboardPresentationController.allowsExpandedKeyboardPresentationKey
        ) as? NSNumber)?.boolValue ?? true
      }
      set {
        objc_setAssociatedObject(
          self,
          &SwiftTermKeyboardPresentationController.allowsExpandedKeyboardPresentationKey,
          NSNumber(value: newValue),
          .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
      }
    }

    fileprivate var stui_suppressingInputView: UIView {
      if let view = objc_getAssociatedObject(
        self,
        &SwiftTermKeyboardPresentationController.suppressingInputViewKey
      ) as? UIView {
        return view
      }

      let view = UIView(frame: .zero)
      view.isUserInteractionEnabled = false
      objc_setAssociatedObject(
        self,
        &SwiftTermKeyboardPresentationController.suppressingInputViewKey,
        view,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
      return view
    }

    // Swap the inherited UIResponder.inputView getter on TerminalView so the
    // host can suppress the software keyboard without blocking first responder.
    @objc fileprivate func stui_keyboardManagedInputView() -> UIView? {
      guard stui_allowsExpandedKeyboardPresentation == false else {
        return stui_keyboardManagedInputView()
      }
      return stui_suppressingInputView
    }
  }
#endif

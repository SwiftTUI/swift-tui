public import SwiftTUICore

/// The direction requested by an assistive adjustment operation.
public enum AccessibilityAdjustmentDirection: Sendable {
  case increment, decrement
}

/// Semantic traits with browser and terminal equivalents.
public struct AccessibilityTraits: OptionSet, Sendable {
  public let rawValue: UInt16
  public init(rawValue: UInt16) { self.rawValue = rawValue }
  public static let isButton = Self(rawValue: 1 << 0)
  public static let isLink = Self(rawValue: 1 << 1)
  public static let isImage = Self(rawValue: 1 << 2)
  public static let isHeader = Self(rawValue: 1 << 3)
  public static let isStaticText = Self(rawValue: 1 << 4)
  public static let isSelected = Self(rawValue: 1 << 5)
}

extension View {
  /// Describes the current value separately from the accessible name.
  public func accessibilityValue(_ value: String) -> some View {
    accessibilityProperties(.init(valueDescription: value))
  }

  /// Supplies an authoritative numeric value and range for a custom control.
  /// Pair this with an adjustable action to change application state.
  public func accessibilityValue(
    _ value: Double, in bounds: ClosedRange<Double>, step: Double = 1,
    description: String? = nil
  ) -> some View {
    modifier(
      AccessibilityNumericValueModifier(
        value: value, bounds: bounds, step: step, description: description))
  }

  /// Replaces the default assistive activation without synthesizing keyboard input.
  public func accessibilityAction(
    _ action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(
      AccessibilityAuthoredActionModifier(
        kinds: [.activate], name: nil, scope: currentImperativeAuthoringContextSnapshot(),
        action: { _ in action() }))
  }

  /// Adds a named operation. Browsers expose named operations as associated buttons.
  /// Names identify operations within a control; an outer duplicate replaces the inner one.
  public func accessibilityAction(
    named name: String, _ action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(
      AccessibilityAuthoredActionModifier(
        kinds: [.custom], name: name, scope: currentImperativeAuthoringContextSnapshot(),
        action: { _ in action() }))
  }

  /// Adds increment and decrement operations. The application owns bounds and mutation.
  public func accessibilityAdjustableAction(
    _ action: @escaping @MainActor @Sendable (AccessibilityAdjustmentDirection) -> Void
  ) -> some View {
    modifier(
      AccessibilityAuthoredActionModifier(
        kinds: [.increment, .decrement], name: nil,
        scope: currentImperativeAuthoringContextSnapshot(),
        action: { action($0 == .increment ? .increment : .decrement) }))
  }

  public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View {
    modifier(AccessibilityTraitsModifier(traits: traits, removing: false))
  }

  public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View {
    modifier(AccessibilityTraitsModifier(traits: traits, removing: true))
  }

  /// Presentation operations stay outside ordinary keyboard traversal.
  package func accessibilityPresentationAction(
    named name: String, _ action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(
      AccessibilityAuthoredActionModifier(
        kinds: [.custom], name: name, scope: currentImperativeAuthoringContextSnapshot(),
        action: { _ in action() }, includesKeyboardFocus: false))
  }
}

private struct AccessibilityAuthoredActionModifier: IterativePrimitiveViewModifier {
  let kinds: [AccessibilityActionKind]
  let name: String?
  let scope: ImperativeAuthoringContextSnapshot?
  let action: @MainActor @Sendable (AccessibilityAction) -> Void
  var includesKeyboardFocus = true

  func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>, in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    content.resolveWork(in: context).map { completed in
      var node = completed
      if let name, name.allSatisfy(\.isWhitespace) { return [node] }
      let previous = node.semanticMetadata.accessibilityControl
      var actions = previous?.actions ?? []
      let focusActions: [AccessibilityActionKind] =
        includesKeyboardFocus ? [.focus] : [.accessibilityFocus, .accessibilityBlur]
      for kind in focusActions + kinds where !actions.contains(kind) { actions.append(kind) }
      var names = previous?.customActions ?? []
      if let name, !names.contains(name) { names.append(name) }
      node.semanticMetadata.accessibilityControl = .init(
        actions: actions, value: previous?.value, minimum: previous?.minimum,
        maximum: previous?.maximum, step: previous?.step, selection: previous?.selection,
        customActions: names,
        opensLink: kinds.contains(.activate) ? false : previous?.opensLink ?? false)
      if includesKeyboardFocus { node.semanticMetadata.isFocusable = true }
      if node.semanticMetadata.accessibilityRole == nil {
        node.semanticMetadata.accessibilityRole = kinds.contains(.increment) ? .stepper : .button
      }
      let intake = HandlerDescriptorIntake(context: context, preferringSnapshot: scope)
      intake.composeAccessibilityAction(
        identity: node.identity,
        preservingExisting: previous?.actions.contains(where: { $0 != .focus }) == true
      ) { request in
        let matches: Bool
        if case .custom(let requestedName) = request {
          matches = name == requestedName
        } else {
          matches = kinds.contains(request.kind)
        }
        if matches {
          action(request)
          return .changed
        }
        return nil
      }
      return [node]
    }
  }
}

private struct AccessibilityNumericValueModifier: IterativePrimitiveViewModifier {
  let value: Double
  let bounds: ClosedRange<Double>
  let step: Double
  let description: String?

  func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>, in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    content.resolveWork(in: context).map { completed in
      var node = completed
      guard value.isFinite, bounds.lowerBound.isFinite, bounds.upperBound.isFinite,
        step.isFinite, step > 0
      else { return [node] }
      let previous = node.semanticMetadata.accessibilityControl
      node.semanticMetadata.accessibilityControl = .init(
        actions: previous?.actions ?? [], value: .number(value),
        minimum: bounds.lowerBound, maximum: bounds.upperBound, step: step,
        selection: previous?.selection, customActions: previous?.customActions ?? [],
        opensLink: previous?.opensLink ?? false)
      if let description {
        let properties = AccessibilityProperties(valueDescription: description)
        node.semanticMetadata.accessibilityProperties =
          node.semanticMetadata.accessibilityProperties?.merging(properties) ?? properties
      }
      return [node]
    }
  }
}

private struct AccessibilityTraitsModifier: IterativePrimitiveViewModifier {
  let traits: AccessibilityTraits
  let removing: Bool

  func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>, in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    content.resolveWork(in: context).map { completed in
      var node = completed
      let roles: [(AccessibilityTraits, AccessibilityRole)] = [
        (.isButton, .button), (.isLink, .link), (.isImage, .image),
        (.isHeader, .heading(level: 1)), (.isStaticText, .group),
      ]
      for (trait, role) in roles where traits.contains(trait) {
        if !removing {
          node.semanticMetadata.accessibilityRole = role
        } else if trait == .isHeader,
          case .heading = node.semanticMetadata.accessibilityRole
        {
          node.semanticMetadata.accessibilityRole = nil
        } else if node.semanticMetadata.accessibilityRole == role {
          node.semanticMetadata.accessibilityRole = nil
        }
      }
      if traits.contains(.isSelected) {
        let selected = AccessibilityProperties(selected: !removing)
        node.semanticMetadata.accessibilityProperties =
          node.semanticMetadata.accessibilityProperties?.merging(selected) ?? selected
      }
      return [node]
    }
  }
}

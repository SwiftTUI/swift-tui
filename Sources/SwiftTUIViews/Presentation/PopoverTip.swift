// Popover tip vocabulary.
//
// A `PopoverTip` is a small, source-attached guidance item shown via
// `View.popoverTip(...)`. This file holds the tip protocol and its action
// type; the popover presentation modifiers and placement live in
// `PopoverPresentation.swift`.

/// A lightweight action displayed by ``PopoverTip`` content.
public struct PopoverTipAction: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String

  public init(
    id: String,
    title: String
  ) {
    self.id = id
    self.title = title
  }
}

/// A small, source-attached guidance item for ``View/popoverTip(_:isPresented:attachmentAnchor:arrowEdge:action:)``.
public protocol PopoverTip: Identifiable, Sendable where ID: Sendable {
  @MainActor
  var title: Text { get }
  @MainActor
  var message: Text? { get }
  @MainActor
  var icon: Text? { get }
  var actions: [PopoverTipAction] { get }
  var isEligible: Bool { get }
}

extension PopoverTip {
  @MainActor
  public var message: Text? { nil }
  @MainActor
  public var icon: Text? { nil }
  public var actions: [PopoverTipAction] { [] }
  public var isEligible: Bool { true }
}

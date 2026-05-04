/// Host-facing snapshot of the settled focus presentation for a committed frame.
public struct FocusPresentation: Equatable, Sendable {
  public enum Semantics: Equatable, Sendable {
    case none
    case automatic
    case activate
    case edit
  }

  public var focusedIdentity: Identity?
  public var semantics: Semantics

  public init(
    focusedIdentity: Identity?,
    semantics: Semantics
  ) {
    self.focusedIdentity = focusedIdentity
    self.semantics = semantics
  }

  public static let none = Self(
    focusedIdentity: nil,
    semantics: .none
  )

  public var hasFocusedRegion: Bool {
    focusedIdentity != nil
  }

  public var prefersTextInput: Bool {
    semantics == .edit
  }
}

extension SemanticSnapshot {
  /// Returns the host-facing focus presentation represented by the committed
  /// semantic snapshot for the currently focused identity.
  public func focusPresentation(
    for focusedIdentity: Identity?
  ) -> FocusPresentation {
    guard let focusedIdentity else {
      return .none
    }
    guard let region = focusRegions.first(where: { $0.identity == focusedIdentity }) else {
      return .none
    }

    return FocusPresentation(
      focusedIdentity: focusedIdentity,
      semantics: .init(region.focusInteractions)
    )
  }
}

extension FocusPresentation.Semantics {
  fileprivate init(_ interactions: FocusInteractions) {
    switch interactions {
    case .automatic:
      self = .automatic
    case .activate:
      self = .activate
    case .edit:
      self = .edit
    }
  }
}

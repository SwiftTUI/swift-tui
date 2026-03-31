public enum ScrollRole: Hashable, Sendable, CustomStringConvertible {
  case scrollView
  case list
  case table

  public var description: String {
    switch self {
    case .scrollView:
      "scrollView"
    case .list:
      "list"
    case .table:
      "table"
    }
  }
}

public enum SectionRole: Hashable, Sendable, CustomStringConvertible {
  case section
  case header
  case content
  case footer

  public var description: String {
    switch self {
    case .section:
      "section"
    case .header:
      "header"
    case .content:
      "content"
    case .footer:
      "footer"
    }
  }
}

public enum PresentationRole: Hashable, Sendable, CustomStringConvertible {
  case alert
  case button
  case confirmationDialog
  case disclosureGroup
  case link
  case list
  case menu
  case picker
  case scrollView
  case scrollViewWithIndicators
  case section
  case sheet
  case slider
  case stepper
  case table
  case tableRow
  case tabView
  case textEditor
  case textField
  case toggle

  public var description: String {
    switch self {
    case .alert:
      "alert"
    case .button:
      "button"
    case .confirmationDialog:
      "confirmationDialog"
    case .disclosureGroup:
      "disclosureGroup"
    case .link:
      "link"
    case .list:
      "list"
    case .menu:
      "menu"
    case .picker:
      "picker"
    case .scrollView:
      "scrollView"
    case .scrollViewWithIndicators:
      "scrollViewWithIndicators"
    case .section:
      "section"
    case .sheet:
      "sheet"
    case .slider:
      "slider"
    case .stepper:
      "stepper"
    case .table:
      "table"
    case .tableRow:
      "tableRow"
    case .tabView:
      "tabView"
    case .textEditor:
      "textEditor"
    case .textField:
      "textField"
    case .toggle:
      "toggle"
    }
  }
}

public enum RouteKind: Hashable, Sendable, CustomStringConvertible {
  case primary

  public var description: String {
    switch self {
    case .primary:
      "primary"
    }
  }
}

public struct RouteID: Hashable, Sendable, CustomStringConvertible {
  public var identity: Identity
  public var kind: RouteKind

  public init(
    identity: Identity,
    kind: RouteKind = .primary
  ) {
    self.identity = identity
    self.kind = kind
  }

  public var description: String {
    "\(identity.path)#\(kind)"
  }
}

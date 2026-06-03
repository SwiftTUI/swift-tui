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

public enum AccessibilityRole: Hashable, Sendable, CustomStringConvertible {
  case alert
  case button
  case cell
  case checkbox
  case columnHeader
  case confirmationDialog
  case custom(String)
  case disclosureGroup
  case group
  case heading(level: Int)
  case image
  case link
  case list
  case menu
  case menuItem
  case picker
  case popover
  case progressBar
  case region
  case rowHeader
  case scrollView
  case scrollViewWithIndicators
  case section
  case secureField
  case separator
  case sheet
  case slider
  case status
  case stepper
  case tab
  case tabPanel
  case table
  case tableRow
  case tabView
  case textEditor
  case textField
  case timer
  case toggle

  public var description: String {
    switch self {
    case .alert:
      "alert"
    case .button:
      "button"
    case .cell:
      "cell"
    case .checkbox:
      "checkbox"
    case .columnHeader:
      "columnHeader"
    case .confirmationDialog:
      "confirmationDialog"
    case .custom(let value):
      "custom(\(value))"
    case .disclosureGroup:
      "disclosureGroup"
    case .group:
      "group"
    case .heading(let level):
      "heading(level: \(level))"
    case .image:
      "image"
    case .link:
      "link"
    case .list:
      "list"
    case .menu:
      "menu"
    case .menuItem:
      "menuItem"
    case .picker:
      "picker"
    case .popover:
      "popover"
    case .progressBar:
      "progressBar"
    case .region:
      "region"
    case .rowHeader:
      "rowHeader"
    case .scrollView:
      "scrollView"
    case .scrollViewWithIndicators:
      "scrollViewWithIndicators"
    case .section:
      "section"
    case .secureField:
      "secureField"
    case .separator:
      "separator"
    case .sheet:
      "sheet"
    case .slider:
      "slider"
    case .status:
      "status"
    case .stepper:
      "stepper"
    case .tab:
      "tab"
    case .tabPanel:
      "tabPanel"
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
    case .timer:
      "timer"
    case .toggle:
      "toggle"
    }
  }
}

public enum AccessibilityPoliteness: Hashable, Sendable, CustomStringConvertible {
  case off
  case polite
  case assertive

  public var description: String {
    switch self {
    case .off:
      "off"
    case .polite:
      "polite"
    case .assertive:
      "assertive"
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
  package var ownerNodeID: ViewNodeID?

  public init(
    identity: Identity,
    kind: RouteKind = .primary
  ) {
    self.identity = identity
    self.kind = kind
    ownerNodeID = nil
  }

  package init(
    identity: Identity,
    kind: RouteKind = .primary,
    ownerNodeID: ViewNodeID?
  ) {
    self.identity = identity
    self.kind = kind
    self.ownerNodeID = ownerNodeID
  }

  public var description: String {
    "\(identity.path)#\(kind)"
  }

  public static func == (lhs: RouteID, rhs: RouteID) -> Bool {
    guard lhs.identity == rhs.identity, lhs.kind == rhs.kind else {
      return false
    }
    switch (lhs.ownerNodeID, rhs.ownerNodeID) {
    case (.some(let lhsID), .some(let rhsID)):
      return lhsID == rhsID
    case (.none, _), (_, .none):
      return true
    }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(identity)
    hasher.combine(kind)
  }
}

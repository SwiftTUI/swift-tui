/// Authored reading structure, independent of raster line wrapping.
public enum AccessibilityTextKind: String, Sendable, Equatable {
  case paragraph, code, quotation
}

/// Sort direction of a table or grid header.
public enum AccessibilitySortDirection: String, Sendable, Equatable {
  case none, ascending, descending, other
}

/// Optional widget semantics shared by every presenter.
///
/// `nil` leaves a property unspecified during composition; explicit `false`,
/// an empty string or an empty relation list overrides an earlier value.
/// Positions, levels and spans are one-based; counts accept -1 for unknown.
/// Relations name semantic identities in the same committed scene. Missing,
/// hidden and self targets are omitted by browser presenters.
/// This immutable payload keeps ordinary resolved nodes small.
public final class AccessibilityProperties: Equatable, Sendable {
  /// A scene-unique authored anchor for semantic relationships. It does not
  /// change graph identity and is resolved to a committed node before export.
  public let identifier: Identity?
  public let selected: Bool?
  public let expanded: Bool?
  public let required: Bool?
  public let invalid: Bool?
  public let busy: Bool?
  public let readOnly: Bool?
  public let description: String?
  public let valueDescription: String?
  public let language: String?
  public let headingLevel: Int?
  public let level: Int?
  public let positionInSet: Int?
  public let setSize: Int?
  public let rowIndex: Int?
  public let columnIndex: Int?
  public let rowCount: Int?
  public let columnCount: Int?
  public let rowSpan: Int?
  public let columnSpan: Int?
  public let textKind: AccessibilityTextKind?
  public let sort: AccessibilitySortDirection?
  public let labelledBy: [Identity]?
  public let describedBy: [Identity]?
  public let errorMessage: [Identity]?
  public let controls: [Identity]?
  public let owns: [Identity]?
  public let flowTo: [Identity]?
  public let activeDescendant: Identity?

  public init(
    selected: Bool? = nil,
    expanded: Bool? = nil,
    required: Bool? = nil,
    invalid: Bool? = nil,
    busy: Bool? = nil,
    readOnly: Bool? = nil,
    description: String? = nil,
    valueDescription: String? = nil,
    language: String? = nil,
    headingLevel: Int? = nil,
    level: Int? = nil,
    positionInSet: Int? = nil,
    setSize: Int? = nil,
    rowIndex: Int? = nil,
    columnIndex: Int? = nil,
    rowCount: Int? = nil,
    columnCount: Int? = nil,
    rowSpan: Int? = nil,
    columnSpan: Int? = nil,
    textKind: AccessibilityTextKind? = nil,
    sort: AccessibilitySortDirection? = nil,
    labelledBy: [Identity]? = nil,
    describedBy: [Identity]? = nil,
    errorMessage: [Identity]? = nil,
    controls: [Identity]? = nil,
    owns: [Identity]? = nil,
    flowTo: [Identity]? = nil,
    activeDescendant: Identity? = nil,
    identifier: Identity? = nil
  ) {
    self.identifier = identifier
    self.selected = selected
    self.expanded = expanded
    self.required = required
    self.invalid = invalid
    self.busy = busy
    self.readOnly = readOnly
    self.description = description
    self.valueDescription = valueDescription
    self.language = language
    self.headingLevel = headingLevel.flatMap {
      $0 > 0 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil
    }
    self.level = level.flatMap { $0 > 0 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil }
    self.positionInSet = positionInSet.flatMap {
      $0 > 0 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil
    }
    self.setSize = setSize.flatMap { $0 >= -1 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil }
    self.rowIndex = rowIndex.flatMap { $0 > 0 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil }
    self.columnIndex = columnIndex.flatMap {
      $0 > 0 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil
    }
    self.rowCount = rowCount.flatMap { $0 >= -1 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil }
    self.columnCount = columnCount.flatMap {
      $0 >= -1 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil
    }
    self.rowSpan = rowSpan.flatMap { $0 > 0 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil }
    self.columnSpan = columnSpan.flatMap { $0 > 0 && Int64($0) <= 9_007_199_254_740_991 ? $0 : nil }
    self.textKind = textKind
    self.sort = sort
    self.labelledBy = labelledBy
    self.describedBy = describedBy
    self.errorMessage = errorMessage
    self.controls = controls
    self.owns = owns
    self.flowTo = flowTo
    self.activeDescendant = activeDescendant
  }

  public static func == (lhs: AccessibilityProperties, rhs: AccessibilityProperties) -> Bool {
    if lhs === rhs { return true }
    guard lhs.identifier == rhs.identifier else { return false }
    guard lhs.selected == rhs.selected else { return false }
    guard lhs.expanded == rhs.expanded else { return false }
    guard lhs.required == rhs.required else { return false }
    guard lhs.invalid == rhs.invalid else { return false }
    guard lhs.busy == rhs.busy else { return false }
    guard lhs.readOnly == rhs.readOnly else { return false }
    guard lhs.description == rhs.description else { return false }
    guard lhs.valueDescription == rhs.valueDescription else { return false }
    guard lhs.language == rhs.language else { return false }
    guard lhs.headingLevel == rhs.headingLevel else { return false }
    guard lhs.level == rhs.level else { return false }
    guard lhs.positionInSet == rhs.positionInSet else { return false }
    guard lhs.setSize == rhs.setSize else { return false }
    guard lhs.rowIndex == rhs.rowIndex else { return false }
    guard lhs.columnIndex == rhs.columnIndex else { return false }
    guard lhs.rowCount == rhs.rowCount else { return false }
    guard lhs.columnCount == rhs.columnCount else { return false }
    guard lhs.rowSpan == rhs.rowSpan else { return false }
    guard lhs.columnSpan == rhs.columnSpan else { return false }
    guard lhs.textKind == rhs.textKind else { return false }
    guard lhs.sort == rhs.sort else { return false }
    guard lhs.labelledBy == rhs.labelledBy else { return false }
    guard lhs.describedBy == rhs.describedBy else { return false }
    guard lhs.errorMessage == rhs.errorMessage else { return false }
    guard lhs.controls == rhs.controls else { return false }
    guard lhs.owns == rhs.owns else { return false }
    guard lhs.flowTo == rhs.flowTo else { return false }
    guard lhs.activeDescendant == rhs.activeDescendant else { return false }
    return true
  }

  /// Combines individual properties, with the supplied payload taking precedence.
  public func merging(_ other: AccessibilityProperties) -> AccessibilityProperties {
    let selected = other.selected ?? self.selected
    let expanded = other.expanded ?? self.expanded
    let required = other.required ?? self.required
    let invalid = other.invalid ?? self.invalid
    let busy = other.busy ?? self.busy
    let readOnly = other.readOnly ?? self.readOnly
    let description = other.description ?? self.description
    let valueDescription = other.valueDescription ?? self.valueDescription
    let language = other.language ?? self.language
    let headingLevel = other.headingLevel ?? self.headingLevel
    let level = other.level ?? self.level
    let positionInSet = other.positionInSet ?? self.positionInSet
    let setSize = other.setSize ?? self.setSize
    let rowIndex = other.rowIndex ?? self.rowIndex
    let columnIndex = other.columnIndex ?? self.columnIndex
    let rowCount = other.rowCount ?? self.rowCount
    let columnCount = other.columnCount ?? self.columnCount
    let rowSpan = other.rowSpan ?? self.rowSpan
    let columnSpan = other.columnSpan ?? self.columnSpan
    let textKind = other.textKind ?? self.textKind
    let sort = other.sort ?? self.sort
    let labelledBy = other.labelledBy ?? self.labelledBy
    let describedBy = other.describedBy ?? self.describedBy
    let errorMessage = other.errorMessage ?? self.errorMessage
    let controls = other.controls ?? self.controls
    let owns = other.owns ?? self.owns
    let flowTo = other.flowTo ?? self.flowTo
    let activeDescendant = other.activeDescendant ?? self.activeDescendant
    return .init(
      selected: selected,
      expanded: expanded,
      required: required,
      invalid: invalid,
      busy: busy,
      readOnly: readOnly,
      description: description,
      valueDescription: valueDescription,
      language: language,
      headingLevel: headingLevel,
      level: level,
      positionInSet: positionInSet,
      setSize: setSize,
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      rowCount: rowCount,
      columnCount: columnCount,
      rowSpan: rowSpan,
      columnSpan: columnSpan,
      textKind: textKind,
      sort: sort,
      labelledBy: labelledBy,
      describedBy: describedBy,
      errorMessage: errorMessage,
      controls: controls,
      owns: owns,
      flowTo: flowTo,
      activeDescendant: activeDescendant,
      identifier: other.identifier ?? self.identifier
    )
  }

  /// Resolve authored anchors to current semantic identities and drop stale targets.
  package func resolvingReferences(_ resolve: (Identity) -> Identity?) -> AccessibilityProperties {
    if identifier == nil && labelledBy == nil && describedBy == nil && errorMessage == nil
      && controls == nil && owns == nil && flowTo == nil && activeDescendant == nil
    {
      return self
    }
    let labelledBy = self.labelledBy.map { $0.compactMap(resolve) }
    let describedBy = self.describedBy.map { $0.compactMap(resolve) }
    let errorMessage = self.errorMessage.map { $0.compactMap(resolve) }
    let controls = self.controls.map { $0.compactMap(resolve) }
    let owns = self.owns.map { $0.compactMap(resolve) }
    let flowTo = self.flowTo.map { $0.compactMap(resolve) }
    let activeDescendant = self.activeDescendant.flatMap(resolve)
    return .init(
      selected: selected,
      expanded: expanded,
      required: required,
      invalid: invalid,
      busy: busy,
      readOnly: readOnly,
      description: description,
      valueDescription: valueDescription,
      language: language,
      headingLevel: headingLevel,
      level: level,
      positionInSet: positionInSet,
      setSize: setSize,
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      rowCount: rowCount,
      columnCount: columnCount,
      rowSpan: rowSpan,
      columnSpan: columnSpan,
      textKind: textKind,
      sort: sort,
      labelledBy: labelledBy,
      describedBy: describedBy,
      errorMessage: errorMessage,
      controls: controls,
      owns: owns,
      flowTo: flowTo,
      activeDescendant: activeDescendant
    )
  }
}

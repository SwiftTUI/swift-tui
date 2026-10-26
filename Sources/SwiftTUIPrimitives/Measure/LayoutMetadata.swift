package struct LayoutMetadata: Sendable {
  private var authoredLayoutPriority: Double?
  package var layoutPriority: Double {
    get { authoredLayoutPriority ?? 0 }
    set { authoredLayoutPriority = newValue }
  }
  package var fixedSizeHorizontal: Bool
  package var fixedSizeVertical: Bool
  package var minimumWidth: Int?
  package var minimumHeight: Int?
  package var lineLimit: Int?
  package var textTruncationMode: TextTruncationMode?
  package var textWrappingStrategy: TextWrappingStrategy?
  package var spacing: Spacing
  package var alignmentKeys: [String]
  package var layoutValues: [String: String]
  private var layoutValueStorage: [ObjectIdentifier: LayoutValueBox]
  private var horizontalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int]
  private var verticalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int]

  package init(
    layoutPriority: Double? = nil,
    fixedSizeHorizontal: Bool = false,
    fixedSizeVertical: Bool = false,
    minimumWidth: Int? = nil,
    minimumHeight: Int? = nil,
    lineLimit: Int? = nil,
    textTruncationMode: TextTruncationMode? = nil,
    textWrappingStrategy: TextWrappingStrategy? = nil,
    spacing: Spacing = .init(),
    alignmentKeys: [String] = [],
    layoutValues: [String: String] = [:],
    layoutValueStorage: [ObjectIdentifier: any Sendable] = [:],
    horizontalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int] = [:],
    verticalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int] = [:]
  ) {
    self.authoredLayoutPriority = layoutPriority
    self.fixedSizeHorizontal = fixedSizeHorizontal
    self.fixedSizeVertical = fixedSizeVertical
    self.minimumWidth = minimumWidth.map { max(0, $0) }
    self.minimumHeight = minimumHeight.map { max(0, $0) }
    self.lineLimit = lineLimit
    self.textTruncationMode = textTruncationMode
    self.textWrappingStrategy = textWrappingStrategy
    self.spacing = spacing
    self.alignmentKeys = alignmentKeys
    self.layoutValues = layoutValues
    self.layoutValueStorage = layoutValueStorage.mapValues(LayoutValueBox.init)
    self.horizontalAlignmentGuideStorage = horizontalAlignmentGuideStorage
    self.verticalAlignmentGuideStorage = verticalAlignmentGuideStorage
  }

  package func merging(_ other: Self) -> Self {
    var merged = self
    if let priority = other.authoredLayoutPriority {
      merged.layoutPriority = priority
    }
    merged.fixedSizeHorizontal = fixedSizeHorizontal || other.fixedSizeHorizontal
    merged.fixedSizeVertical = fixedSizeVertical || other.fixedSizeVertical
    merged.minimumWidth = other.minimumWidth ?? minimumWidth
    merged.minimumHeight = other.minimumHeight ?? minimumHeight
    merged.lineLimit = other.lineLimit ?? lineLimit
    merged.textTruncationMode = other.textTruncationMode ?? textTruncationMode
    merged.textWrappingStrategy = other.textWrappingStrategy ?? textWrappingStrategy
    merged.spacing = spacing.merging(other.spacing)
    for key in other.alignmentKeys where !merged.alignmentKeys.contains(key) {
      merged.alignmentKeys.append(key)
    }
    merged.layoutValues.merge(other.layoutValues) { _, new in new }
    merged.layoutValueStorage.merge(other.layoutValueStorage) { _, new in new }
    merged.horizontalAlignmentGuideStorage.merge(other.horizontalAlignmentGuideStorage) { _, new in
      new
    }
    merged.verticalAlignmentGuideStorage.merge(other.verticalAlignmentGuideStorage) { _, new in new
    }
    return merged
  }

  package func settingLayoutValue<Value: Sendable>(
    _ value: Value,
    for keyIdentifier: ObjectIdentifier,
    debugName: String,
    debugValue: String
  ) -> Self {
    var copy = self
    copy.layoutValues[debugName] = debugValue
    copy.layoutValueStorage[keyIdentifier] = LayoutValueBox(value)
    return copy
  }

  package func layoutValue<Value: Sendable>(
    for keyIdentifier: ObjectIdentifier,
    as _: Value.Type = Value.self
  ) -> Value? {
    guard let box = layoutValueStorage[keyIdentifier] else { return nil }
    return box.value as? Value
  }

  package func settingHorizontalAlignmentGuide(
    _ alignment: HorizontalAlignment,
    debugName: String,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> Self {
    var copy = self
    if !copy.alignmentKeys.contains(debugName) {
      copy.alignmentKeys.append(debugName)
    }
    copy.horizontalAlignmentGuideStorage[alignment.key] = computeValue
    return copy
  }

  package func settingVerticalAlignmentGuide(
    _ alignment: VerticalAlignment,
    debugName: String,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> Self {
    var copy = self
    if !copy.alignmentKeys.contains(debugName) {
      copy.alignmentKeys.append(debugName)
    }
    copy.verticalAlignmentGuideStorage[alignment.key] = computeValue
    return copy
  }

  /// True when this metadata carries any explicit alignment-guide closure.
  /// Guide closures are invisible to `==` (`alignmentKeys` compares only
  /// which alignments have guides, not what they compute), so equivalence
  /// gates that reuse cached placement must treat guide-carrying nodes as
  /// never provably unchanged — a re-authored closure with a different
  /// capture would otherwise keep serving the first capture's placement.
  package var hasExplicitAlignmentGuides: Bool {
    !horizontalAlignmentGuideStorage.isEmpty || !verticalAlignmentGuideStorage.isEmpty
  }

  package func hasExplicitHorizontalAlignmentGuide(
    _ alignment: HorizontalAlignment
  ) -> Bool {
    horizontalAlignmentGuideStorage[alignment.key] != nil
  }

  package func hasExplicitVerticalAlignmentGuide(
    _ alignment: VerticalAlignment
  ) -> Bool {
    verticalAlignmentGuideStorage[alignment.key] != nil
  }

  package func applyingGuides(to base: ViewDimensions) -> ViewDimensions {
    let horizontalGuideStorage = horizontalAlignmentGuideStorage
    let verticalGuideStorage = verticalAlignmentGuideStorage

    // A guide closure runs once on its base's public values. Its value is
    // half a cell past its integer when it read a half-cell value, so a guide
    // computed from the centre (`{ $0[.center] }`) keeps the centre's half
    // cell (`ViewDimensions.evaluatingGuide(_:)`).
    return
      base
      .overridingHorizontalGuides(positions: { alignment in
        horizontalGuideStorage[alignment.key].map { computeValue in
          ViewDimensions.evaluatingGuide { computeValue(base) }
        }
      })
      .overridingVerticalGuides(positions: { alignment in
        verticalGuideStorage[alignment.key].map { computeValue in
          ViewDimensions.evaluatingGuide { computeValue(base) }
        }
      })
  }

  package func viewDimensions(for size: CellSize) -> ViewDimensions {
    applyingGuides(to: ViewDimensions(width: size.width, height: size.height))
  }
}

extension LayoutMetadata: Equatable {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.hasSameFields(as: rhs) && lhs.layoutValueStorage == rhs.layoutValueStorage
  }

  /// A cache miss is not proof of changed output: opaque, non-Equatable
  /// layout values deliberately deny reuse. Soundness diagnostics alarm
  /// only when a compared field or typed value proves a difference.
  package func isKnownToDiffer(from other: Self) -> Bool {
    if !hasSameFields(as: other) || layoutValueStorage.keys != other.layoutValueStorage.keys {
      return true
    }
    return layoutValueStorage.contains { key, box in
      guard let otherBox = other.layoutValueStorage[key] else { return true }
      return box.comparison(to: otherBox) == false
    }
  }

  private func hasSameFields(as rhs: Self) -> Bool {
    let lhs = self
    return lhs.authoredLayoutPriority == rhs.authoredLayoutPriority
      && lhs.fixedSizeHorizontal == rhs.fixedSizeHorizontal
      && lhs.fixedSizeVertical == rhs.fixedSizeVertical
      && lhs.minimumWidth == rhs.minimumWidth
      && lhs.minimumHeight == rhs.minimumHeight
      && lhs.lineLimit == rhs.lineLimit
      && lhs.textTruncationMode == rhs.textTruncationMode
      && lhs.textWrappingStrategy == rhs.textWrappingStrategy
      && lhs.spacing == rhs.spacing
      && lhs.alignmentKeys == rhs.alignmentKeys
      && lhs.layoutValues == rhs.layoutValues
  }
}

/// Debug descriptions are diagnostic text, never value identity. Unknown
/// equality conservatively invalidates a re-authored value; a copied box
/// remains reflexive and preserves reuse for unchanged metadata.
private final class LayoutValueBox: Sendable, Equatable {
  let value: any Sendable
  init(_ value: any Sendable) { self.value = value }

  static func == (lhs: LayoutValueBox, rhs: LayoutValueBox) -> Bool {
    lhs.comparison(to: rhs) == true
  }

  func comparison(to other: LayoutValueBox) -> Bool? {
    if self === other { return true }
    if type(of: value) != type(of: other.value) { return false }
    guard let equatable = value as? any Equatable else { return nil }
    return Self.equals(equatable, other.value)
  }

  private static func equals<Value: Equatable>(_ value: Value, _ other: any Sendable) -> Bool {
    guard let other = other as? Value else { return false }
    return value == other
  }
}

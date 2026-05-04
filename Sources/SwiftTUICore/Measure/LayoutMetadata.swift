package struct LayoutMetadata: Sendable {
  package var layoutPriority: Double
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
  private var layoutValueStorage: [ObjectIdentifier: any Sendable]
  private var horizontalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int]
  private var verticalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int]

  package init(
    layoutPriority: Double = 0,
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
    self.layoutPriority = layoutPriority
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
    self.layoutValueStorage = layoutValueStorage
    self.horizontalAlignmentGuideStorage = horizontalAlignmentGuideStorage
    self.verticalAlignmentGuideStorage = verticalAlignmentGuideStorage
  }

  package func merging(_ other: Self) -> Self {
    var merged = self
    if other.layoutPriority != 0 {
      merged.layoutPriority = other.layoutPriority
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
    copy.layoutValueStorage[keyIdentifier] = value
    return copy
  }

  package func layoutValue<Value: Sendable>(
    for keyIdentifier: ObjectIdentifier,
    as _: Value.Type = Value.self
  ) -> Value? {
    layoutValueStorage[keyIdentifier] as? Value
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

    return
      base
      .overridingHorizontalGuides { alignment in
        horizontalGuideStorage[alignment.key].map { computeValue in
          computeValue(base)
        }
      }
      .overridingVerticalGuides { alignment in
        verticalGuideStorage[alignment.key].map { computeValue in
          computeValue(base)
        }
      }
  }

  package func viewDimensions(for size: CellSize) -> ViewDimensions {
    applyingGuides(to: ViewDimensions(width: size.width, height: size.height))
  }
}

extension LayoutMetadata: Equatable {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.layoutPriority == rhs.layoutPriority
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

/// The measured size assigned to a child during container layout.

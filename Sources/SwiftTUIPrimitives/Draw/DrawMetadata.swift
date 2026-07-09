/// Visual metadata attached to a resolved node before draw extraction.
package struct DrawMetadata: Equatable, Sendable {
  /// List-specific styling preferences carried by draw metadata.
  package struct ListStyleMetadata: Equatable, Sendable {
    package var rowForegroundStyle: AnyShapeStyle?
    package var rowBackgroundStyle: AnyShapeStyle?
    package var rowSeparatorTopVisibility: Visibility?
    package var rowSeparatorBottomVisibility: Visibility?
    package var sectionSeparatorTopVisibility: Visibility?
    package var sectionSeparatorBottomVisibility: Visibility?

    package init(
      rowForegroundStyle: AnyShapeStyle? = nil,
      rowBackgroundStyle: AnyShapeStyle? = nil,
      rowSeparatorTopVisibility: Visibility? = nil,
      rowSeparatorBottomVisibility: Visibility? = nil,
      sectionSeparatorTopVisibility: Visibility? = nil,
      sectionSeparatorBottomVisibility: Visibility? = nil
    ) {
      self.rowForegroundStyle = rowForegroundStyle
      self.rowBackgroundStyle = rowBackgroundStyle
      self.rowSeparatorTopVisibility = rowSeparatorTopVisibility
      self.rowSeparatorBottomVisibility = rowSeparatorBottomVisibility
      self.sectionSeparatorTopVisibility = sectionSeparatorTopVisibility
      self.sectionSeparatorBottomVisibility = sectionSeparatorBottomVisibility
    }

    package var isDefault: Bool {
      rowForegroundStyle == nil
        && rowBackgroundStyle == nil
        && rowSeparatorTopVisibility == nil
        && rowSeparatorBottomVisibility == nil
        && sectionSeparatorTopVisibility == nil
        && sectionSeparatorBottomVisibility == nil
    }

    package func merging(_ other: Self) -> Self {
      .init(
        rowForegroundStyle: other.rowForegroundStyle ?? rowForegroundStyle,
        rowBackgroundStyle: other.rowBackgroundStyle ?? rowBackgroundStyle,
        rowSeparatorTopVisibility: other.rowSeparatorTopVisibility ?? rowSeparatorTopVisibility,
        rowSeparatorBottomVisibility: other.rowSeparatorBottomVisibility
          ?? rowSeparatorBottomVisibility,
        sectionSeparatorTopVisibility: other.sectionSeparatorTopVisibility
          ?? sectionSeparatorTopVisibility,
        sectionSeparatorBottomVisibility: other.sectionSeparatorBottomVisibility
          ?? sectionSeparatorBottomVisibility
      )
    }
  }

  package struct HeavyFields: Equatable, Sendable {
    var baseStyle: BaseStyle
    var borderShapeStyle: AnyShapeStyle?
    var borderStrokeStyle: StrokeStyle?
    var scrollIndicatorAxes: AxisSet?
    var focusedScrollIndicatorAxes: AxisSet?
    var scrollIndicatorForegroundStyle: AnyShapeStyle?
    var listStyle: ListStyleMetadata?

    init(
      foregroundStyle: AnyShapeStyle? = nil,
      backgroundStyle: AnyShapeStyle? = nil,
      borderShapeStyle: AnyShapeStyle? = nil,
      borderStrokeStyle: StrokeStyle? = nil,
      scrollIndicatorAxes: AxisSet? = nil,
      focusedScrollIndicatorAxes: AxisSet? = nil,
      scrollIndicatorForegroundStyle: AnyShapeStyle? = nil,
      listStyle: ListStyleMetadata? = nil,
      emphasis: TextStyle.TextEmphasis = [],
      underlineStyle: TextLineStyle? = nil,
      strikethroughStyle: TextLineStyle? = nil,
      opacity: Double? = nil
    ) {
      baseStyle = .init(
        foregroundStyle: foregroundStyle,
        backgroundStyle: backgroundStyle,
        emphasis: emphasis,
        underlineStyle: underlineStyle,
        strikethroughStyle: strikethroughStyle,
        opacity: opacity
      )
      self.borderShapeStyle = borderShapeStyle
      self.borderStrokeStyle = borderStrokeStyle
      self.scrollIndicatorAxes = scrollIndicatorAxes
      self.focusedScrollIndicatorAxes = focusedScrollIndicatorAxes
      self.scrollIndicatorForegroundStyle = scrollIndicatorForegroundStyle
      self.listStyle = listStyle
    }

    func merging(_ other: Self) -> Self {
      var merged = self
      merged.baseStyle = baseStyle.merging(other.baseStyle)
      merged.borderShapeStyle = other.borderShapeStyle ?? borderShapeStyle
      merged.borderStrokeStyle = other.borderStrokeStyle ?? borderStrokeStyle
      merged.scrollIndicatorAxes = other.scrollIndicatorAxes ?? scrollIndicatorAxes
      merged.focusedScrollIndicatorAxes =
        other.focusedScrollIndicatorAxes ?? focusedScrollIndicatorAxes
      merged.scrollIndicatorForegroundStyle =
        other.scrollIndicatorForegroundStyle ?? scrollIndicatorForegroundStyle
      merged.listStyle =
        switch (listStyle, other.listStyle) {
        case (let lhs?, let rhs?):
          lhs.merging(rhs)
        case (_, let rhs?):
          rhs
        case (let lhs?, nil):
          lhs
        case (nil, nil):
          nil
        }
      return merged
    }
  }

  package var heavyFields: Boxed<HeavyFields>
  package var clipsToBounds: Bool
  package var clipIdentifier: String?
  package var compositingHint: String?
  package var imagePreference: String?
  package var ruleStackAxis: Axis?

  package init(
    foregroundStyle: AnyShapeStyle? = nil,
    backgroundStyle: AnyShapeStyle? = nil,
    borderShapeStyle: AnyShapeStyle? = nil,
    borderStrokeStyle: StrokeStyle? = nil,
    scrollIndicatorAxes: AxisSet? = nil,
    focusedScrollIndicatorAxes: AxisSet? = nil,
    scrollIndicatorForegroundStyle: AnyShapeStyle? = nil,
    listStyle: ListStyleMetadata? = nil,
    listRowForegroundStyle: AnyShapeStyle? = nil,
    listRowBackgroundStyle: AnyShapeStyle? = nil,
    listRowSeparatorTopVisibility: Visibility? = nil,
    listRowSeparatorBottomVisibility: Visibility? = nil,
    listSectionSeparatorTopVisibility: Visibility? = nil,
    listSectionSeparatorBottomVisibility: Visibility? = nil,
    emphasis: TextStyle.TextEmphasis = [],
    underlineStyle: TextLineStyle? = nil,
    strikethroughStyle: TextLineStyle? = nil,
    opacity: Double? = nil,
    clipsToBounds: Bool = false,
    clipIdentifier: String? = nil,
    compositingHint: String? = nil,
    imagePreference: String? = nil
  ) {
    let resolvedListStyle =
      listStyle?.merging(
        .init(
          rowForegroundStyle: listRowForegroundStyle,
          rowBackgroundStyle: listRowBackgroundStyle,
          rowSeparatorTopVisibility: listRowSeparatorTopVisibility,
          rowSeparatorBottomVisibility: listRowSeparatorBottomVisibility,
          sectionSeparatorTopVisibility: listSectionSeparatorTopVisibility,
          sectionSeparatorBottomVisibility: listSectionSeparatorBottomVisibility
        )
      )
      ?? .init(
        rowForegroundStyle: listRowForegroundStyle,
        rowBackgroundStyle: listRowBackgroundStyle,
        rowSeparatorTopVisibility: listRowSeparatorTopVisibility,
        rowSeparatorBottomVisibility: listRowSeparatorBottomVisibility,
        sectionSeparatorTopVisibility: listSectionSeparatorTopVisibility,
        sectionSeparatorBottomVisibility: listSectionSeparatorBottomVisibility
      )
    heavyFields = Boxed(
      HeavyFields(
        foregroundStyle: foregroundStyle,
        backgroundStyle: backgroundStyle,
        borderShapeStyle: borderShapeStyle,
        borderStrokeStyle: borderStrokeStyle,
        scrollIndicatorAxes: scrollIndicatorAxes,
        focusedScrollIndicatorAxes: focusedScrollIndicatorAxes,
        scrollIndicatorForegroundStyle: scrollIndicatorForegroundStyle,
        listStyle: resolvedListStyle.isDefault ? nil : resolvedListStyle,
        emphasis: emphasis,
        underlineStyle: underlineStyle,
        strikethroughStyle: strikethroughStyle,
        opacity: opacity
      )
    )
    self.clipsToBounds = clipsToBounds
    self.clipIdentifier = clipIdentifier
    self.compositingHint = compositingHint
    self.imagePreference = imagePreference
    ruleStackAxis = nil
  }

  package var baseStyle: BaseStyle {
    get { heavyFields.value.baseStyle }
    set { heavyFields.value.baseStyle = newValue }
  }

  package var foregroundStyle: AnyShapeStyle? {
    get { baseStyle.foregroundStyle }
    set { baseStyle.foregroundStyle = newValue }
  }

  package var backgroundStyle: AnyShapeStyle? {
    get { baseStyle.backgroundStyle }
    set { baseStyle.backgroundStyle = newValue }
  }

  package var emphasis: TextStyle.TextEmphasis {
    get { baseStyle.emphasis }
    set { baseStyle.emphasis = newValue }
  }

  package var underlineStyle: TextLineStyle? {
    get { baseStyle.underlineStyle }
    set { baseStyle.underlineStyle = newValue }
  }

  package var strikethroughStyle: TextLineStyle? {
    get { baseStyle.strikethroughStyle }
    set { baseStyle.strikethroughStyle = newValue }
  }

  package var opacity: Double {
    get { baseStyle.opacity }
    set { baseStyle.opacity = newValue }
  }

  package var explicitOpacity: Double? {
    get { baseStyle.explicitOpacity }
    set { baseStyle.explicitOpacity = newValue }
  }

  package var listRowForegroundStyle: AnyShapeStyle? {
    get { listStyle?.rowForegroundStyle }
    set {
      var updated = listStyle ?? .init()
      updated.rowForegroundStyle = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listRowBackgroundStyle: AnyShapeStyle? {
    get { listStyle?.rowBackgroundStyle }
    set {
      var updated = listStyle ?? .init()
      updated.rowBackgroundStyle = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listRowSeparatorTopVisibility: Visibility? {
    get { listStyle?.rowSeparatorTopVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.rowSeparatorTopVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listRowSeparatorBottomVisibility: Visibility? {
    get { listStyle?.rowSeparatorBottomVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.rowSeparatorBottomVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listSectionSeparatorTopVisibility: Visibility? {
    get { listStyle?.sectionSeparatorTopVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.sectionSeparatorTopVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listSectionSeparatorBottomVisibility: Visibility? {
    get { listStyle?.sectionSeparatorBottomVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.sectionSeparatorBottomVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package func merging(_ other: Self) -> Self {
    var merged = self
    merged.heavyFields.value = heavyFields.value.merging(other.heavyFields.value)
    merged.clipsToBounds = clipsToBounds || other.clipsToBounds
    merged.clipIdentifier = other.clipIdentifier ?? clipIdentifier
    merged.compositingHint = other.compositingHint ?? compositingHint
    merged.imagePreference = other.imagePreference ?? imagePreference
    merged.ruleStackAxis = other.ruleStackAxis ?? ruleStackAxis
    return merged
  }

  package var borderShapeStyle: AnyShapeStyle? {
    get { heavyFields.value.borderShapeStyle }
    set { heavyFields.value.borderShapeStyle = newValue }
  }

  package var borderStrokeStyle: StrokeStyle? {
    get { heavyFields.value.borderStrokeStyle }
    set { heavyFields.value.borderStrokeStyle = newValue }
  }

  package var scrollIndicatorAxes: AxisSet? {
    get { heavyFields.value.scrollIndicatorAxes }
    set { heavyFields.value.scrollIndicatorAxes = newValue }
  }

  package var focusedScrollIndicatorAxes: AxisSet? {
    get { heavyFields.value.focusedScrollIndicatorAxes }
    set { heavyFields.value.focusedScrollIndicatorAxes = newValue }
  }

  package var scrollIndicatorForegroundStyle: AnyShapeStyle? {
    get { heavyFields.value.scrollIndicatorForegroundStyle }
    set { heavyFields.value.scrollIndicatorForegroundStyle = newValue }
  }

  package var listStyle: ListStyleMetadata? {
    get { heavyFields.value.listStyle }
    set { heavyFields.value.listStyle = newValue }
  }
}

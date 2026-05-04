public import SwiftTUICore

extension Text {
  /// Alias for the low-level text line decoration style.
  public typealias LineStyle = TextLineStyle

  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
    mutatingDrawMetadata { metadata in
      metadata.foregroundStyle = AnyShapeStyle(style)
    }
  }

  public func bold() -> Text {
    bold(true)
  }

  public func bold(_ isActive: Bool) -> Text {
    applyingEmphasis(.bold, isActive: isActive)
  }

  public func italic() -> Text {
    italic(true)
  }

  public func italic(_ isActive: Bool) -> Text {
    applyingEmphasis(.italic, isActive: isActive)
  }

  public func faint() -> Text {
    faint(true)
  }

  public func faint(_ isActive: Bool) -> Text {
    applyingEmphasis(.faint, isActive: isActive)
  }

  public func blink() -> Text {
    blink(true)
  }

  public func blink(_ isActive: Bool) -> Text {
    applyingEmphasis(.blink, isActive: isActive)
  }

  public func reverse() -> Text {
    reverse(true)
  }

  public func reverse(_ isActive: Bool) -> Text {
    applyingEmphasis(.reverse, isActive: isActive)
  }

  public func underline(
    _ isActive: Bool = true,
    color: Color? = nil
  ) -> Text {
    underline(
      isActive,
      pattern: .solid,
      color: color
    )
  }

  public func underline(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> Text {
    mutatingDrawMetadata { metadata in
      metadata.underlineStyle = isActive ? .init(pattern: pattern, color: color) : nil
    }
  }

  public func strikethrough(
    _ isActive: Bool = true,
    color: Color? = nil
  ) -> Text {
    strikethrough(
      isActive,
      pattern: .solid,
      color: color
    )
  }

  public func strikethrough(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> Text {
    mutatingDrawMetadata { metadata in
      metadata.strikethroughStyle = isActive ? .init(pattern: pattern, color: color) : nil
    }
  }

  private func applyingEmphasis(
    _ emphasis: TextStyle.TextEmphasis,
    isActive: Bool
  ) -> Text {
    mutatingDrawMetadata { metadata in
      if isActive {
        guard !metadata.emphasis.contains(emphasis) else {
          return
        }
        metadata.emphasis.formUnion(emphasis)
        return
      }

      metadata.emphasis.subtract(emphasis)
    }
  }

  private func mutatingDrawMetadata(
    _ update: (inout DrawMetadata) -> Void
  ) -> Text {
    var copy = self
    update(&copy.drawMetadata)
    return copy
  }
}

public import SwiftTUICore

extension Text {
  /// Alias for the low-level text line decoration style.
  public typealias LineStyle = TextLineStyle

  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
    mutatingDrawMetadata { metadata in
      metadata.foregroundStyle = AnyShapeStyle(style)
    }
  }

  /// Paints the cells this text occupies with a background shape style,
  /// including the fragment's cells when it is interpolated into
  /// ``Text/RichContent``. Named for the terminal-cell semantics; SwiftUI's
  /// `backgroundStyle(_:)` is an environment write with different behavior.
  public func cellBackground<S: ShapeStyle>(_ style: S) -> Text {
    mutatingDrawMetadata { metadata in
      metadata.backgroundStyle = AnyShapeStyle(style)
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
    var copy = mutatingDrawMetadata { metadata in
      metadata.underlineStyle = isActive ? .init(pattern: pattern, color: color) : nil
    }
    // An explicit `false` must suppress an ambient `View.underline()` too —
    // a bare nil style would read as "unstyled, inherit".
    copy.underlineExplicitlyCleared = !isActive
    return copy
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
    var copy = mutatingDrawMetadata { metadata in
      metadata.strikethroughStyle = isActive ? .init(pattern: pattern, color: color) : nil
    }
    copy.strikethroughExplicitlyCleared = !isActive
    return copy
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

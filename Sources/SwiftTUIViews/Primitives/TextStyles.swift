public import SwiftTUICore

extension Text {
  /// Alias for the low-level text line decoration style.
  public typealias LineStyle = TextLineStyle

  /// Paints this text's glyphs with a shape style.
  ///
  /// A value-level style stamped on the ``Text`` itself, so it survives
  /// interpolation into ``Text/RichContent`` and wins over the ambient
  /// `foregroundStyle(_:)` environment write. Prefer a semantic role such as
  /// `SemanticShapeStyle.muted` over a literal color so the paint follows the
  /// active theme.
  ///
  /// ```swift
  /// Text("Deprecated").foregroundStyle(SemanticShapeStyle.warning)
  /// ```
  ///
  /// - Parameter style: The paint for this text's glyphs.
  /// - Returns: A copy of this text carrying the foreground paint.
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

  /// Adds bold emphasis to this text.
  ///
  /// Shorthand for `bold(true)`.
  ///
  /// - Returns: A copy of this text with bold emphasis added.
  public func bold() -> Text {
    bold(true)
  }

  /// Adds or removes bold emphasis on this text.
  ///
  /// Emphasis accumulates as a set, so bold combines with italic and the
  /// other emphases rather than replacing them. Passing `false` removes bold
  /// and leaves the rest.
  ///
  /// - Parameter isActive: Whether bold emphasis is present.
  /// - Returns: A copy of this text with bold emphasis added or removed.
  public func bold(_ isActive: Bool) -> Text {
    applyingEmphasis(.bold, isActive: isActive)
  }

  /// Adds italic emphasis to this text.
  ///
  /// Shorthand for `italic(true)`. Terminals that cannot render italics may
  /// substitute another treatment.
  ///
  /// - Returns: A copy of this text with italic emphasis added.
  public func italic() -> Text {
    italic(true)
  }

  /// Adds or removes italic emphasis on this text.
  ///
  /// Emphasis accumulates as a set, so italic combines with the other
  /// emphases rather than replacing them.
  ///
  /// - Parameter isActive: Whether italic emphasis is present.
  /// - Returns: A copy of this text with italic emphasis added or removed.
  public func italic(_ isActive: Bool) -> Text {
    applyingEmphasis(.italic, isActive: isActive)
  }

  /// Adds faint emphasis to this text, the terminal's dim attribute.
  ///
  /// Shorthand for `faint(true)`.
  ///
  /// - Returns: A copy of this text with faint emphasis added.
  public func faint() -> Text {
    faint(true)
  }

  /// Adds or removes faint emphasis on this text.
  ///
  /// Emphasis accumulates as a set, so faint combines with the other emphases
  /// rather than replacing them.
  ///
  /// - Parameter isActive: Whether faint emphasis is present.
  /// - Returns: A copy of this text with faint emphasis added or removed.
  public func faint(_ isActive: Bool) -> Text {
    applyingEmphasis(.faint, isActive: isActive)
  }

  /// Adds blink emphasis to this text.
  ///
  /// Shorthand for `blink(true)`. Many terminals ignore the blink attribute,
  /// so do not rely on it to carry meaning on its own.
  ///
  /// - Returns: A copy of this text with blink emphasis added.
  public func blink() -> Text {
    blink(true)
  }

  /// Adds or removes blink emphasis on this text.
  ///
  /// Emphasis accumulates as a set, so blink combines with the other emphases
  /// rather than replacing them.
  ///
  /// - Parameter isActive: Whether blink emphasis is present.
  /// - Returns: A copy of this text with blink emphasis added or removed.
  public func blink(_ isActive: Bool) -> Text {
    applyingEmphasis(.blink, isActive: isActive)
  }

  /// Adds reverse-video emphasis to this text, swapping foreground and
  /// background.
  ///
  /// Shorthand for `reverse(true)`.
  ///
  /// - Returns: A copy of this text with reverse emphasis added.
  public func reverse() -> Text {
    reverse(true)
  }

  /// Adds or removes reverse-video emphasis on this text.
  ///
  /// Emphasis accumulates as a set, so reverse combines with the other
  /// emphases rather than replacing them.
  ///
  /// - Parameter isActive: Whether reverse emphasis is present.
  /// - Returns: A copy of this text with reverse emphasis added or removed.
  public func reverse(_ isActive: Bool) -> Text {
    applyingEmphasis(.reverse, isActive: isActive)
  }

  /// Underlines this text with a solid line.
  ///
  /// A value-level style, so it wins over an ambient `View.underline(_:color:)`
  /// for this run. An explicit `false` also suppresses an inherited underline
  /// rather than reading as unstyled.
  ///
  /// - Parameters:
  ///   - isActive: Whether the underline is drawn. Defaults to `true`.
  ///   - color: The underline color, or `nil` to use the run's foreground.
  /// - Returns: A copy of this text with the underline set or cleared.
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

  /// Underlines this text with an explicit line pattern.
  ///
  /// Behaves like `underline(_:color:)` and adds the pattern. An explicit
  /// `false` suppresses an inherited underline for this run.
  ///
  /// - Parameters:
  ///   - isActive: Whether the underline is drawn. Defaults to `true`.
  ///   - pattern: The line pattern, such as `.solid`, `.dashed`, or `.curly`.
  ///   - color: The underline color, or `nil` to use the run's foreground.
  /// - Returns: A copy of this text with the underline set or cleared.
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

  /// Strikes through this text with a solid line.
  ///
  /// A value-level style, so it wins over an ambient
  /// `View.strikethrough(_:color:)` for this run. An explicit `false` also
  /// suppresses an inherited strikethrough rather than reading as unstyled.
  ///
  /// - Parameters:
  ///   - isActive: Whether the line is drawn. Defaults to `true`.
  ///   - color: The line color, or `nil` to use the run's foreground.
  /// - Returns: A copy of this text with the strikethrough set or cleared.
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

  /// Strikes through this text with an explicit line pattern.
  ///
  /// Behaves like `strikethrough(_:color:)` and adds the pattern. An explicit
  /// `false` suppresses an inherited strikethrough for this run.
  ///
  /// - Parameters:
  ///   - isActive: Whether the line is drawn. Defaults to `true`.
  ///   - pattern: The line pattern, such as `.solid`, `.dashed`, or `.double`.
  ///   - color: The line color, or `nil` to use the run's foreground.
  /// - Returns: A copy of this text with the strikethrough set or cleared.
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

/// The terminal capabilities assumed when presenting a raster surface.
public struct TerminalCapabilityProfile: Equatable, Sendable {
  /// The glyph repertoire the presentation layer may emit.
  public enum GlyphLevel: String, Equatable, Sendable {
    case ascii
    case unicode
  }

  /// The color repertoire the presentation layer may emit.
  public enum ColorLevel: String, Equatable, Sendable {
    case none
    case ansi16
    case ansi256
    case trueColor
  }

  public var glyphLevel: GlyphLevel
  public var colorLevel: ColorLevel
  public var emitsStyleEscapeSequences: Bool
  public var supportsHyperlinks: Bool
  public var supportsMouseReporting: Bool
  public var supportsSynchronizedOutput: Bool

  /// Creates a terminal capability profile explicitly.
  public init(
    glyphLevel: GlyphLevel,
    colorLevel: ColorLevel,
    emitsStyleEscapeSequences: Bool,
    supportsHyperlinks: Bool = false,
    supportsMouseReporting: Bool = false,
    supportsSynchronizedOutput: Bool = false
  ) {
    self.glyphLevel = glyphLevel
    self.colorLevel = colorLevel
    self.emitsStyleEscapeSequences = emitsStyleEscapeSequences
    self.supportsHyperlinks = supportsHyperlinks
    self.supportsMouseReporting = supportsMouseReporting
    self.supportsSynchronizedOutput = supportsSynchronizedOutput
  }

  public static let previewUnicode = Self(
    glyphLevel: .unicode,
    colorLevel: .none,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: false,
    supportsMouseReporting: false
  )

  public static let previewASCII = Self(
    glyphLevel: .ascii,
    colorLevel: .none,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: false,
    supportsMouseReporting: false
  )

  public static let ansi16 = Self(
    glyphLevel: .unicode,
    colorLevel: .ansi16,
    emitsStyleEscapeSequences: true,
    supportsHyperlinks: true,
    supportsMouseReporting: true
  )

  public static let ansi256 = Self(
    glyphLevel: .unicode,
    colorLevel: .ansi256,
    emitsStyleEscapeSequences: true,
    supportsHyperlinks: true,
    supportsMouseReporting: true
  )

  public static let trueColor = Self(
    glyphLevel: .unicode,
    colorLevel: .trueColor,
    emitsStyleEscapeSequences: true,
    supportsHyperlinks: true,
    supportsMouseReporting: true
  )

  /// Detects a capability profile from environment variables and TTY status.
  public static func detect(
    environment: [String: String],
    isTTY: Bool
  ) -> Self {

    let term = environment["TERM"]?.lowercased() ?? ""
    let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
    let localeValues = [
      environment["LC_ALL"],
      environment["LC_CTYPE"],
      environment["LANG"],
    ]

    let supportsUnicode =
      localeValues
      .compactMap { $0?.lowercased() }
      .contains { value in
        value.contains("utf-8") || value.contains("utf8")
      }

    let glyphLevel: GlyphLevel = supportsUnicode ? .unicode : .ascii

    guard isTTY, term != "dumb" else {
      return Self(
        glyphLevel: glyphLevel,
        colorLevel: .none,
        emitsStyleEscapeSequences: false,
        supportsHyperlinks: false,
        supportsMouseReporting: false
      )
    }

    let colorLevel: ColorLevel
    if environment["NO_COLOR"] != nil {
      colorLevel = .none
    } else if colorTerm.contains("truecolor") || colorTerm.contains("24bit") {
      colorLevel = .trueColor
    } else if term.contains("256color") {
      colorLevel = .ansi256
    } else {
      colorLevel = .ansi16
    }

    return Self(
      glyphLevel: glyphLevel,
      colorLevel: colorLevel,
      emitsStyleEscapeSequences: colorLevel != .none,
      supportsHyperlinks: supportsHyperlinks(term: term),
      supportsMouseReporting: supportsMouseReporting(term: term),
      supportsSynchronizedOutput: supportsSynchronizedOutput(term: term)
    )
  }

  private static func supportsHyperlinks(
    term: String
  ) -> Bool {
    supportsRichTerminalFeatures(term: term)
  }

  private static func supportsMouseReporting(
    term: String
  ) -> Bool {
    supportsRichTerminalFeatures(term: term)
  }

  private static func supportsSynchronizedOutput(
    term: String
  ) -> Bool {
    supportsRichTerminalFeatures(term: term)
  }

  private static func supportsRichTerminalFeatures(
    term: String
  ) -> Bool {
    guard !term.isEmpty, term != "dumb" else {
      return false
    }

    let sgrCapableTerms = [
      "xterm",
      "screen",
      "tmux",
      "wezterm",
      "kitty",
      "ghostty",
      "rxvt",
      "alacritty",
      "foot",
      "st",
    ]

    return sgrCapableTerms.contains { candidate in
      term.contains(candidate)
    }
  }
}

extension TerminalCapabilityProfile {
  /// Returns a new profile with the user's explicit `RuntimeConfiguration`
  /// preferences applied on top of the detected profile.
  ///
  /// - `RuntimeConfiguration.color`:
  ///   - `.never`: forces `colorLevel = .none` and disables style escape
  ///     sequences. Wins regardless of TTY status.
  ///   - `.always`: forces `colorLevel` to at least `.ansi16` even when
  ///     the detected profile would have disabled color (non-TTY, etc.).
  ///   - `.auto`: no override; the detected level stands.
  /// - `RuntimeConfiguration.glyphs`:
  ///   - `.ascii`: forces `glyphLevel = .ascii`.
  ///   - `.unicode`: no override (unicode is the strict superset; if
  ///     detection picked ascii because of locale, the user's `.unicode`
  ///     preference is treated as a "don't restrict me" hint rather than
  ///     a "force unicode glyphs" override).
  ///
  /// Other `RuntimeConfiguration` fields (motion, output, web, debug) are not
  /// terminal capability inputs; this method ignores them.
  public func applying(_ configuration: RuntimeConfiguration) -> Self {
    var result = self
    switch configuration.color {
    case .never:
      result.colorLevel = .none
      result.emitsStyleEscapeSequences = false
    case .always:
      if result.colorLevel == .none {
        result.colorLevel = .ansi16
        result.emitsStyleEscapeSequences = true
      }
    case .auto:
      break
    }
    switch configuration.glyphs {
    case .ascii:
      result.glyphLevel = .ascii
    case .unicode:
      break
    }
    return result
  }
}

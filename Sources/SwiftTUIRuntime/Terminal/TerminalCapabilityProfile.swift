/// The terminal capabilities assumed when presenting a raster surface.
public struct TerminalCapabilityProfile: Equatable, Sendable {
  /// The glyph repertoire that the presentation layer can emit.
  public enum GlyphLevel: String, Equatable, Sendable {
    case ascii
    case unicode
  }

  /// The color repertoire that the presentation layer can emit.
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
  /// Whether the terminal honors DECSTBM scroll regions with SU/SD (CSI r,
  /// CSI S, CSI T) — the vocabulary the verified scroll-region emission
  /// (R2.3) uses to translate a full-width band instead of repainting it.
  ///
  /// VT100-core, so detection defaults it **on** for any non-dumb TTY. Kept
  /// `package` (not public API): the explicit public initializer leaves it
  /// `false`, which keeps hand-built profiles — previews, fixtures, protocol
  /// stubs — byte-stable unless they opt in.
  package var supportsScrollRegions = false

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
  ///
  /// On POSIX platforms the terminal emulator sits at the far end of a pty
  /// and can only be known through the environment it exports, so detection
  /// reads `TERM`, `COLORTERM`, `NO_COLOR`, and the locale
  /// (``detectPOSIXTerminal(environment:isTTY:)``). On Windows the process
  /// talks to a console host the framework configures itself, so the
  /// platform carries the defaults and the environment only refines them
  /// (``detectWindowsConsole(environment:isTTY:)``).
  public static func detect(
    environment: [String: String],
    isTTY: Bool
  ) -> Self {
    #if os(Windows)
      detectWindowsConsole(environment: environment, isTTY: isTTY)
    #else
      detectPOSIXTerminal(environment: environment, isTTY: isTTY)
    #endif
  }

  /// The POSIX arm of ``detect(environment:isTTY:)``: capabilities inferred
  /// from the environment variables the terminal emulator exports. Kept
  /// platform-independent (and `package`-visible) so both arms stay
  /// exercisable from every platform's test run.
  package static func detectPOSIXTerminal(
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

    var profile = Self(
      glyphLevel: glyphLevel,
      colorLevel: colorLevel,
      emitsStyleEscapeSequences: colorLevel != .none,
      supportsHyperlinks: supportsHyperlinks(term: term),
      supportsMouseReporting: supportsMouseReporting(term: term),
      supportsSynchronizedOutput: supportsSynchronizedOutput(term: term)
    )
    // DECSTBM/SU/SD are VT100-core: default on for any non-dumb TTY (this
    // branch), independent of the rich-feature term list. The
    // `SWIFTTUI_SCROLL_REGION=0` kill switch remains for misbehaving
    // emulators.
    profile.supportsScrollRegions = true
    return profile
  }

  /// The Windows arm of ``detect(environment:isTTY:)``.
  ///
  /// The Windows console is not at the far end of a pty: the session
  /// controller configures the host directly — it enables virtual-terminal
  /// processing and switches both codepages to UTF-8
  /// (`WindowsTerminalController`) — and every console host at the declared
  /// platform floor (Windows 10 1809, the ConPTY line) renders 24-bit VT
  /// color once VT processing is on. So the platform, not the environment,
  /// carries the defaults: Unicode glyphs and true color. The environment
  /// refines the answer only where something set it deliberately: `NO_COLOR`
  /// wins; an explicit `TERM` names a foreign terminal (WezTerm exporting
  /// its own value, an ssh session into Windows) and is honored the way the
  /// POSIX arm honors it; `WT_SESSION` marks Windows Terminal, which adds
  /// the OSC 8 hyperlinks and synchronized-output handling bare conhost
  /// lacks. Kept platform-independent (and `package`-visible) so both arms
  /// stay exercisable from every platform's test run.
  package static func detectWindowsConsole(
    environment: [String: String],
    isTTY: Bool
  ) -> Self {

    let term = environment["TERM"]?.lowercased() ?? ""
    let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
    // The controller owns the console codepages; the locale never describes
    // the Windows console, so the glyph repertoire is unconditional.
    let glyphLevel: GlyphLevel = .unicode

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
    } else if !term.isEmpty {
      // An explicit TERM describes a foreign terminal; land on the POSIX
      // arm's conservative default rung rather than the console-host floor.
      colorLevel = .ansi16
    } else {
      // The native console host: VT-enabled at the 1809 floor is 24-bit.
      colorLevel = .trueColor
    }

    let isWindowsTerminal = environment["WT_SESSION"] != nil
    let richFeatures =
      isWindowsTerminal || supportsRichTerminalFeatures(term: term)
    var profile = Self(
      glyphLevel: glyphLevel,
      colorLevel: colorLevel,
      emitsStyleEscapeSequences: colorLevel != .none,
      supportsHyperlinks: richFeatures,
      // The input pump owns mouse on the local console: conhost's
      // MOUSE_EVENT records and Windows Terminal's SGR bytes decode through
      // the same path. A foreign TERM is honored by the POSIX list.
      supportsMouseReporting: term.isEmpty ? true : richFeatures,
      supportsSynchronizedOutput: richFeatures
    )
    // conhost documents DECSTBM with SU/SD; VT100-core here as on POSIX.
    profile.supportsScrollRegions = true
    return profile
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
  ///     the detected profile disables color, such as for a non-TTY output.
  ///   - `.auto`: does not override the detected level.
  /// - `RuntimeConfiguration.glyphs`:
  ///   - `.ascii`: forces `glyphLevel = .ascii`.
  ///   - `.unicode`: does not override the detected level. Unicode is the strict superset. If
  ///     detection picked ascii because of locale, the user's `.unicode`
  ///     preference is treated as a "permit Unicode" hint rather than
  ///     a "force unicode glyphs" override).
  ///
  /// Other `RuntimeConfiguration` fields (motion, output, web, debug) are not
  /// terminal capability inputs. This method ignores them.
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

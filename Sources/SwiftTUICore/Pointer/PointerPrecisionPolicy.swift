/// Pre-resolved terminal mouse input mode.
public enum TerminalMouseInputMode: Equatable, Sendable {
  /// Do not request terminal mouse reports.
  case disabled
  /// Request cell-granularity SGR mouse reports.
  case cell
  /// Request SGR-Pixels reports using the supplied cell metrics.
  case sgrPixels(metrics: CellPixelMetrics)
}

/// How much evidence an automatic terminal mouse resolver may trust.
public enum TerminalMouseInputTrustPolicy: Equatable, Sendable {
  /// Use SGR-Pixels only after a live DECRQM probe recognizes mode 1016.
  case liveProbeOnly
  /// Use a live probe, then fall back to the documented compatibility matrix.
  case liveProbeOrDocumentedSupport
  /// Also trust explicit terminal identities known to be compatible even when
  /// their current docs do not advertise SGR-Pixels clearly.
  case liveProbeOrKnownTerminalIdentity
  /// Trust rough terminal-name heuristics. This may be wrong behind wrappers or
  /// multiplexers, so prefer narrower policies when possible.
  case roughTerminalIdentityHeuristics
  /// Use SGR-Pixels whenever cell metrics and mouse reporting are available.
  case assumeWhenCellMetricsKnown
}

/// Terminal mouse input resolution request.
public enum TerminalMouseInputResolution: Equatable, Sendable {
  /// Use a caller-provided answer and skip runtime probing and matrix lookup.
  case preResolved(TerminalMouseInputMode)
  /// Resolve the most precise mode allowed by `trustPolicy`.
  case automatic(TerminalMouseInputTrustPolicy)

  /// Default automatic resolver: live proof first, documented support second.
  public static let defaultAutomatic = Self.automatic(.liveProbeOrDocumentedSupport)
}

/// Source quality for a terminal mouse compatibility entry.
public enum TerminalMouseInputCompatibilityEvidence: Equatable, Sendable {
  /// A terminal reference or feature table advertises SGR-Pixels mode.
  case referenceDocumentation
  /// An official terminal changelog advertises SGR-Pixels mode.
  case officialChangelog
  /// Compatibility is known from implementation or ecosystem data, but is not
  /// backed by a clear current terminal reference.
  case knownCompatible
}

/// A documented terminal identity that can be used as a conservative fallback.
public struct TerminalMouseInputCompatibilityEntry: Equatable, Sendable {
  public var terminalName: String
  public var environmentMatches: [TerminalEnvironmentMatch]
  public var supportsSGRPixels: Bool
  public var supportsPrivateModeQuery: Bool?
  public var evidence: TerminalMouseInputCompatibilityEvidence
  public var sourceURL: String

  public init(
    terminalName: String,
    environmentMatches: [TerminalEnvironmentMatch],
    supportsSGRPixels: Bool,
    supportsPrivateModeQuery: Bool? = nil,
    evidence: TerminalMouseInputCompatibilityEvidence,
    sourceURL: String
  ) {
    self.terminalName = terminalName
    self.environmentMatches = environmentMatches
    self.supportsSGRPixels = supportsSGRPixels
    self.supportsPrivateModeQuery = supportsPrivateModeQuery
    self.evidence = evidence
    self.sourceURL = sourceURL
  }

  public func matches(environment: [String: String]) -> Bool {
    environmentMatches.contains { $0.matches(environment: environment) }
  }
}

/// Environment predicate used by terminal compatibility entries.
public struct TerminalEnvironmentMatch: Equatable, Sendable {
  public enum Comparison: Equatable, Sendable {
    case equals
    case hasPrefix
    case contains
  }

  public var variable: String
  public var value: String
  public var comparison: Comparison

  public init(
    variable: String,
    value: String,
    comparison: Comparison
  ) {
    self.variable = variable
    self.value = value
    self.comparison = comparison
  }

  public func matches(environment: [String: String]) -> Bool {
    guard let rawValue = environment[variable]?.lowercased() else {
      return false
    }
    let expected = value.lowercased()
    switch comparison {
    case .equals:
      return rawValue == expected
    case .hasPrefix:
      return rawValue.hasPrefix(expected)
    case .contains:
      return rawValue.contains(expected)
    }
  }
}

/// Documented terminal compatibility data for SGR-Pixels mouse reporting.
public struct TerminalMouseInputCompatibilityMatrix: Equatable, Sendable {
  public var entries: [TerminalMouseInputCompatibilityEntry]

  public init(entries: [TerminalMouseInputCompatibilityEntry]) {
    self.entries = entries
  }

  public static let documentedSupport = Self(
    entries: [
      .init(
        terminalName: "xterm",
        environmentMatches: [
          .init(variable: "XTERM_VERSION", value: "xterm", comparison: .contains)
        ],
        supportsSGRPixels: true,
        supportsPrivateModeQuery: true,
        evidence: .referenceDocumentation,
        sourceURL: "https://invisible-island.net/xterm/ctlseqs/ctlseqs.html"
      ),
      .init(
        terminalName: "xterm.js",
        environmentMatches: [
          .init(variable: "TERM_PROGRAM", value: "xterm.js", comparison: .equals),
          .init(variable: "TERM_PROGRAM", value: "xtermjs", comparison: .equals),
        ],
        supportsSGRPixels: true,
        supportsPrivateModeQuery: true,
        evidence: .referenceDocumentation,
        sourceURL: "https://xtermjs.org/docs/api/vtfeatures/"
      ),
      .init(
        terminalName: "foot",
        environmentMatches: [
          .init(variable: "TERM", value: "foot", comparison: .hasPrefix),
          .init(variable: "TERM_PROGRAM", value: "foot", comparison: .equals),
        ],
        supportsSGRPixels: true,
        evidence: .referenceDocumentation,
        sourceURL: "https://manpages.ubuntu.com/manpages/noble/man7/foot-ctlseqs.7.html"
      ),
      .init(
        terminalName: "kitty",
        environmentMatches: [
          .init(variable: "TERM", value: "xterm-kitty", comparison: .equals),
          .init(variable: "TERM_PROGRAM", value: "kitty", comparison: .equals),
          .init(variable: "KITTY_WINDOW_ID", value: "", comparison: .contains),
        ],
        supportsSGRPixels: true,
        evidence: .officialChangelog,
        sourceURL: "https://sw.kovidgoyal.net/kitty/changelog/"
      ),
      .init(
        terminalName: "WezTerm",
        environmentMatches: [
          .init(variable: "TERM_PROGRAM", value: "wezterm", comparison: .equals),
          .init(variable: "WEZTERM_EXECUTABLE", value: "wezterm", comparison: .contains),
          .init(variable: "WEZTERM_PANE", value: "", comparison: .contains),
        ],
        supportsSGRPixels: true,
        evidence: .officialChangelog,
        sourceURL: "https://wezterm.org/changelog.html"
      ),
      .init(
        terminalName: "iTerm2",
        environmentMatches: [
          .init(variable: "TERM_PROGRAM", value: "iterm.app", comparison: .equals),
          .init(variable: "LC_TERMINAL", value: "iterm2", comparison: .equals),
        ],
        supportsSGRPixels: true,
        evidence: .officialChangelog,
        sourceURL: "https://iterm2.com/downloads.html"
      ),
    ]
  )

  public static let knownCompatible = Self(
    entries: documentedSupport.entries
  )

  public func supportingSGRPixels(
    environment: [String: String],
    includingKnownCompatible: Bool = false
  ) -> TerminalMouseInputCompatibilityEntry? {
    entries.first { entry in
      guard entry.supportsSGRPixels else {
        return false
      }
      if entry.evidence == .knownCompatible, !includingKnownCompatible {
        return false
      }
      return entry.matches(environment: environment)
    }
  }
}

/// Policy for enabling sub-cell pointer coordinates from terminal protocols.
public enum PointerPrecisionPolicy: Equatable, Sendable {
  /// Always use integer terminal-cell mouse coordinates.
  case cellOnly
  /// Use sub-cell coordinates only when the host has proven support and metrics.
  case useHostSubCellWhenAvailable

  /// Enable terminal pixel coordinates when reported cell metrics are available.
  case forceTerminalPixels

  public var terminalMouseInputResolution: TerminalMouseInputResolution {
    switch self {
    case .cellOnly, .useHostSubCellWhenAvailable:
      return .preResolved(.cell)
    case .forceTerminalPixels:
      return .automatic(.assumeWhenCellMetricsKnown)
    }
  }
}

/// Runtime pointer input capabilities exposed to authored views.
public struct PointerInputCapabilities: Equatable, Sendable {
  public var precision: PointerPrecision
  public var supportsSubCellLocation: Bool { precision.isSubCell }
  public var supportsHover: Bool
  public var supportsPreciseScroll: Bool

  public init(
    precision: PointerPrecision = .cell,
    supportsHover: Bool = false,
    supportsPreciseScroll: Bool = false
  ) {
    self.precision = precision
    self.supportsHover = supportsHover
    self.supportsPreciseScroll = supportsPreciseScroll
  }

  /// Conservative default for terminal SGR 1006 and tests that do not opt in.
  public static let cellOnly = PointerInputCapabilities()
}

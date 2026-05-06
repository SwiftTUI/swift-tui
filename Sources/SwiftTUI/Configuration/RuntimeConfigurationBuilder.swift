extension RuntimeConfiguration {
  /// Returns a new fluent builder initialized with `RuntimeConfiguration.default`.
  ///
  /// Use this API in runners that construct `RuntimeConfiguration` programmatically
  /// (e.g., `SwiftUIHost`, `WebHost`) rather than through argv parsing.
  public static func builder() -> Builder {
    Builder()
  }

  /// A value-type fluent builder for `RuntimeConfiguration`.
  ///
  /// Each mutating method returns a copy, so intermediate builders can be stored
  /// without affecting later chains. Call `build()` to produce the final value.
  public struct Builder: Sendable {
    private var configuration: RuntimeConfiguration = .default

    public init() {}

    public func color(_ value: ColorMode) -> Self {
      var copy = self
      copy.configuration.color = value
      return copy
    }

    public func glyphs(_ value: GlyphMode) -> Self {
      var copy = self
      copy.configuration.glyphs = value
      return copy
    }

    public func motion(_ value: MotionMode) -> Self {
      var copy = self
      copy.configuration.motion = value
      return copy
    }

    public func output(_ value: OutputMode) -> Self {
      var copy = self
      copy.configuration.output = value
      return copy
    }

    public func verbosity(_ value: Verbosity) -> Self {
      var copy = self
      copy.configuration.verbosity = value
      return copy
    }

    public func startIn(_ value: String?) -> Self {
      var copy = self
      copy.configuration.startIn = value
      return copy
    }

    public func debug(_ value: Bool) -> Self {
      var copy = self
      copy.configuration.debug = value
      return copy
    }

    public func noProgress(_ value: Bool) -> Self {
      var copy = self
      copy.configuration.noProgress = value
      return copy
    }

    public func linear(_ value: Bool) -> Self {
      var copy = self
      copy.configuration.linear = value
      return copy
    }

    public func cursorFollowsFocus(_ value: Bool) -> Self {
      var copy = self
      copy.configuration.cursorFollowsFocus = value
      return copy
    }

    public func web(port: Int = 0, bind: String = "127.0.0.1", openBrowser: Bool = false)
      -> Self
    {
      var copy = self
      copy.configuration.web = WebConfig(port: port, bind: bind, openBrowser: openBrowser)
      return copy
    }

    public func build() -> RuntimeConfiguration { configuration }
  }
}

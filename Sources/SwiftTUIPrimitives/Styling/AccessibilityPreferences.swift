/// A user-selected palette profile, independent of color enablement.
public enum AccessibilityColorProfile: String, CaseIterable, Codable, Sendable {
  /// Preserve the host palette.
  case standard
  /// Request luminance-only differentiation.
  case monochrome
  /// Request a profile for reduced red sensitivity.
  case protanopia
  /// Request a profile for reduced green sensitivity.
  case deuteranopia
  /// Request a profile for reduced blue sensitivity.
  case tritanopia
}

/// Optional user choices. `nil` inherits the next source in the host policy;
/// an explicit `false` or `.standard` remains a choice and overrides detection.
public struct AccessibilityPreferences: Equatable, Codable, Sendable {
  /// Avoid nonessential animation when enabled.
  public var reduceMotion: Bool?
  /// Explicit contrast preference, or nil to inherit.
  public var contrast: ColorSchemeContrast?
  /// Distinguish information using more than hue.
  public var differentiateWithoutColor: Bool?
  /// Prefer opaque surfaces.
  public var reduceTransparency: Bool?
  /// Requested palette profile, or nil to inherit.
  public var colorProfile: AccessibilityColorProfile?

  /// Creates overrides; unspecified fields inherit from the host.
  public init(
    reduceMotion: Bool? = nil,
    contrast: ColorSchemeContrast? = nil,
    differentiateWithoutColor: Bool? = nil,
    reduceTransparency: Bool? = nil,
    colorProfile: AccessibilityColorProfile? = nil
  ) {
    self.reduceMotion = reduceMotion
    self.contrast = contrast
    self.differentiateWithoutColor = differentiateWithoutColor
    self.reduceTransparency = reduceTransparency
    self.colorProfile = colorProfile
  }

  /// Fill unspecified choices from a lower-priority source.
  public func inheriting(_ fallback: Self) -> Self {
    .init(
      reduceMotion: reduceMotion ?? fallback.reduceMotion,
      contrast: contrast ?? fallback.contrast,
      differentiateWithoutColor: differentiateWithoutColor ?? fallback.differentiateWithoutColor,
      reduceTransparency: reduceTransparency ?? fallback.reduceTransparency,
      colorProfile: colorProfile ?? fallback.colorProfile)
  }
}

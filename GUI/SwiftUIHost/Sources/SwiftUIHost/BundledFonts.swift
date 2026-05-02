import CoreText
import Foundation

/// Bundled terminal fonts shipped with `SwiftUIHost`.
///
/// The TTF files in `Resources/` are registered with Core Text at first access
/// using process-scoped registration, so callers do not need to add the fonts
/// to `Info.plist` (`UIAppFonts` / `ATSApplicationFontsPath`).
enum BundledFonts {
  /// PostScript name of the regular face. Use this with `NSFont(name:size:)`
  /// or `UIFont(name:size:)` after calling `registerIfNeeded()`.
  static let regularPostScriptName = "AnonymiceProNFP"

  /// Family name as advertised by the TTFs' `name` table. Useful when the
  /// caller wants to set `SwiftUIHostTerminalStyle.fontFamily` explicitly.
  static let familyName = "AnonymicePro Nerd Font Propo"

  /// Idempotent registration — safe to call from any thread, runs at most once.
  static func registerIfNeeded() {
    _ = registration
  }

  /// PostScript name for a specific emphasis combination. Embedded fonts can
  /// be flaky with `NSFontManager.convert(toHaveTrait:)` / symbolic-trait
  /// derivation, so we resolve each face directly.
  static func postScriptName(forBold bold: Bool, italic: Bool) -> String {
    switch (bold, italic) {
    case (true, true):
      "AnonymiceProNFP-BoldItalic"
    case (true, false):
      "AnonymiceProNFP-Bold"
    case (false, true):
      "AnonymiceProNFP-Italic"
    case (false, false):
      regularPostScriptName
    }
  }

  /// Lazy, dispatch-once-equivalent registration of every bundled `.ttf`.
  /// Errors (including "already registered") are intentionally ignored.
  private static let registration: Void = {
    let baseNames = [
      "AnonymiceProNerdFontPropo-Regular",
      "AnonymiceProNerdFontPropo-Bold",
      "AnonymiceProNerdFontPropo-Italic",
      "AnonymiceProNerdFontPropo-BoldItalic",
    ]

    for name in baseNames {
      guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
        continue
      }
      var error: Unmanaged<CFError>?
      _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
      error?.release()
    }
  }()
}

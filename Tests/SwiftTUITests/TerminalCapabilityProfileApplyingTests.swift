import Testing

@testable import SwiftTUIRuntime

@Suite
struct TerminalCapabilityProfileApplyingTests {
  @Test("color=.never forces colorLevel=.none and emitsStyleEscapeSequences=false")
  func colorNeverDisablesEverything() {
    let profile = TerminalCapabilityProfile.trueColor
    let result = profile.applying(RuntimeConfiguration(color: .never))
    #expect(result.colorLevel == .none)
    #expect(result.emitsStyleEscapeSequences == false)
  }

  @Test("color=.always bumps .none up to .ansi16")
  func colorAlwaysBumpsFromNone() {
    let profile = TerminalCapabilityProfile.previewASCII  // colorLevel = .none
    let result = profile.applying(RuntimeConfiguration(color: .always))
    #expect(result.colorLevel == .ansi16)
    #expect(result.emitsStyleEscapeSequences == true)
  }

  @Test("color=.always preserves detected level when already non-none")
  func colorAlwaysPreservesHigherLevel() {
    let profile = TerminalCapabilityProfile.trueColor
    let result = profile.applying(RuntimeConfiguration(color: .always))
    #expect(result.colorLevel == .trueColor)
    #expect(result.emitsStyleEscapeSequences == true)
  }

  @Test("color=.auto preserves the detected profile")
  func colorAutoIsNoop() {
    let profile = TerminalCapabilityProfile.ansi256
    let result = profile.applying(RuntimeConfiguration(color: .auto))
    #expect(result == profile)
  }

  @Test("glyphs=.ascii forces glyphLevel=.ascii")
  func glyphsAsciiForces() {
    let profile = TerminalCapabilityProfile.trueColor  // glyphLevel = .unicode
    let result = profile.applying(RuntimeConfiguration(glyphs: .ascii))
    #expect(result.glyphLevel == .ascii)
  }

  @Test("glyphs=.unicode does not override ascii detection")
  func glyphsUnicodeIsNoop() {
    let profile = TerminalCapabilityProfile.previewASCII  // glyphLevel = .ascii
    let result = profile.applying(RuntimeConfiguration(glyphs: .unicode))
    #expect(result.glyphLevel == .ascii)
  }

  @Test("color=.never combined with glyphs=.ascii applies both")
  func combinedOverrides() {
    let profile = TerminalCapabilityProfile.trueColor
    let result = profile.applying(RuntimeConfiguration(color: .never, glyphs: .ascii))
    #expect(result.colorLevel == .none)
    #expect(result.emitsStyleEscapeSequences == false)
    #expect(result.glyphLevel == .ascii)
  }

  @Test("Default RuntimeConfiguration leaves the profile unchanged")
  func defaultConfigurationIsNoop() {
    let profile = TerminalCapabilityProfile.ansi256
    let result = profile.applying(.default)
    #expect(result == profile)
  }
}

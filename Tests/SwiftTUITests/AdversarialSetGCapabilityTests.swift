@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

private let setGTerms: [String?] = [
  nil, "", "xterm", "xterm-256color", "xterm-direct", "xterm-direct256", "screen-256color",
  "screen.xterm-256color", "tmux-256color", "wezterm", "xterm-kitty", "xterm-ghostty",
  "alacritty", "foot-direct", "linux", "dumb", "vt100", "st-256color", "rxvt-unicode-256color",
  "konsole-direct", "putty", "xterm-color",
]
private let setGColorTerms: [String?] = [nil, "", "truecolor", "24bit", "yes"]
private let setGPrograms: [String?] = [
  nil, "", "WezTerm", "ghostty", "iTerm.app", "vscode", "Apple_Terminal", "tmux", "mintty",
]
private let setGVTE: [String?] = [nil, "4999", "5000", "7600", "x"]
private let setGLocales: [String?] = [
  nil, "", "C", "POSIX", "en_US.UTF-8", "C.utf8", "de_DE.ISO8859-1",
]

/// An environment over the documented variable vocabulary.
private func setGEnvironment(_ n: [Int], windowsTerminal: Bool? = nil) -> [String: String] {
  var environment: [String: String] = [:]
  func put(_ key: String, _ value: String?) { if let value { environment[key] = value } }
  put("TERM", setGTerms[n[0] % setGTerms.count])
  put("COLORTERM", setGColorTerms[n[1] % setGColorTerms.count])
  put("TERM_PROGRAM", setGPrograms[n[2] % setGPrograms.count])
  put("VTE_VERSION", setGVTE[n[3] % setGVTE.count])
  let wt = windowsTerminal ?? (n[4] % 2 == 0)
  if wt { environment["WT_SESSION"] = "8c2f" }
  put("NO_COLOR", [nil, "", "1"][n[5] % 3])
  put("LC_ALL", setGLocales[n[6] % setGLocales.count])
  put("LC_CTYPE", setGLocales[n[7] % setGLocales.count])
  put("LANG", setGLocales[n[8] % setGLocales.count])
  return environment
}

private func setGBoth(_ environment: [String: String], isTTY: Bool) -> (
  posix: TerminalCapabilityProfile, windows: TerminalCapabilityProfile
) {
  (
    TerminalCapabilityProfile.detectPOSIXTerminal(environment: environment, isTTY: isTTY),
    TerminalCapabilityProfile.detectWindowsConsole(environment: environment, isTTY: isTTY)
  )
}

@MainActor
@Suite("Campaign F5 pass 2 capability properties", .serialized)
struct AdversarialSetGCapabilityTests {
  @Test(arguments: Array(131...136))
  func capability(id: Int) {
    switch id {
    case 131: caseInsensitive(id)
    case 132: localePrecedence(id)
    case 133: colourDisabled(id)
    case 134: directColourNames(id)
    case 135: foreignTermAgreement(id)
    default: programOutranksWindowsTerminal(id)
    }
  }

  private func caseInsensitive(_ id: Int) {
    setGProperty(id, setGDraws(11)) { n in
      let environment = setGEnvironment(n)
      var recased = environment
      for key in ["TERM", "COLORTERM", "TERM_PROGRAM", "LC_ALL", "LC_CTYPE", "LANG"] {
        guard let value = environment[key] else { continue }
        recased[key] =
          n[9] % 2 == 0
          ? value.uppercased()
          : String(
            value.enumerated().map {
              $0.offset % 2 == 0 ? Character($0.element.uppercased()) : $0.element
            })
      }
      let isTTY = n[10] % 4 != 0
      let original = setGBoth(environment, isTTY: isTTY)
      let changed = setGBoth(recased, isTTY: isTTY)
      if original.posix != changed.posix { return "POSIX \(environment) vs \(recased)" }
      return original.windows == changed.windows ? nil : "Windows \(environment) vs \(recased)"
    }
  }

  private func localePrecedence(_ id: Int) {
    setGProperty(id, setGDraws(11)) { n in
      let environment = setGEnvironment(n)
      let locale =
        [environment["LC_ALL"], environment["LC_CTYPE"], environment["LANG"]]
        .compactMap { $0 }.first { !$0.isEmpty }?.lowercased() ?? ""
      let expected: TerminalCapabilityProfile.GlyphLevel =
        locale.contains("utf-8") || locale.contains("utf8") ? .unicode : .ascii
      let profiles = setGBoth(environment, isTTY: n[10] % 2 == 0)
      if profiles.posix.glyphLevel != expected {
        return "POSIX glyphs \(profiles.posix.glyphLevel) for \(environment), expected \(expected)"
      }
      return profiles.windows.glyphLevel == .unicode
        ? nil : "Windows glyphs \(profiles.windows.glyphLevel)"
    }
  }

  private func colourDisabled(_ id: Int) {
    setGProperty(id, setGDraws(11)) { n in
      let environment = setGEnvironment(n)
      let isTTY = n[10] % 3 != 0
      let term = environment["TERM"]?.lowercased() ?? ""
      let noColor = (environment["NO_COLOR"] ?? "").isEmpty == false
      let disabled = !isTTY || term == "dumb" || noColor
      let profiles = setGBoth(environment, isTTY: isTTY)
      for profile in [profiles.posix, profiles.windows] {
        let off = profile.colorLevel == .none && !profile.emitsStyleEscapeSequences
        if off != disabled { return "colour off \(off) for \(environment) TTY \(isTTY)" }
      }
      if environment["NO_COLOR"] == "" {
        var without = environment
        without["NO_COLOR"] = nil
        let reference = setGBoth(without, isTTY: isTTY)
        if reference.posix != profiles.posix || reference.windows != profiles.windows {
          return "empty NO_COLOR changed the profile for \(environment)"
        }
      }
      return nil
    }
  }

  private func directColourNames(_ id: Int) {
    setGProperty(id, setGDraws(3)) { n in
      let families = ["xterm", "foot", "konsole", "mlterm", "st", "wezterm"]
      let valid = ["-direct", "-direct2", "-direct16", "-direct256", "-direct0"]
      let invalid = ["-directx", "-direct-1", "-direct256color", "-indirect"]
      let isValid = n[1] % 2 == 0
      var term =
        isValid
        ? families[n[0] % families.count] + valid[n[1] / 2 % valid.count]
        : families[n[0] % families.count] + invalid[n[1] / 2 % invalid.count]
      if n[2] % 3 == 0 { term = term.uppercased() }
      if !isValid, n[2] % 3 == 1 { term = "direct" }
      let profiles = setGBoth(["TERM": term], isTTY: true)
      for profile in [profiles.posix, profiles.windows]
      where (profile.colorLevel == .trueColor) != isValid {
        return "TERM \(term): colour \(profile.colorLevel)"
      }
      return nil
    }
  }

  private func foreignTermAgreement(_ id: Int) {
    setGProperty(id, setGDraws(11)) { n in
      var environment = setGEnvironment(n, windowsTerminal: false)
      let term = environment["TERM"] ?? ""
      guard !term.isEmpty, term.lowercased() != "dumb" else { return nil }
      environment["WT_SESSION"] = nil
      let profiles = setGBoth(environment, isTTY: true)
      let posix = profiles.posix
      let windows = profiles.windows
      let same =
        posix.colorLevel == windows.colorLevel
        && posix.emitsStyleEscapeSequences == windows.emitsStyleEscapeSequences
        && posix.supportsHyperlinks == windows.supportsHyperlinks
        && posix.supportsMouseReporting == windows.supportsMouseReporting
        && posix.supportsSynchronizedOutput == windows.supportsSynchronizedOutput
      return same ? nil : "POSIX \(posix) vs Windows \(windows) for \(environment)"
    }
  }

  private func programOutranksWindowsTerminal(_ id: Int) {
    setGProperty(id, setGDraws(3)) { n in
      let terms = ["", "xterm", "xterm-256color", "xterm-direct"]
      let programs = ["mintty", "Hyper", "Tabby", "Apple_Terminal"]
      var environment = ["TERM_PROGRAM": programs[n[1] % programs.count], "WT_SESSION": "8c2f"]
      let term = terms[n[0] % terms.count]
      if !term.isEmpty { environment["TERM"] = term }
      if n[2] % 2 == 0 { environment["VTE_VERSION"] = "7600" }
      var inherited = environment
      inherited["WT_SESSION"] = nil
      let marked = TerminalCapabilityProfile.detectWindowsConsole(
        environment: environment, isTTY: true)
      let unmarked = TerminalCapabilityProfile.detectWindowsConsole(
        environment: inherited, isTTY: true)
      return marked.supportsHyperlinks == unmarked.supportsHyperlinks
        && marked.supportsSynchronizedOutput == unmarked.supportsSynchronizedOutput
        ? nil
        : "WT_SESSION under TERM_PROGRAM \(environment["TERM_PROGRAM"] ?? "") and TERM '\(term)': hyperlinks \(marked.supportsHyperlinks), sync \(marked.supportsSynchronizedOutput); without it \(unmarked.supportsHyperlinks), \(unmarked.supportsSynchronizedOutput)"
    }
  }

  // STUI-1313 neighbours: WT_SESSION still marks Windows Terminal when nothing
  // names another emulator (unset or empty TERM_PROGRAM, as setC271 pins on
  // POSIX), a foreign TERM still gets neither upgrade, and an emulator named
  // by TERM_PROGRAM keeps only its own capabilities (vscode: hyperlinks on a
  // generic xterm, as on the POSIX arm).
  @Test func windowsTerminalMarkerNeighbours() {
    func windows(_ environment: [String: String]) -> TerminalCapabilityProfile {
      TerminalCapabilityProfile.detectWindowsConsole(environment: environment, isTTY: true)
    }
    for environment in [
      ["WT_SESSION": "8c2f"], ["WT_SESSION": "8c2f", "TERM_PROGRAM": ""],
      ["WT_SESSION": "8c2f", "TERM": "XTERM"],
      ["WT_SESSION": "8c2f", "TERM": "xterm-256color", "TERM_PROGRAM": ""],
    ] {
      let profile = windows(environment)
      #expect(profile.supportsHyperlinks, "\(environment)")
      #expect(profile.supportsSynchronizedOutput, "\(environment)")
    }
    let foreign = windows(["WT_SESSION": "8c2f", "TERM": "screen-256color"])
    #expect(!foreign.supportsHyperlinks)
    #expect(!foreign.supportsSynchronizedOutput)
    let vscode = ["WT_SESSION": "8c2f", "TERM": "xterm-256color", "TERM_PROGRAM": "vscode"]
    let vscodeWindows = windows(vscode)
    let vscodePOSIX = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: vscode, isTTY: true)
    #expect(vscodeWindows.supportsHyperlinks)
    #expect(!vscodeWindows.supportsSynchronizedOutput, "WT_SESSION outranked TERM_PROGRAM")
    #expect(vscodeWindows.supportsHyperlinks == vscodePOSIX.supportsHyperlinks)
    #expect(vscodeWindows.supportsSynchronizedOutput == vscodePOSIX.supportsSynchronizedOutput)
  }
}

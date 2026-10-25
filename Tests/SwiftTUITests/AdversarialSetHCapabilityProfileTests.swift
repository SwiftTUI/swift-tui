// Adversarial set H, pass 1 (F6 platform edges): capability detection from
// the environment a Linux terminal exports (setH020, setH037–setH050). The
// locale rules follow POSIX XBD 8.2; the terminal families follow the
// emulators' own documentation and terminfo. Pure functions; no descriptors.
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite("Adversarial set H: capability profile")
struct AdversarialSetHCapabilityProfileTests {
  private func profile(_ environment: [String: String], tty: Bool = true)
    -> TerminalCapabilityProfile
  {
    TerminalCapabilityProfile.detectPOSIXTerminal(environment: environment, isTTY: tty)
  }

  // terminfo's *-direct entries declare the RGB capability (24-bit colour);
  // the ladder only knows COLORTERM and the 256color suffix.
  @Test func setH020DirectColorTerminalsAreTrueColor() {
    for term in ["xterm-direct", "foot-direct", "tmux-direct"] {
      let detected = profile(["TERM": term, "LANG": "C.UTF-8"])
      setHKnown(
        "STUI-1224: setH020: TERM=xterm-direct/foot-direct/tmux-direct detects ansi16; the colour ladder knows only COLORTERM and the 256color suffix (TerminalCapabilityProfile.swift:143-152); contract: terminfo(5) *-direct entries declare RGB 24-bit colour; adjacent: none"
      ) {
        #expect(detected.colorLevel == .trueColor, "\(term)")
      }
    }
  }

  @Test func setH037LocaleCUTF8IsUnicode() {
    #expect(profile(["LANG": "C.UTF-8", "TERM": "xterm"]).glyphLevel == .unicode)
  }

  @Test func setH038LocaleUtf8SpellingsAreUnicode() {
    #expect(profile(["LANG": "en_US.utf8", "TERM": "xterm"]).glyphLevel == .unicode)
    #expect(profile(["LANG": "en_US.UTF8", "TERM": "xterm"]).glyphLevel == .unicode)
  }

  @Test func setH039LCALLOverridesLANG() {
    #expect(profile(["LC_ALL": "C", "LANG": "en_US.UTF-8", "TERM": "xterm"]).glyphLevel == .ascii)
  }

  @Test func setH040EmptyLCALLDefersToLCCTYPE() {
    #expect(profile(["LC_ALL": "", "LC_CTYPE": "C.utf8", "TERM": "xterm"]).glyphLevel == .unicode)
    #expect(
      profile(["LC_ALL": "", "LC_CTYPE": "", "LANG": "C.UTF-8", "TERM": "xterm"]).glyphLevel
        == .unicode)
  }

  @Test func setH041POSIXLocaleAndDumbTerminal() {
    #expect(profile(["LANG": "POSIX", "TERM": "xterm"]).glyphLevel == .ascii)
    #expect(profile(["TERM": "xterm"]).glyphLevel == .ascii)
    let dumb = profile(["TERM": "dumb", "LANG": "C.UTF-8", "COLORTERM": "truecolor"])
    #expect(dumb.glyphLevel == .unicode)
    #expect(dumb.colorLevel == .none)
    #expect(!dumb.emitsStyleEscapeSequences)
  }

  @Test func setH042NonUTF8CodesetsAreASCII() {
    #expect(profile(["LANG": "en_US.ISO8859-1", "TERM": "xterm"]).glyphLevel == .ascii)
    #expect(profile(["LANG": "zh_CN.GB18030", "TERM": "xterm"]).glyphLevel == .ascii)
  }

  @Test func setH043LinuxConsoleProfile() {
    let console = profile(["TERM": "linux", "LANG": "C.UTF-8"])
    #expect(console.colorLevel == .ansi16)
    #expect(!console.supportsMouseReporting)
    #expect(!console.supportsHyperlinks)
    #expect(!console.supportsSynchronizedOutput)
    #expect(console.supportsScrollRegions)
  }

  @Test func setH044RxvtUnicodeProfile() {
    let rxvt = profile(["TERM": "rxvt-unicode-256color", "LANG": "C.UTF-8"])
    #expect(rxvt.colorLevel == .ansi256)
    #expect(!rxvt.supportsMouseReporting)
    #expect(!rxvt.supportsHyperlinks)
  }

  // GNOME Terminal exports VTE_VERSION; VTE renders OSC 8 since 0.50.
  @Test func setH045VTEHyperlinksUnderGenericXterm() {
    let gnome = profile(["TERM": "xterm-256color", "VTE_VERSION": "7600", "LANG": "C.UTF-8"])
    setHKnown(
      "STUI-1225: setH045: GNOME Terminal (VTE_VERSION=7600, TERM=xterm-256color) gets no OSC 8 hyperlinks; identifiedTerminal refines a generic xterm only through TERM_PROGRAM wezterm/ghostty/iTerm.app (TerminalCapabilityProfile.swift:256-275); contract: VTE >= 0.50 renders OSC 8; adjacent: none"
    ) {
      #expect(gnome.supportsHyperlinks)
    }
  }

  @Test func setH046VSCodeAndWindowsTerminalHyperlinks() {
    let vscode = profile(["TERM": "xterm-256color", "TERM_PROGRAM": "vscode", "LANG": "C.UTF-8"])
    setHKnown(
      "STUI-1225: setH046: VS Code (TERM_PROGRAM=vscode) gets no OSC 8 hyperlinks; same identifiedTerminal mechanism as setH045 (TerminalCapabilityProfile.swift:256-275); contract: xterm.js renders OSC 8; adjacent: none"
    ) {
      #expect(vscode.supportsHyperlinks)
    }
    let wsl = profile([
      "TERM": "xterm-256color", "WT_SESSION": "4f8a6e7a-0000-4000-8000-000000000000",
      "LANG": "C.UTF-8",
    ])
    setHKnown(
      "STUI-1225: setH046: Windows Terminal under WSL (WT_SESSION, TERM=xterm-256color) gets no OSC 8 hyperlinks on the POSIX arm; same identifiedTerminal mechanism as setH045 (TerminalCapabilityProfile.swift:256-275); contract: Windows Terminal >= 1.4 renders OSC 8; adjacent: none"
    ) {
      #expect(wsl.supportsHyperlinks)
    }
  }

  @Test func setH047ScreenProfile() {
    let screen = profile(["TERM": "screen-256color", "LANG": "C.UTF-8"])
    #expect(screen.supportsMouseReporting)
    #expect(!screen.supportsHyperlinks)
    #expect(screen.colorLevel == .ansi256)
  }

  @Test func setH048TmuxProfile() {
    let tmux = profile(["TERM": "tmux-256color", "LANG": "C.UTF-8"])
    #expect(tmux.supportsHyperlinks)
    #expect(tmux.supportsSynchronizedOutput)
    #expect(tmux.supportsMouseReporting)
  }

  @Test func setH049KittyAndFootFamilies() {
    for term in ["xterm-kitty", "foot-extra"] {
      let detected = profile(["TERM": term, "LANG": "C.UTF-8"])
      #expect(detected.supportsMouseReporting, "\(term)")
      #expect(detected.supportsHyperlinks, "\(term)")
      #expect(detected.supportsSynchronizedOutput, "\(term)")
    }
  }

  @Test func setH050NoColorAndColorTerm() {
    let kept = profile(["TERM": "xterm", "NO_COLOR": "", "COLORTERM": "24bit"])
    #expect(kept.colorLevel == .trueColor)
    let disabled = profile(["TERM": "xterm", "NO_COLOR": "0", "COLORTERM": "truecolor"])
    #expect(disabled.colorLevel == .none)
  }
}

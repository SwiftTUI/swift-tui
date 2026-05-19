import CoreGraphics
import Foundation
import SwiftTUIRuntime

// Platform adapters for the native terminal surface.
//
// The native host renders identically on macOS (AppKit) and iOS (UIKit); this
// file holds the per-platform primitives behind a shared vocabulary:
// `NativePlatformFont` / `NativePlatformColor` / `NativePlatformImage` alias
// the platform types, and the extensions adapt a `SwiftUIHostTerminalStyle` /
// `SwiftTUIRuntime.Color` / `ImageSource` into them. `NativeInputMapper`
// translates a platform key event into a framework `InputEvent`.
//
// Split out of `NativeTerminalSurfaceView.swift`. The typealiases and the
// adapter entry points (`terminalFont`, `measureTerminalCharacter`,
// `terminalColor`, `terminalImage`, `NativeInputMapper`) are widened from
// `private`/`fileprivate` to file-internal so `NativeTerminalMetrics`,
// `NativeRasterSurfaceRenderer`, and the view classes — each now in their own
// file — can reach them. A `typealias` is only an alias, so widening it leaks
// no abstraction.

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  typealias NativePlatformFont = NSFont
  typealias NativePlatformColor = NSColor
  typealias NativePlatformImage = NSImage

  extension NativePlatformFont {
    static func terminalFont(
      style: SwiftUIHostTerminalStyle,
      emphasis: SwiftTUIRuntime.TextStyle.TextEmphasis
    ) -> NativePlatformFont {
      BundledFonts.registerIfNeeded()
      let size = CGFloat(style.fontSize ?? 14)

      if let fontFamily = style.fontFamily,
        let font = NSFont(name: fontFamily, size: size)
      {
        return font.withTerminalTraits(emphasis)
      }

      let postScriptName = BundledFonts.postScriptName(
        forBold: emphasis.contains(.bold),
        italic: emphasis.contains(.italic)
      )
      if let bundled = NSFont(name: postScriptName, size: size) {
        return bundled
      }

      let fallback = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
      return fallback.withTerminalTraits(emphasis)
    }

    static func measureTerminalCharacter(
      _ font: NativePlatformFont
    ) -> CGSize {
      ("W" as NSString).size(withAttributes: [.font: font])
    }

    fileprivate func withTerminalTraits(
      _ traits: SwiftTUIRuntime.TextStyle.TextEmphasis
    ) -> NativePlatformFont {
      var result = self
      if traits.contains(.bold) {
        result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask)
      }
      if traits.contains(.italic) {
        result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask)
      }
      return result
    }
  }

  extension NativePlatformColor {
    static func terminalColor(
      _ color: SwiftTUIRuntime.Color,
      alphaMultiplier: Double = 1
    ) -> NativePlatformColor {
      let converted = color.converted(to: .sRGB)
      return NativePlatformColor(
        calibratedRed: CGFloat(converted.red),
        green: CGFloat(converted.green),
        blue: CGFloat(converted.blue),
        alpha: CGFloat(converted.alpha * alphaMultiplier)
      )
    }
  }

  extension NativePlatformImage {
    static func terminalImage(
      from source: ImageSource
    ) -> NativePlatformImage? {
      switch source {
      case .path(let path):
        return NSImage(contentsOfFile: path)
      case .fileURL(let value):
        guard let url = URL(string: value) else {
          return nil
        }
        return NSImage(contentsOf: url)
      case .data(let bytes):
        return NSImage(data: Data(bytes))
      }
    }

    func drawTerminalImage(
      in rect: CGRect
    ) {
      draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: nil
      )
    }
  }

  enum NativeInputMapper {
    static func inputEvent(
      for event: NSEvent
    ) -> InputEvent? {
      let modifiers = modifiers(for: event)
      switch event.keyCode {
      case 36:
        return .key(.init(.return, modifiers: modifiers))
      case 48:
        return .key(.init(.tab, modifiers: modifiers))
      case 51:
        return .key(.init(.backspace, modifiers: modifiers))
      case 53:
        return .key(.init(.escape, modifiers: modifiers))
      case 115:
        return .key(.init(.home, modifiers: modifiers))
      case 119:
        return .key(.init(.end, modifiers: modifiers))
      case 123:
        return .key(.init(.arrowLeft, modifiers: modifiers))
      case 124:
        return .key(.init(.arrowRight, modifiers: modifiers))
      case 125:
        return .key(.init(.arrowDown, modifiers: modifiers))
      case 126:
        return .key(.init(.arrowUp, modifiers: modifiers))
      default:
        break
      }

      guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
        let character = characters.first
      else {
        return nil
      }

      if character == " " {
        return .key(.init(.space, modifiers: modifiers))
      }
      return .key(.init(.character(character), modifiers: modifiers))
    }

    static func modifiers(
      for event: NSEvent
    ) -> EventModifiers {
      var result: EventModifiers = []
      if event.modifierFlags.contains(.shift) {
        result.insert(.shift)
      }
      if event.modifierFlags.contains(.option) {
        result.insert(.alt)
      }
      if event.modifierFlags.contains(.control) {
        result.insert(.ctrl)
      }
      return result
    }
  }
#elseif canImport(UIKit)
  import UIKit

  typealias NativePlatformFont = UIFont
  typealias NativePlatformColor = UIColor
  typealias NativePlatformImage = UIImage

  extension NativePlatformFont {
    static func terminalFont(
      style: SwiftUIHostTerminalStyle,
      emphasis: SwiftTUIRuntime.TextStyle.TextEmphasis
    ) -> NativePlatformFont {
      BundledFonts.registerIfNeeded()
      let size = CGFloat(style.fontSize ?? 14)

      if let fontFamily = style.fontFamily,
        let font = UIFont(name: fontFamily, size: size)
      {
        return font.withTerminalTraits(emphasis)
      }

      let postScriptName = BundledFonts.postScriptName(
        forBold: emphasis.contains(.bold),
        italic: emphasis.contains(.italic)
      )
      if let bundled = UIFont(name: postScriptName, size: size) {
        return bundled
      }

      let fallback = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
      return fallback.withTerminalTraits(emphasis)
    }

    static func measureTerminalCharacter(
      _ font: NativePlatformFont
    ) -> CGSize {
      ("W" as NSString).size(withAttributes: [.font: font])
    }

    fileprivate func withTerminalTraits(
      _ traits: SwiftTUIRuntime.TextStyle.TextEmphasis
    ) -> NativePlatformFont {
      var symbolicTraits = fontDescriptor.symbolicTraits
      if traits.contains(.bold) {
        symbolicTraits.insert(.traitBold)
      }
      if traits.contains(.italic) {
        symbolicTraits.insert(.traitItalic)
      }
      guard let descriptor = fontDescriptor.withSymbolicTraits(symbolicTraits) else {
        return self
      }
      return UIFont(descriptor: descriptor, size: pointSize)
    }
  }

  extension NativePlatformColor {
    static func terminalColor(
      _ color: SwiftTUIRuntime.Color,
      alphaMultiplier: Double = 1
    ) -> NativePlatformColor {
      let converted = color.converted(to: .sRGB)
      return NativePlatformColor(
        red: CGFloat(converted.red),
        green: CGFloat(converted.green),
        blue: CGFloat(converted.blue),
        alpha: CGFloat(converted.alpha * alphaMultiplier)
      )
    }
  }

  extension NativePlatformImage {
    static func terminalImage(
      from source: ImageSource
    ) -> NativePlatformImage? {
      switch source {
      case .path(let path):
        return UIImage(contentsOfFile: path)
      case .fileURL(let value):
        guard let url = URL(string: value) else {
          return nil
        }
        return UIImage(contentsOfFile: url.path)
      case .data(let bytes):
        return UIImage(data: Data(bytes))
      }
    }

    func drawTerminalImage(
      in rect: CGRect
    ) {
      draw(in: rect)
    }
  }

  enum NativeInputMapper {
    static func inputEvent(
      for press: UIPress
    ) -> InputEvent? {
      guard let key = press.key else {
        return nil
      }
      let modifiers = modifiers(for: key)

      switch key.keyCode {
      case .keyboardReturnOrEnter:
        return .key(.init(.return, modifiers: modifiers))
      case .keyboardTab:
        return .key(.init(.tab, modifiers: modifiers))
      case .keyboardDeleteOrBackspace:
        return .key(.init(.backspace, modifiers: modifiers))
      case .keyboardEscape:
        return .key(.init(.escape, modifiers: modifiers))
      case .keyboardHome:
        return .key(.init(.home, modifiers: modifiers))
      case .keyboardEnd:
        return .key(.init(.end, modifiers: modifiers))
      case .keyboardLeftArrow:
        return .key(.init(.arrowLeft, modifiers: modifiers))
      case .keyboardRightArrow:
        return .key(.init(.arrowRight, modifiers: modifiers))
      case .keyboardDownArrow:
        return .key(.init(.arrowDown, modifiers: modifiers))
      case .keyboardUpArrow:
        return .key(.init(.arrowUp, modifiers: modifiers))
      default:
        break
      }

      guard key.charactersIgnoringModifiers.count == 1,
        let character = key.charactersIgnoringModifiers.first
      else {
        return nil
      }

      if character == " " {
        return .key(.init(.space, modifiers: modifiers))
      }
      return .key(.init(.character(character), modifiers: modifiers))
    }

    private static func modifiers(
      for key: UIKey
    ) -> EventModifiers {
      var result: EventModifiers = []
      if key.modifierFlags.contains(.shift) {
        result.insert(.shift)
      }
      if key.modifierFlags.contains(.alternate) {
        result.insert(.alt)
      }
      if key.modifierFlags.contains(.control) {
        result.insert(.ctrl)
      }
      return result
    }
  }
#endif

import CoreGraphics
import Foundation
import TerminalUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  final class NativeTerminalSurfaceView: NSView {
    var surface: RasterSurface? {
      didSet { needsDisplay = true }
    }

    var style: SwiftUITUITerminalStyle = .default {
      didSet {
        updateMetrics()
        needsDisplay = true
      }
    }

    var focusPresentation: FocusPresentation = .none
    var allowsTextInput = false
    var onResize: ((Size, Size?) -> Void)?
    var onInputEvent: ((InputEvent) -> Void)?

    private var metrics = NativeTerminalMetrics(style: .default)
    private var lastPublishedGrid: Size?
    private var lastPublishedCellPixelSize: Size?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.isOpaque = true
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      wantsLayer = true
      layer?.isOpaque = true
    }

    override func layout() {
      super.layout()
      publishGridIfNeeded()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      publishGridIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)
      guard let context = NSGraphicsContext.current?.cgContext else {
        return
      }
      NativeRasterSurfaceRenderer.draw(
        surface: surface,
        style: style,
        metrics: metrics,
        bounds: bounds,
        context: context
      )
    }

    override func keyDown(with event: NSEvent) {
      if let inputEvent = NativeInputMapper.inputEvent(for: event) {
        onInputEvent?(inputEvent)
      } else {
        super.keyDown(with: event)
      }
    }

    override func mouseDown(with event: NSEvent) {
      window?.makeFirstResponder(self)
      onInputEvent?(
        .mouse(
          .init(
            kind: .down(.primary),
            location: cellPoint(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    override func mouseDragged(with event: NSEvent) {
      onInputEvent?(
        .mouse(
          .init(
            kind: .dragged(.primary),
            location: cellPoint(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    override func mouseUp(with event: NSEvent) {
      onInputEvent?(
        .mouse(
          .init(
            kind: .up(.primary),
            location: cellPoint(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    override func scrollWheel(with event: NSEvent) {
      let deltaX = Int(event.scrollingDeltaX.rounded())
      let deltaY = Int((-event.scrollingDeltaY).rounded())
      guard deltaX != 0 || deltaY != 0 else {
        return
      }

      onInputEvent?(
        .mouse(
          .init(
            kind: .scrolled(deltaX: deltaX, deltaY: deltaY),
            location: cellPoint(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    private func cellPoint(
      for windowPoint: NSPoint
    ) -> Point {
      let local = convert(windowPoint, from: nil)
      return metrics.cellPoint(for: CGPoint(x: local.x, y: local.y), in: bounds)
    }

    private func updateMetrics() {
      metrics = NativeTerminalMetrics(style: style)
      publishGridIfNeeded()
    }

    private func publishGridIfNeeded() {
      guard bounds.width > 0, bounds.height > 0 else {
        return
      }

      let grid = metrics.gridSize(for: bounds.size)
      let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
      let cellPixelSize = metrics.cellPixelSize(scale: scale)
      guard grid != lastPublishedGrid || cellPixelSize != lastPublishedCellPixelSize else {
        return
      }

      lastPublishedGrid = grid
      lastPublishedCellPixelSize = cellPixelSize
      onResize?(grid, cellPixelSize)
    }
  }
#elseif canImport(UIKit)
  import UIKit

  final class NativeTerminalSurfaceView: UIView, UIKeyInput {
    var surface: RasterSurface? {
      didSet { setNeedsDisplay() }
    }

    var style: SwiftUITUITerminalStyle = .default {
      didSet {
        updateMetrics()
        setNeedsDisplay()
      }
    }

    var focusPresentation: FocusPresentation = .none {
      didSet { syncFirstResponder() }
    }

    var allowsTextInput = false {
      didSet { syncFirstResponder() }
    }

    var onResize: ((Size, Size?) -> Void)?
    var onInputEvent: ((InputEvent) -> Void)?

    private var metrics = NativeTerminalMetrics(style: .default)
    private var lastPublishedGrid: Size?
    private var lastPublishedCellPixelSize: Size?

    override init(frame: CGRect) {
      super.init(frame: frame)
      isOpaque = true
      isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      isOpaque = true
      isMultipleTouchEnabled = false
    }

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { false }

    override func layoutSubviews() {
      super.layoutSubviews()
      publishGridIfNeeded()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      publishGridIfNeeded()
      syncFirstResponder()
    }

    override func draw(_ rect: CGRect) {
      guard let context = UIGraphicsGetCurrentContext() else {
        return
      }
      NativeRasterSurfaceRenderer.draw(
        surface: surface,
        style: style,
        metrics: metrics,
        bounds: bounds,
        context: context
      )
    }

    func insertText(_ text: String) {
      for character in text {
        if character == "\n" || character == "\r" {
          onInputEvent?(.key(.init(.return)))
        } else if character == "\t" {
          onInputEvent?(.key(.init(.tab)))
        } else if character == " " {
          onInputEvent?(.key(.init(.space)))
        } else {
          onInputEvent?(.key(.init(.character(character))))
        }
      }
    }

    func deleteBackward() {
      onInputEvent?(.key(.init(.backspace)))
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      var handled = false
      for press in presses {
        guard let inputEvent = NativeInputMapper.inputEvent(for: press) else {
          continue
        }
        onInputEvent?(inputEvent)
        handled = true
      }

      if !handled {
        super.pressesBegan(presses, with: event)
      }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      becomeFirstResponder()
      guard let touch = touches.first else {
        return
      }
      onInputEvent?(
        .mouse(
          .init(
            kind: .down(.primary),
            location: cellPoint(for: touch.location(in: self))
          )
        )
      )
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else {
        return
      }
      onInputEvent?(
        .mouse(
          .init(
            kind: .dragged(.primary),
            location: cellPoint(for: touch.location(in: self))
          )
        )
      )
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else {
        return
      }
      onInputEvent?(
        .mouse(
          .init(
            kind: .up(.primary),
            location: cellPoint(for: touch.location(in: self))
          )
        )
      )
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      touchesEnded(touches, with: event)
    }

    private func syncFirstResponder() {
      guard window != nil else {
        return
      }

      if allowsTextInput {
        becomeFirstResponder()
      } else if isFirstResponder, !focusPresentation.prefersTextInput {
        resignFirstResponder()
      }
    }

    private func cellPoint(
      for local: CGPoint
    ) -> Point {
      metrics.cellPoint(for: local, in: bounds)
    }

    private func updateMetrics() {
      metrics = NativeTerminalMetrics(style: style)
      publishGridIfNeeded()
    }

    private func publishGridIfNeeded() {
      guard bounds.width > 0, bounds.height > 0 else {
        return
      }

      let grid = metrics.gridSize(for: bounds.size)
      let cellPixelSize = metrics.cellPixelSize(scale: window?.screen.scale ?? UIScreen.main.scale)
      guard grid != lastPublishedGrid || cellPixelSize != lastPublishedCellPixelSize else {
        return
      }

      lastPublishedGrid = grid
      lastPublishedCellPixelSize = cellPixelSize
      onResize?(grid, cellPixelSize)
    }
  }
#endif

private struct NativeTerminalMetrics {
  let font: NativePlatformFont
  let boldFont: NativePlatformFont
  let italicFont: NativePlatformFont
  let boldItalicFont: NativePlatformFont
  let cellSize: CGSize
  let textOffset: CGPoint

  init(style: SwiftUITUITerminalStyle) {
    let baseFont = NativePlatformFont.terminalFont(style: style, emphasis: [])
    font = baseFont
    boldFont = NativePlatformFont.terminalFont(style: style, emphasis: [.bold])
    italicFont = NativePlatformFont.terminalFont(style: style, emphasis: [.italic])
    boldItalicFont = NativePlatformFont.terminalFont(style: style, emphasis: [.bold, .italic])

    let characterSize = NativePlatformFont.measureTerminalCharacter(baseFont)
    let cellWidth = max(1, ceil(characterSize.width))
    let cellHeight = max(1, ceil(baseFont.ascender - baseFont.descender))
    cellSize = CGSize(width: cellWidth, height: cellHeight)
    textOffset = CGPoint(
      x: 0,
      y: max(0, (cellHeight - characterSize.height) / 2)
    )
  }

  func gridSize(
    for boundsSize: CGSize
  ) -> Size {
    Size(
      width: max(1, Int(boundsSize.width / cellSize.width)),
      height: max(1, Int(boundsSize.height / cellSize.height))
    )
  }

  func cellPixelSize(
    scale: CGFloat
  ) -> Size {
    Size(
      width: max(1, Int((cellSize.width * scale).rounded())),
      height: max(1, Int((cellSize.height * scale).rounded()))
    )
  }

  func cellPoint(
    for local: CGPoint,
    in bounds: CGRect
  ) -> Point {
    let x = max(0, min(Int(local.x / cellSize.width), Int(bounds.width / cellSize.width)))
    let y = max(0, min(Int(local.y / cellSize.height), Int(bounds.height / cellSize.height)))
    return Point(x: x, y: y)
  }

  func font(
    for emphasis: TerminalUI.TextStyle.TextEmphasis
  ) -> NativePlatformFont {
    switch (emphasis.contains(.bold), emphasis.contains(.italic)) {
    case (true, true):
      boldItalicFont
    case (true, false):
      boldFont
    case (false, true):
      italicFont
    case (false, false):
      font
    }
  }
}

private enum NativeRasterSurfaceRenderer {
  static func draw(
    surface: RasterSurface?,
    style: SwiftUITUITerminalStyle,
    metrics: NativeTerminalMetrics,
    bounds: CGRect,
    context: CGContext
  ) {
    let defaultForeground = style.palette.foreground
    let defaultBackground = style.palette.background
    context.setFillColor(
      NativePlatformColor.terminalColor(
        defaultBackground,
        alphaMultiplier: Double(style.backgroundOpacity)
      ).cgColor
    )
    context.fill(bounds)

    guard let surface else {
      return
    }

    for (y, row) in surface.cells.enumerated() {
      for (x, cell) in row.enumerated() where !cell.isContinuation {
        drawCell(
          cell,
          x: x,
          y: y,
          style: cell.style ?? ResolvedTextStyle(),
          defaultForeground: defaultForeground,
          metrics: metrics,
          context: context
        )
      }
    }

    for attachment in surface.imageAttachments {
      drawImageAttachment(
        attachment,
        metrics: metrics,
        context: context
      )
    }
  }

  private static func drawCell(
    _ cell: RasterCell,
    x: Int,
    y: Int,
    style: ResolvedTextStyle,
    defaultForeground: TerminalUI.Color,
    metrics: NativeTerminalMetrics,
    context: CGContext
  ) {
    let spanWidth = max(1, cell.spanWidth)
    let rect = CGRect(
      x: CGFloat(x) * metrics.cellSize.width,
      y: CGFloat(y) * metrics.cellSize.height,
      width: CGFloat(spanWidth) * metrics.cellSize.width,
      height: metrics.cellSize.height
    )

    if let background = style.backgroundColor {
      context.setFillColor(
        NativePlatformColor.terminalColor(
          background,
          alphaMultiplier: style.opacity
        ).cgColor
      )
      context.fill(rect)
    }

    guard cell.character != " " else {
      return
    }

    let foreground = style.foregroundColor ?? defaultForeground
    let color = NativePlatformColor.terminalColor(
      foreground,
      alphaMultiplier: style.opacity
    )
    let font = metrics.font(for: style.emphasis)
    let textPoint = CGPoint(
      x: rect.minX,
      y: rect.minY + metrics.textOffset.y
    )
    let text = String(cell.character) as NSString
    text.draw(
      at: textPoint,
      withAttributes: [
        .font: font,
        .foregroundColor: color,
      ]
    )

    drawLineDecorations(
      style: style,
      fallbackColor: color,
      rect: rect,
      metrics: metrics,
      context: context
    )
  }

  private static func drawLineDecorations(
    style: ResolvedTextStyle,
    fallbackColor: NativePlatformColor,
    rect: CGRect,
    metrics: NativeTerminalMetrics,
    context: CGContext
  ) {
    if let underlineStyle = style.underlineStyle {
      let color =
        underlineStyle.color.map {
          NativePlatformColor.terminalColor($0, alphaMultiplier: style.opacity)
        } ?? fallbackColor
      strokeLine(
        y: rect.minY + metrics.cellSize.height - 2,
        color: color,
        rect: rect,
        context: context
      )
    }

    if let strikethroughStyle = style.strikethroughStyle {
      let color =
        strikethroughStyle.color.map {
          NativePlatformColor.terminalColor($0, alphaMultiplier: style.opacity)
        } ?? fallbackColor
      strokeLine(
        y: rect.midY,
        color: color,
        rect: rect,
        context: context
      )
    }
  }

  private static func strokeLine(
    y: CGFloat,
    color: NativePlatformColor,
    rect: CGRect,
    context: CGContext
  ) {
    context.saveGState()
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(1)
    context.move(to: CGPoint(x: rect.minX, y: y))
    context.addLine(to: CGPoint(x: rect.maxX, y: y))
    context.strokePath()
    context.restoreGState()
  }

  private static func drawImageAttachment(
    _ attachment: RasterImageAttachment,
    metrics: NativeTerminalMetrics,
    context _: CGContext
  ) {
    guard let image = NativePlatformImage.terminalImage(from: attachment.source) else {
      return
    }

    let bounds = attachment.visibleBounds
    guard !bounds.isEmpty else {
      return
    }

    let rect = CGRect(
      x: CGFloat(bounds.origin.x) * metrics.cellSize.width,
      y: CGFloat(bounds.origin.y) * metrics.cellSize.height,
      width: CGFloat(bounds.size.width) * metrics.cellSize.width,
      height: CGFloat(bounds.size.height) * metrics.cellSize.height
    )
    image.drawTerminalImage(in: rect)
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  private typealias NativePlatformFont = NSFont
  private typealias NativePlatformColor = NSColor
  private typealias NativePlatformImage = NSImage

  extension NativePlatformFont {
    fileprivate static func terminalFont(
      style: SwiftUITUITerminalStyle,
      emphasis: TerminalUI.TextStyle.TextEmphasis
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

    fileprivate static func measureTerminalCharacter(
      _ font: NativePlatformFont
    ) -> CGSize {
      ("W" as NSString).size(withAttributes: [.font: font])
    }

    fileprivate func withTerminalTraits(
      _ traits: TerminalUI.TextStyle.TextEmphasis
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
    fileprivate static func terminalColor(
      _ color: TerminalUI.Color,
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
    fileprivate static func terminalImage(
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
      case .pngData(let bytes):
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

  private enum NativeInputMapper {
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
  private typealias NativePlatformFont = UIFont
  private typealias NativePlatformColor = UIColor
  private typealias NativePlatformImage = UIImage

  extension NativePlatformFont {
    fileprivate static func terminalFont(
      style: SwiftUITUITerminalStyle,
      emphasis: TerminalUI.TextStyle.TextEmphasis
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

    fileprivate static func measureTerminalCharacter(
      _ font: NativePlatformFont
    ) -> CGSize {
      ("W" as NSString).size(withAttributes: [.font: font])
    }

    fileprivate func withTerminalTraits(
      _ traits: TerminalUI.TextStyle.TextEmphasis
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
    fileprivate static func terminalColor(
      _ color: TerminalUI.Color,
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
    fileprivate static func terminalImage(
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
      case .pngData(let bytes):
        return UIImage(data: Data(bytes))
      }
    }

    func drawTerminalImage(
      in rect: CGRect
    ) {
      draw(in: rect)
    }
  }

  private enum NativeInputMapper {
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

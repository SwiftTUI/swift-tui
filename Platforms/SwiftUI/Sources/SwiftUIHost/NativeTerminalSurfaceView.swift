import CoreGraphics
import Foundation
import SwiftTUIRuntime

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  final class NativeTerminalSurfaceView: NSView {
    private(set) var surface: RasterSurface?

    var style: SwiftUIHostTerminalStyle = .default {
      didSet {
        guard oldValue != style else {
          return
        }
        updateMetrics()
        needsDisplay = true
      }
    }

    var focusPresentation: FocusPresentation = .none
    var allowsTextInput = false
    var onResize: ((CellSize, PixelSize?) -> Void)?
    var onInputEvent: ((InputEvent) -> Void)?

    private var metrics = NativeTerminalMetrics(style: .default)
    private var lastPublishedGrid: CellSize?
    private var lastPublishedCellPixelSize: PixelSize?

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
        dirtyRect: dirtyRect,
        context: context
      )
    }

    func present(
      surface: RasterSurface?,
      damage: PresentationDamage?
    ) {
      let previousSize = self.surface?.size
      self.surface = surface
      invalidateSurface(previousSize: previousSize, surface: surface, damage: damage)
    }

    override func keyDown(with event: NSEvent) {
      if let inputEvent = NativeInputMapper.inputEvent(for: event) {
        onInputEvent?(inputEvent)
      } else {
        super.keyDown(with: event)
      }
    }

    override func mouseDown(with event: NSEvent) {
      unsafe window?.makeFirstResponder(self)
      onInputEvent?(
        .mouse(
          .init(
            kind: .down(.primary),
            location: pointerLocation(for: event.locationInWindow),
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
            location: pointerLocation(for: event.locationInWindow),
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
            location: pointerLocation(for: event.locationInWindow),
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
            location: pointerLocation(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    private func pointerLocation(
      for windowPoint: NSPoint
    ) -> PointerLocation {
      let local = convert(windowPoint, from: nil)
      return metrics.pointerLocation(
        for: CGPoint(x: local.x, y: local.y),
        in: bounds,
        scale: backingScale
      )
    }

    private var backingScale: CGFloat {
      unsafe window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
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
      let cellPixelSize = metrics.cellPixelSize(scale: backingScale)
      guard grid != lastPublishedGrid || cellPixelSize != lastPublishedCellPixelSize else {
        return
      }

      lastPublishedGrid = grid
      lastPublishedCellPixelSize = cellPixelSize
      onResize?(grid, cellPixelSize)
    }

    private func invalidateSurface(
      previousSize: CellSize?,
      surface: RasterSurface?,
      damage: PresentationDamage?
    ) {
      guard let surface,
        let damage,
        previousSize == surface.size,
        !damage.requiresFullTextRepaint,
        !damage.requiresFullGraphicsReplay
      else {
        needsDisplay = true
        return
      }

      let rects = NativeRasterSurfaceRenderer.dirtyRects(
        for: damage,
        surface: surface,
        metrics: metrics,
        bounds: bounds
      )
      guard !rects.isEmpty else {
        return
      }
      for rect in rects {
        setNeedsDisplay(rect)
      }
    }
  }
#elseif canImport(UIKit)
  import UIKit

  final class NativeTerminalSurfaceView: UIView, UIKeyInput {
    private(set) var surface: RasterSurface?

    var style: SwiftUIHostTerminalStyle = .default {
      didSet {
        guard oldValue != style else {
          return
        }
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

    var onResize: ((CellSize, PixelSize?) -> Void)?
    var onInputEvent: ((InputEvent) -> Void)?

    private var metrics = NativeTerminalMetrics(style: .default)
    private var lastPublishedGrid: CellSize?
    private var lastPublishedCellPixelSize: PixelSize?

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
        dirtyRect: rect,
        context: context
      )
    }

    func present(
      surface: RasterSurface?,
      damage: PresentationDamage?
    ) {
      let previousSize = self.surface?.size
      self.surface = surface
      invalidateSurface(previousSize: previousSize, surface: surface, damage: damage)
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
            location: pointerLocation(for: touch.location(in: self))
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
            location: pointerLocation(for: touch.location(in: self))
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
            location: pointerLocation(for: touch.location(in: self))
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

    private func pointerLocation(
      for local: CGPoint
    ) -> PointerLocation {
      metrics.pointerLocation(
        for: local,
        in: bounds,
        scale: backingScale
      )
    }

    private var backingScale: CGFloat {
      window?.screen.scale ?? UIScreen.main.scale
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
      let cellPixelSize = metrics.cellPixelSize(scale: backingScale)
      guard grid != lastPublishedGrid || cellPixelSize != lastPublishedCellPixelSize else {
        return
      }

      lastPublishedGrid = grid
      lastPublishedCellPixelSize = cellPixelSize
      onResize?(grid, cellPixelSize)
    }

    private func invalidateSurface(
      previousSize: CellSize?,
      surface: RasterSurface?,
      damage: PresentationDamage?
    ) {
      guard let surface,
        let damage,
        previousSize == surface.size,
        !damage.requiresFullTextRepaint,
        !damage.requiresFullGraphicsReplay
      else {
        setNeedsDisplay()
        return
      }

      let rects = NativeRasterSurfaceRenderer.dirtyRects(
        for: damage,
        surface: surface,
        metrics: metrics,
        bounds: bounds
      )
      guard !rects.isEmpty else {
        return
      }
      for rect in rects {
        setNeedsDisplay(rect)
      }
    }
  }
#endif

// `NativeTerminalMetrics`, `NativeRasterSurfaceRenderer`, and the platform
// adapters (`NativePlatformFont`/`Color`/`Image`, `NativeInputMapper`) live in
// `NativeTerminalMetrics.swift`, `NativeRasterSurfaceRenderer.swift`, and
// `NativeTerminalPlatformAdapters.swift` respectively.

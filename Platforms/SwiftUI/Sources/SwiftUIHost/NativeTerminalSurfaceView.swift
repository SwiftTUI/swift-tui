import CoreGraphics
import Foundation
import SwiftTUIRuntime

struct NativeTerminalSurfaceConfirmedSlack: Equatable {
  private struct AxisSlack: Equatable {
    var preferred: Int
    var capacity: Int
  }

  private var width: AxisSlack?
  private var height: AxisSlack?

  mutating func update(
    preferredGridSize: CellSize?,
    renderedGridSize: CellSize?
  ) {
    width = updatedAxisSlack(
      preferred: preferredGridSize?.width,
      rendered: renderedGridSize?.width,
      current: width
    )
    height = updatedAxisSlack(
      preferred: preferredGridSize?.height,
      rendered: renderedGridSize?.height,
      current: height
    )
  }

  func confirmedPreferredWidth(
    proposed: Int,
    preferred: Int?,
    rendered: Int?
  ) -> Int? {
    confirmedPreferred(
      axisSlack: width,
      proposed: proposed,
      preferred: preferred,
      rendered: rendered
    )
  }

  func confirmedPreferredHeight(
    proposed: Int,
    preferred: Int?,
    rendered: Int?
  ) -> Int? {
    confirmedPreferred(
      axisSlack: height,
      proposed: proposed,
      preferred: preferred,
      rendered: rendered
    )
  }

  private func updatedAxisSlack(
    preferred: Int?,
    rendered: Int?,
    current: AxisSlack?
  ) -> AxisSlack? {
    guard let preferred, let rendered else {
      return nil
    }

    let normalizedPreferred = max(1, preferred)
    let normalizedRendered = max(1, rendered)
    if normalizedPreferred < normalizedRendered {
      return AxisSlack(preferred: normalizedPreferred, capacity: normalizedRendered)
    }
    if let current, normalizedPreferred == current.preferred,
      normalizedRendered <= current.capacity
    {
      return current
    }
    return nil
  }

  private func confirmedPreferred(
    axisSlack: AxisSlack?,
    proposed: Int,
    preferred: Int?,
    rendered: Int?
  ) -> Int? {
    guard let axisSlack, let preferred, let rendered else {
      return nil
    }

    guard max(1, preferred) == axisSlack.preferred,
      max(1, rendered) <= axisSlack.capacity,
      max(1, proposed) <= axisSlack.capacity
    else {
      return nil
    }

    return axisSlack.preferred
  }
}

struct NativeTerminalSurfaceSizeNegotiation: Equatable {
  var size: CGSize
  var probeGridSize: CellSize?
}

struct NativeTerminalSurfaceSizeNegotiator {
  var cellSize: CGSize
  var preferredGridSize: CellSize?
  var renderedGridSize: CellSize?
  var fallbackGridSize = CellSize(width: 80, height: 24)
  var confirmedSlack = NativeTerminalSurfaceConfirmedSlack()

  func sizeThatFits(
    proposedWidth: CGFloat?,
    proposedHeight: CGFloat?
  ) -> CGSize {
    negotiate(
      proposedWidth: proposedWidth,
      proposedHeight: proposedHeight
    ).size
  }

  func negotiate(
    proposedWidth: CGFloat?,
    proposedHeight: CGFloat?
  ) -> NativeTerminalSurfaceSizeNegotiation {
    let width = resolvedAxis(
      preferred: preferredGridSize?.width,
      rendered: renderedGridSize?.width,
      fallback: fallbackGridSize.width,
      proposedLength: proposedWidth,
      cellLength: cellSize.width
    ) { proposed, preferred, rendered in
      confirmedSlack.confirmedPreferredWidth(
        proposed: proposed,
        preferred: preferred,
        rendered: rendered
      )
    }
    let height = resolvedAxis(
      preferred: preferredGridSize?.height,
      rendered: renderedGridSize?.height,
      fallback: fallbackGridSize.height,
      proposedLength: proposedHeight,
      cellLength: cellSize.height
    ) { proposed, preferred, rendered in
      confirmedSlack.confirmedPreferredHeight(
        proposed: proposed,
        preferred: preferred,
        rendered: rendered
      )
    }

    let probeGridSize: CellSize? =
      if width.probeCells != nil || height.probeCells != nil {
        CellSize(
          width: width.probeCells ?? width.cells,
          height: height.probeCells ?? height.cells
        )
      } else {
        nil
      }

    return NativeTerminalSurfaceSizeNegotiation(
      size: CGSize(
        width: CGFloat(width.cells) * cellSize.width,
        height: CGFloat(height.cells) * cellSize.height
      ),
      probeGridSize: probeGridSize
    )
  }

  func intrinsicContentSize(
    noIntrinsicMetric: CGFloat
  ) -> CGSize {
    guard let preferredGridSize else {
      return CGSize(width: noIntrinsicMetric, height: noIntrinsicMetric)
    }

    return CGSize(
      width: CGFloat(max(1, preferredGridSize.width)) * cellSize.width,
      height: CGFloat(max(1, preferredGridSize.height)) * cellSize.height
    )
  }

  private struct AxisNegotiation {
    var cells: Int
    var probeCells: Int?
  }

  private func resolvedAxis(
    preferred: Int?,
    rendered: Int?,
    fallback: Int,
    proposedLength: CGFloat?,
    cellLength: CGFloat,
    confirmedPreferred: (Int, Int?, Int?) -> Int?
  ) -> AxisNegotiation {
    let preferred = preferred.map { max(1, $0) }
    let rendered = rendered.map { max(1, $0) }

    if let proposedCells = proposedCells(
      for: proposedLength,
      cellLength: cellLength
    ) {
      if let confirmedPreferred = confirmedPreferred(proposedCells, preferred, rendered) {
        return AxisNegotiation(
          cells: max(1, min(confirmedPreferred, proposedCells)),
          probeCells: nil
        )
      }

      guard let preferred else {
        return AxisNegotiation(cells: proposedCells, probeCells: nil)
      }
      if let rendered, proposedCells > rendered, preferred == rendered {
        return AxisNegotiation(cells: preferred, probeCells: proposedCells)
      }
      return AxisNegotiation(cells: max(1, min(preferred, proposedCells)), probeCells: nil)
    }

    return AxisNegotiation(cells: max(1, preferred ?? rendered ?? fallback), probeCells: nil)
  }

  private func proposedCells(
    for proposedLength: CGFloat?,
    cellLength: CGFloat
  ) -> Int? {
    guard let proposedLength,
      proposedLength.isFinite,
      proposedLength > 0,
      cellLength.isFinite,
      cellLength > 0
    else {
      return nil
    }

    return max(1, Int((proposedLength / cellLength).rounded(.down)))
  }
}

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
    var preferredGridSize: CellSize? {
      didSet {
        guard oldValue != preferredGridSize else {
          return
        }
        invalidateNegotiatedSize()
      }
    }
    var onResize: ((CellSize, PixelSize?) -> Void)?
    var onInputEvent: ((InputEvent) -> Void)?

    private var metrics = NativeTerminalMetrics(style: .default)
    private var lastPublishedLayoutGrid: CellSize?
    private var lastPublishedLayoutCellPixelSize: PixelSize?
    private var lastRequestedSurfaceGrid: CellSize?
    private var lastRequestedSurfaceCellPixelSize: PixelSize?
    private var confirmedSlack = NativeTerminalSurfaceConfirmedSlack()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
      sizeNegotiator.intrinsicContentSize(noIntrinsicMetric: NSView.noIntrinsicMetric)
    }

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
      confirmedSlack.update(
        preferredGridSize: preferredGridSize,
        renderedGridSize: surface?.size
      )
      if previousSize != surface?.size {
        invalidateNegotiatedSize()
      }
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
      invalidateNegotiatedSize()
      publishGridIfNeeded()
    }

    func negotiatedSizeThatFits(
      proposedWidth: CGFloat?,
      proposedHeight: CGFloat?,
      preferredGridSize: CellSize?
    ) -> CGSize {
      let negotiation = makeSizeNegotiator(preferredGridSize: preferredGridSize).negotiate(
        proposedWidth: proposedWidth,
        proposedHeight: proposedHeight
      )
      publishProbeGridIfNeeded(negotiation.probeGridSize)
      return negotiation.size
    }

    private var sizeNegotiator: NativeTerminalSurfaceSizeNegotiator {
      makeSizeNegotiator(preferredGridSize: preferredGridSize)
    }

    private func makeSizeNegotiator(
      preferredGridSize: CellSize?
    ) -> NativeTerminalSurfaceSizeNegotiator {
      NativeTerminalSurfaceSizeNegotiator(
        cellSize: metrics.cellSize,
        preferredGridSize: preferredGridSize,
        renderedGridSize: surface?.size,
        confirmedSlack: confirmedSlack
      )
    }

    private func invalidateNegotiatedSize() {
      invalidateIntrinsicContentSize()
      needsLayout = true
    }

    private func publishGridIfNeeded() {
      guard bounds.width > 0, bounds.height > 0 else {
        return
      }

      let grid = metrics.gridSize(for: bounds.size)
      let cellPixelSize = metrics.cellPixelSize(scale: backingScale)
      guard
        grid != lastPublishedLayoutGrid
          || cellPixelSize != lastPublishedLayoutCellPixelSize
      else {
        return
      }

      lastPublishedLayoutGrid = grid
      lastPublishedLayoutCellPixelSize = cellPixelSize
      publishSurfaceGridIfNeeded(grid, cellPixelSize: cellPixelSize)
    }

    private func publishProbeGridIfNeeded(
      _ grid: CellSize?
    ) {
      guard let grid else {
        return
      }
      publishSurfaceGridIfNeeded(
        grid,
        cellPixelSize: metrics.cellPixelSize(scale: backingScale)
      )
    }

    private func publishSurfaceGridIfNeeded(
      _ grid: CellSize,
      cellPixelSize: PixelSize?
    ) {
      guard
        grid != lastRequestedSurfaceGrid
          || cellPixelSize != lastRequestedSurfaceCellPixelSize
      else {
        return
      }

      lastRequestedSurfaceGrid = grid
      lastRequestedSurfaceCellPixelSize = cellPixelSize
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

    var preferredGridSize: CellSize? {
      didSet {
        guard oldValue != preferredGridSize else {
          return
        }
        invalidateNegotiatedSize()
      }
    }
    var onResize: ((CellSize, PixelSize?) -> Void)?
    var onInputEvent: ((InputEvent) -> Void)?

    private var metrics = NativeTerminalMetrics(style: .default)
    private var lastPublishedLayoutGrid: CellSize?
    private var lastPublishedLayoutCellPixelSize: PixelSize?
    private var lastRequestedSurfaceGrid: CellSize?
    private var lastRequestedSurfaceCellPixelSize: PixelSize?
    private var confirmedSlack = NativeTerminalSurfaceConfirmedSlack()

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
    override var intrinsicContentSize: CGSize {
      sizeNegotiator.intrinsicContentSize(noIntrinsicMetric: UIView.noIntrinsicMetric)
    }
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
      confirmedSlack.update(
        preferredGridSize: preferredGridSize,
        renderedGridSize: surface?.size
      )
      if previousSize != surface?.size {
        invalidateNegotiatedSize()
      }
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
      invalidateNegotiatedSize()
      publishGridIfNeeded()
    }

    func negotiatedSizeThatFits(
      proposedWidth: CGFloat?,
      proposedHeight: CGFloat?,
      preferredGridSize: CellSize?
    ) -> CGSize {
      let negotiation = makeSizeNegotiator(preferredGridSize: preferredGridSize).negotiate(
        proposedWidth: proposedWidth,
        proposedHeight: proposedHeight
      )
      publishProbeGridIfNeeded(negotiation.probeGridSize)
      return negotiation.size
    }

    private var sizeNegotiator: NativeTerminalSurfaceSizeNegotiator {
      makeSizeNegotiator(preferredGridSize: preferredGridSize)
    }

    private func makeSizeNegotiator(
      preferredGridSize: CellSize?
    ) -> NativeTerminalSurfaceSizeNegotiator {
      NativeTerminalSurfaceSizeNegotiator(
        cellSize: metrics.cellSize,
        preferredGridSize: preferredGridSize,
        renderedGridSize: surface?.size,
        confirmedSlack: confirmedSlack
      )
    }

    private func invalidateNegotiatedSize() {
      invalidateIntrinsicContentSize()
      setNeedsLayout()
    }

    private func publishGridIfNeeded() {
      guard bounds.width > 0, bounds.height > 0 else {
        return
      }

      let grid = metrics.gridSize(for: bounds.size)
      let cellPixelSize = metrics.cellPixelSize(scale: backingScale)
      guard
        grid != lastPublishedLayoutGrid
          || cellPixelSize != lastPublishedLayoutCellPixelSize
      else {
        return
      }

      lastPublishedLayoutGrid = grid
      lastPublishedLayoutCellPixelSize = cellPixelSize
      publishSurfaceGridIfNeeded(grid, cellPixelSize: cellPixelSize)
    }

    private func publishProbeGridIfNeeded(
      _ grid: CellSize?
    ) {
      guard let grid else {
        return
      }
      publishSurfaceGridIfNeeded(
        grid,
        cellPixelSize: metrics.cellPixelSize(scale: backingScale)
      )
    }

    private func publishSurfaceGridIfNeeded(
      _ grid: CellSize,
      cellPixelSize: PixelSize?
    ) {
      guard
        grid != lastRequestedSurfaceGrid
          || cellPixelSize != lastRequestedSurfaceCellPixelSize
      else {
        return
      }

      lastRequestedSurfaceGrid = grid
      lastRequestedSurfaceCellPixelSize = cellPixelSize
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

import SwiftTUI
import Testing

@testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  @Test
  func native_surface_view_emits_mouse_down_before_mouse_up() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    let metrics = NativeTerminalMetrics(style: .default)
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }

    let localPoint = NSPoint(
      x: metrics.cellSize.width * 2.5,
      y: metrics.cellSize.height * 1.5
    )
    let point = windowPoint(forLocal: localPoint, in: view)
    view.mouseDown(
      with: mouseEvent(
        type: .leftMouseDown,
        location: point,
        eventNumber: 1
      )
    )

    #expect(events.count == 1)
    #expect(events.first?.mouseKind == .down(.primary))
    let downLocation = try #require(events.first?.mouseLocation)
    #expect(downLocation.cell == CellPoint(x: 2, y: 1))
    #expect(abs(downLocation.location.x - 2.5) < 0.0001)
    #expect(abs(downLocation.location.y - 1.5) < 0.0001)
    guard
      case .subCell(source: .nativePixels, metrics: let precisionMetrics) =
        downLocation.precision
    else {
      Issue.record("expected native sub-cell precision")
      return
    }
    #expect(precisionMetrics.source == .reported)
    #expect(downLocation.rawPixel != nil)

    view.mouseUp(
      with: mouseEvent(
        type: .leftMouseUp,
        location: point,
        eventNumber: 2
      )
    )

    #expect(events.map(\.mouseKind) == [.down(.primary), .up(.primary)])
  }

  @MainActor
  @Test
  func native_surface_view_emits_drag_and_scroll_events() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    let metrics = NativeTerminalMetrics(style: .default)
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }
    let localPoint = NSPoint(
      x: metrics.cellSize.width * 3.25,
      y: metrics.cellSize.height * 1.75
    )
    let point = windowPoint(forLocal: localPoint, in: view)

    view.mouseDragged(
      with: mouseEvent(
        type: .leftMouseDragged,
        location: point,
        eventNumber: 1
      )
    )
    view.scrollWheel(
      with: scrollEvent(
        location: point,
        scrollingDeltaX: 0,
        scrollingDeltaY: -3
      )
    )

    #expect(events.count == 2)
    #expect(events[0].mouseKind == .dragged(.primary))
    #expect(events[1].mouseKind == .scrolled(deltaX: 0, deltaY: 3))
    let dragLocation = try #require(events[0].mouseLocation)
    #expect(dragLocation.cell == CellPoint(x: 3, y: 1))
    #expect(abs(dragLocation.location.x - 3.25) < 0.0001)
    #expect(abs(dragLocation.location.y - 1.75) < 0.0001)
    let scrollLocation = try #require(events[1].mouseLocation)
    guard case .subCell(source: .nativePixels, metrics: _) = scrollLocation.precision else {
      Issue.record("expected native sub-cell precision")
      return
    }
  }

  @MainActor
  @Test
  func native_surface_view_preserves_sub_cell_drag_inside_one_cell() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    let metrics = NativeTerminalMetrics(style: .default)
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }

    view.mouseDragged(
      with: mouseEvent(
        type: .leftMouseDragged,
        location: windowPoint(
          forLocal: NSPoint(
            x: metrics.cellSize.width * 2.10,
            y: metrics.cellSize.height * 1.40
          ),
          in: view
        ),
        eventNumber: 1
      )
    )
    view.mouseDragged(
      with: mouseEvent(
        type: .leftMouseDragged,
        location: windowPoint(
          forLocal: NSPoint(
            x: metrics.cellSize.width * 2.70,
            y: metrics.cellSize.height * 1.40
          ),
          in: view
        ),
        eventNumber: 2
      )
    )

    let first = try #require(events.first?.mouseLocation)
    let second = try #require(events.dropFirst().first?.mouseLocation)
    #expect(first.cell == CellPoint(x: 2, y: 1))
    #expect(second.cell == CellPoint(x: 2, y: 1))
    #expect(first.location != second.location)
  }

  @MainActor
  @Test
  func native_surface_view_growth_probe_is_not_undone_by_unchanged_layout_bounds() {
    let metrics = NativeTerminalMetrics(style: .default)
    let visibleGrid = CellSize(width: 5, height: 3)
    let probeGrid = CellSize(width: 12, height: 6)
    let view = NativeTerminalSurfaceView(
      frame: NSRect(
        x: 0,
        y: 0,
        width: metrics.cellSize.width * CGFloat(visibleGrid.width),
        height: metrics.cellSize.height * CGFloat(visibleGrid.height)
      )
    )
    var resizes: [CellSize] = []
    view.onResize = { size, _ in
      resizes.append(size)
    }
    view.preferredGridSize = visibleGrid
    view.present(
      surface: RasterSurface(
        size: visibleGrid,
        lines: Array(repeating: "", count: visibleGrid.height)
      ),
      damage: nil
    )

    view.layout()
    _ = view.negotiatedSizeThatFits(
      proposedWidth: metrics.cellSize.width * CGFloat(probeGrid.width),
      proposedHeight: metrics.cellSize.height * CGFloat(probeGrid.height),
      preferredGridSize: visibleGrid
    )
    view.layout()

    #expect(resizes == [visibleGrid, probeGrid])
  }

  @MainActor
  @Test
  func native_surface_view_initial_probe_is_not_undone_by_placeholder_layout_bounds() {
    let metrics = NativeTerminalMetrics(style: .default)
    let placeholderGrid = CellSize(width: 1, height: 1)
    let probeGrid = CellSize(width: 12, height: 6)
    let view = NativeTerminalSurfaceView(
      frame: NSRect(
        x: 0,
        y: 0,
        width: metrics.cellSize.width * CGFloat(placeholderGrid.width),
        height: metrics.cellSize.height * CGFloat(placeholderGrid.height)
      )
    )
    var resizes: [CellSize] = []
    view.onResize = { size, _ in
      resizes.append(size)
    }

    _ = view.negotiatedSizeThatFits(
      proposedWidth: metrics.cellSize.width * CGFloat(probeGrid.width),
      proposedHeight: metrics.cellSize.height * CGFloat(probeGrid.height),
      preferredGridSize: nil
    )
    view.layout()

    #expect(resizes == [probeGrid])
  }

  @MainActor
  private func windowPoint(
    forLocal local: NSPoint,
    in view: NativeTerminalSurfaceView
  ) -> NSPoint {
    NSPoint(
      x: local.x,
      y: view.bounds.height - local.y
    )
  }

  private func mouseEvent(
    type: NSEvent.EventType,
    location: NSPoint,
    eventNumber: Int
  ) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: eventNumber,
      clickCount: 1,
      pressure: 1
    )!
  }

  private func scrollEvent(
    location: NSPoint,
    scrollingDeltaX: CGFloat,
    scrollingDeltaY: CGFloat
  ) -> NSEvent {
    let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 2,
      wheel1: Int32(scrollingDeltaY),
      wheel2: Int32(scrollingDeltaX),
      wheel3: 0
    )!
    event.location = location
    return NSEvent(cgEvent: event)!
  }
#endif

extension InputEvent {
  fileprivate var mouseKind: MouseEvent.Kind? {
    guard case .mouse(let mouseEvent) = self else {
      return nil
    }
    return mouseEvent.kind
  }

  fileprivate var mouseLocation: PointerLocation? {
    guard case .mouse(let mouseEvent) = self else {
      return nil
    }
    return mouseEvent.location
  }
}

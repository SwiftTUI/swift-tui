import TerminalUI
import Testing

@testable import SwiftUITUIGUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  @Test
  func native_surface_view_emits_mouse_down_before_mouse_up() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }

    view.mouseDown(
      with: mouseEvent(
        type: .leftMouseDown,
        location: NSPoint(x: 12, y: 10),
        eventNumber: 1
      )
    )

    #expect(events.count == 1)
    #expect(events.first?.mouseKind == .down(.primary))
    let downLocation = try #require(events.first?.mouseLocation)
    #expect(downLocation.precision == .cell)
    #expect(
      downLocation.location
        == Point(
          x: Double(downLocation.cell.x) + 0.5,
          y: Double(downLocation.cell.y) + 0.5
        ))

    view.mouseUp(
      with: mouseEvent(
        type: .leftMouseUp,
        location: NSPoint(x: 12, y: 10),
        eventNumber: 2
      )
    )

    #expect(events.map(\.mouseKind) == [.down(.primary), .up(.primary)])
  }

  @MainActor
  @Test
  func native_surface_view_emits_drag_and_scroll_events() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }

    view.mouseDragged(
      with: mouseEvent(
        type: .leftMouseDragged,
        location: NSPoint(x: 24, y: 18),
        eventNumber: 1
      )
    )
    view.scrollWheel(
      with: scrollEvent(
        location: NSPoint(x: 24, y: 18),
        scrollingDeltaX: 0,
        scrollingDeltaY: -3
      )
    )

    #expect(events.count == 2)
    #expect(events[0].mouseKind == .dragged(.primary))
    #expect(events[1].mouseKind == .scrolled(deltaX: 0, deltaY: 3))
    let scrollLocation = try #require(events[1].mouseLocation)
    #expect(scrollLocation.precision == .cell)
    #expect(
      scrollLocation.location
        == Point(
          x: Double(scrollLocation.cell.x) + 0.5,
          y: Double(scrollLocation.cell.y) + 0.5
        ))
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

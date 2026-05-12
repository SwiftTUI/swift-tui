import SwiftTUI

struct ScrollControlTab: View {
  @State private var position = ScrollPosition.zero
  @State private var lastCommand = "ready"

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 1) {
        header
        controls(proxy)
        Divider()
        scrollPane
        Divider()
        status
        Spacer(minLength: 0)
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Scroll Control")
        .foregroundStyle(.foreground)
      Text("ScrollViewReader drives identity, anchor, edge, and offset movement.")
        .foregroundStyle(.separator)
    }
  }

  private func controls(
    _ proxy: ScrollViewProxy
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 1) {
        Button("Top") {
          record("top edge", changed: proxy.scrollTo(edge: .top))
        }
        Button("Build") {
          record(
            "build anchored top",
            changed: proxy.scrollTo(ScrollControlTarget.build.identity, anchor: .top)
          )
        }
        Button("Errors") {
          record(
            "errors centered",
            changed: proxy.scrollTo(ScrollControlTarget.errors.identity, anchor: .center)
          )
        }
        Button("Bottom") {
          record("bottom edge", changed: proxy.scrollTo(edge: .bottom))
        }
      }
      HStack(spacing: 1) {
        Button("Up 2") {
          record("up two rows", changed: proxy.scrollBy(y: -2))
        }
        Button("Down 2") {
          record("down two rows", changed: proxy.scrollBy(y: 2))
        }
        Button("Offset 6") {
          record("absolute offset six", changed: proxy.scrollTo(y: 6))
        }
      }
    }
  }

  private var scrollPane: some View {
    ScrollView(
      .vertical,
      showsIndicators: true,
      position: $position
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(ScrollControlEvent.events) { event in
          row(for: event)
            .id(event.identity)
        }
      }
    }
    .frame(width: 72, height: 11, alignment: .topLeading)
    .border(set: .rounded)
  }

  private func row(
    for event: ScrollControlEvent
  ) -> some View {
    HStack(spacing: 1) {
      Text(event.timestamp)
        .foregroundStyle(.separator)
      Text(event.badge)
        .foregroundStyle(event.tone)
      Text(event.message)
    }
  }

  private var status: some View {
    HStack(spacing: 2) {
      Text("offset")
        .foregroundStyle(.separator)
      Text("x:\(position.x) y:\(position.y)")
        .foregroundStyle(.cyan)
      Text("last")
        .foregroundStyle(.separator)
      Text(lastCommand)
    }
  }

  private func record(
    _ label: String,
    changed: Bool
  ) {
    lastCommand = changed ? label : "\(label) (no change)"
  }
}

private enum ScrollControlTarget: String, Hashable, Sendable {
  case intro = "scroll-control-intro"
  case build = "scroll-control-build"
  case errors = "scroll-control-errors"
  case summary = "scroll-control-summary"

  var identity: Identity {
    Identity(components: [rawValue])
  }
}

private struct ScrollControlEvent: Identifiable, Hashable, Sendable {
  var id: Int
  var identity: Identity
  var timestamp: String
  var badge: String
  var tone: Color
  var message: String
  var target: ScrollControlTarget?

  init(
    id: Int,
    timestamp: String,
    badge: String,
    tone: Color,
    message: String,
    target: ScrollControlTarget? = nil
  ) {
    self.id = id
    self.identity = target?.identity ?? Identity(components: ["scroll-control-event-\(id)"])
    self.timestamp = timestamp
    self.badge = badge
    self.tone = tone
    self.message = message
    self.target = target
  }

  static let events: [Self] = [
    .init(
      id: 0,
      timestamp: "00:00",
      badge: "info ",
      tone: .cyan,
      message: "Scroll targets are ordinary rows with stable .id values",
      target: .intro
    ),
    .init(
      id: 1,
      timestamp: "00:07",
      badge: "task ",
      tone: .green,
      message: "Resolve gallery model state"
    ),
    .init(
      id: 2,
      timestamp: "00:12",
      badge: "task ",
      tone: .green,
      message: "Render tab controls"
    ),
    .init(
      id: 3,
      timestamp: "00:16",
      badge: "build",
      tone: .yellow,
      message: "Compile SwiftTUIViews scroll control surface",
      target: .build
    ),
    .init(
      id: 4,
      timestamp: "00:18",
      badge: "build",
      tone: .yellow,
      message: "Commit target geometry into the scroll registry"
    ),
    .init(
      id: 5,
      timestamp: "00:21",
      badge: "build",
      tone: .yellow,
      message: "Proxy command requests a rerender"
    ),
    .init(
      id: 6,
      timestamp: "00:27",
      badge: "note ",
      tone: .cyan,
      message: "Nil anchor reveals with the smallest possible movement"
    ),
    .init(
      id: 7,
      timestamp: "00:34",
      badge: "warn ",
      tone: .red,
      message: "Missing target IDs are no-op commands",
      target: .errors
    ),
    .init(
      id: 8,
      timestamp: "00:38",
      badge: "warn ",
      tone: .red,
      message: "Anchors clamp to content bounds at top and bottom"
    ),
    .init(
      id: 9,
      timestamp: "00:44",
      badge: "info ",
      tone: .cyan,
      message: "Home and End keys also move focused scroll panes"
    ),
    .init(
      id: 10,
      timestamp: "00:51",
      badge: "done ",
      tone: .green,
      message: "Final gate renders with public ScrollViewReader APIs",
      target: .summary
    ),
    .init(
      id: 11,
      timestamp: "00:55",
      badge: "done ",
      tone: .green,
      message: "Example tab stays inside the gallery package boundary"
    ),
  ]
}

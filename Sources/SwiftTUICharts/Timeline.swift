import Core
import View

/// A compact textual timeline for ordered events or releases.
public struct Timeline: View, ResolvableView {
  public var entries: [TimelineEntry]

  public init(_ entries: [TimelineEntry]) {
    self.entries = entries
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          ForEach(entries.indices, id: \.self) { index in
            timelineEntryView(entries[index], isLast: index == entries.count - 1)
          }
        },
        in: context
      )
    ]
  }
}

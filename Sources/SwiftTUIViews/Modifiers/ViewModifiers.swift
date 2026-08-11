import SwiftTUICore

extension View {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveViewElements(self, in: context)
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }
}

import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct ViewProtocolShapeTests {
  @Test("body-based user view still resolves")
  func bodyBasedUserViewResolves() {
    struct BodyView: View {
      var body: some View {
        Text("ok")
      }
    }

    let resolved = Resolver().resolve(
      BodyView(),
      in: .init(identity: Identity(components: ["ProtocolShape", "BodyView"]))
    )

    #expect(resolved.identity == Identity(components: ["ProtocolShape", "BodyView"]))
  }

  @Test("representative primitive views still compile as View values")
  func representativePrimitiveViewsCompile() {
    func accept<V: View>(_ view: V) {
      _ = view
    }

    accept(Text("ok"))
    accept(EmptyView())
    accept(Group { Text("ok") })
    accept(Rectangle())
    accept(Canvas { _ in })
  }

  @Test("explicit Body Never modifier still compiles without body")
  func explicitPrimitiveModifierCompiles() {
    struct ExplicitPrimitiveModifier: ViewModifier {
      typealias Body = Never
    }

    let modified: ModifiedContent<Text, ExplicitPrimitiveModifier> =
      Text("ok").modifier(ExplicitPrimitiveModifier())

    _ = modified
  }
}

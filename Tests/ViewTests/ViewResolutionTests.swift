import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct ViewResolutionTests {
  @Test("Text view resolves to a single node")
  func textViewResolvesToSingleNode() {
    let resolver = Resolver()
    let view = Text("Hello")
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(resolved.identity == testIdentity("root"))
  }

  @Test("EmptyView resolves with no draw payload")
  func emptyViewResolvesCleanly() {
    let resolver = Resolver()
    let view = EmptyView()
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(resolved.identity == testIdentity("root"))
  }

  @Test("HStack resolves children")
  func hstackResolvesChildren() {
    let resolver = Resolver()
    let view = HStack {
      Text("A")
      Text("B")
    }
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(!resolved.children.isEmpty)
  }

  @Test("LazyVStack resolves children")
  func lazyVStackResolvesChildren() {
    let resolver = Resolver()
    let view = LazyVStack(alignment: .leading, spacing: 2) {
      Text("A")
      Text("B")
    }
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(resolved.identity == testIdentity("root"))
    #expect(resolved.kind == .view("LazyVStack"))
    #expect(resolved.children.count == 2)
    #expect(
      resolved.layoutBehavior
        == .lazyStack(
          axis: .vertical,
          spacing: 2,
          horizontalAlignment: .leading,
          verticalAlignment: .center
        )
    )
  }

  @Test("LazyHStack resolves children")
  func lazyHStackResolvesChildren() {
    let resolver = Resolver()
    let view = LazyHStack(alignment: .top, spacing: 1) {
      Text("A")
      Text("B")
    }
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(resolved.identity == testIdentity("root"))
    #expect(resolved.kind == .view("LazyHStack"))
    #expect(resolved.children.count == 2)
    #expect(
      resolved.layoutBehavior
        == .lazyStack(
          axis: .horizontal,
          spacing: 1,
          horizontalAlignment: .center,
          verticalAlignment: .top
        )
    )
  }
}

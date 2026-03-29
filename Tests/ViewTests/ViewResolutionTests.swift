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
}

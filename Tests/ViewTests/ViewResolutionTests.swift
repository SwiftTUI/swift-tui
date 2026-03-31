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

  @Test("LazyVStack with a single ForEach defers eager child resolution")
  func lazyVStackWithSingleForEachDefersChildResolution() {
    let counter = ResolveInvocationCounter()
    let resolver = Resolver()
    let view = LazyVStack(alignment: .leading, spacing: 1) {
      Group {
        ForEach(0..<3) { index in
          counter.count += 1
          Text("Row \(index)")
        }
      }
    }

    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(resolved.kind == .view("LazyVStack"))
    #expect(counter.count == 0)
  }

  @Test("LazyHStack with a single ForEach defers eager child resolution")
  func lazyHStackWithSingleForEachDefersChildResolution() {
    let counter = ResolveInvocationCounter()
    let resolver = Resolver()
    let view = LazyHStack(alignment: .center, spacing: 1) {
      ForEach(0..<3) { index in
        counter.count += 1
        Text("Column \(index)")
      }
    }

    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(resolved.kind == .view("LazyHStack"))
    #expect(counter.count == 0)
  }

  @Test("LazyVStack with mixed static siblings still resolves ForEach eagerly")
  func lazyVStackWithMixedStaticSiblingsResolvesForEachEagerly() {
    let counter = ResolveInvocationCounter()
    let resolver = Resolver()
    let view = LazyVStack(alignment: .leading, spacing: 1) {
      Text("Header")
      Group {
        ForEach(0..<3) { index in
          counter.count += 1
          Text("Row \(index)")
        }
      }
      Text("Footer")
    }

    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))

    #expect(resolved.kind == .view("LazyVStack"))
    #expect(resolved.children.count == 5)
    #expect(counter.count == 3)
  }
}

private final class ResolveInvocationCounter: @unchecked Sendable {
  var count = 0
}

import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct ViewResolutionTests {
  @Test("Text view resolves to a single node")
  func textViewResolvesToSingleNode() throws {
    let resolver = Resolver()
    let view = Text("Hello")
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))
    let payload = try #require(resolved.anyViewPayload)
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(resolved.identity == testIdentity("root"))
    #expect(resolved.kind == .view("AnyView"))
    #expect(payload.kind == .view("AnyViewPayload"))
    #expect(payload.identity.lastComponent?.contains("Text") == true)
    #expect(content.identity == testIdentity("root", payload.identity.lastComponent!, "Content"))
    #expect(content.kind == .view("Text"))
  }

  @Test("EmptyView resolves with no draw payload")
  func emptyViewResolvesCleanly() throws {
    let resolver = Resolver()
    let view = EmptyView()
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(resolved.identity == testIdentity("root"))
    #expect(resolved.kind == .view("AnyView"))
    #expect(content.kind == .view("EmptyView"))
  }

  @Test("HStack resolves children")
  func hstackResolvesChildren() throws {
    let resolver = Resolver()
    let view = HStack {
      Text("A")
      Text("B")
    }
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(resolved.kind == .view("AnyView"))
    #expect(content.kind == .view("HStack"))
    #expect(!content.children.isEmpty)
  }

  @Test("LazyVStack resolves children")
  func lazyVStackResolvesChildren() throws {
    let resolver = Resolver()
    let view = LazyVStack(alignment: .leading, spacing: 2) {
      Text("A")
      Text("B")
    }
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(resolved.identity == testIdentity("root"))
    #expect(resolved.kind == .view("AnyView"))
    #expect(content.kind == .view("LazyVStack"))
    #expect(content.children.count == 2)
    #expect(
      content.layoutBehavior
        == .lazyStack(
          axis: .vertical,
          spacing: 2,
          horizontalAlignment: .leading,
          verticalAlignment: .center
        )
    )
  }

  @Test("LazyHStack resolves children")
  func lazyHStackResolvesChildren() throws {
    let resolver = Resolver()
    let view = LazyHStack(alignment: .top, spacing: 1) {
      Text("A")
      Text("B")
    }
    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(resolved.identity == testIdentity("root"))
    #expect(resolved.kind == .view("AnyView"))
    #expect(content.kind == .view("LazyHStack"))
    #expect(content.children.count == 2)
    #expect(
      content.layoutBehavior
        == .lazyStack(
          axis: .horizontal,
          spacing: 1,
          horizontalAlignment: .center,
          verticalAlignment: .top
        )
    )
  }

  @Test("LazyVStack with a single ForEach defers eager child resolution")
  func lazyVStackWithSingleForEachDefersChildResolution() throws {
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
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(content.kind == .view("LazyVStack"))
    #expect(counter.count == 0)
    #expect(content.structuralEdgeRole == .viewportBarrier)
    #expect(content.indexedChildSource != nil)
  }

  @Test("LazyHStack with a single ForEach defers eager child resolution")
  func lazyHStackWithSingleForEachDefersChildResolution() throws {
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
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(content.kind == .view("LazyHStack"))
    #expect(counter.count == 0)
    #expect(content.structuralEdgeRole == .viewportBarrier)
    #expect(content.indexedChildSource != nil)
  }

  @Test("LazyVStack with mixed static siblings still resolves ForEach eagerly")
  func lazyVStackWithMixedStaticSiblingsResolvesForEachEagerly() throws {
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
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(content.kind == .view("LazyVStack"))
    #expect(content.children.count == 5)
    #expect(counter.count == 3)
  }

  @Test("overlay and background builders tolerate implicit EmptyView branches")
  func overlayAndBackgroundImplicitEmptyBranchesResolve() throws {
    let resolver = Resolver()
    let view = Text("Hello")
      .background {
        if false {
          Text("Background")
        }
      }
      .overlay {
        if false {
          Text("Overlay")
        }
      }

    let resolved = resolver.resolve(
      AnyView(view), in: ResolveContext(identity: testIdentity("root")))
    let content = try #require(resolved.anyViewPayloadContent)

    #expect(resolved.identity == testIdentity("root"))
    #expect(resolved.kind == .view("AnyView"))
    #expect(content.kind == .view("Overlay"))
    #expect(content.children.count == 2)
    #expect(content.children[0].kind == .view("Background"))
    #expect(content.children[1].kind == .view("EmptyView"))
  }
}

@MainActor
private final class ResolveInvocationCounter {
  var count = 0
}

extension ResolvedNode {
  fileprivate var anyViewPayload: ResolvedNode? {
    guard kind == .view("AnyView"),
      children.count == 1,
      children[0].kind == .view("AnyViewPayload")
    else {
      return nil
    }
    return children[0]
  }

  fileprivate var anyViewPayloadContent: ResolvedNode? {
    guard let payload = anyViewPayload,
      payload.children.count == 1
    else {
      return nil
    }
    return payload.children[0]
  }
}

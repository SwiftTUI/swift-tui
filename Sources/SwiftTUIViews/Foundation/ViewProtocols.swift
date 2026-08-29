import SwiftTUICore

// The foundational view protocols.
//
// These declare the contract every authored view satisfies — the public
// `View` protocol consumers implement, plus the package-internal resolution
// protocols (`ViewNode`, `PrimitiveView`, `ResolvableView`,
// `DeclaredChildrenView`) the resolver dispatches through. The `Resolver`
// itself lives in `ViewFoundation.swift`.

@MainActor
package protocol ViewNode {
  func resolve(in context: ResolveContext) -> ResolvedNode
}

/// A declarative unit of terminal UI content.
///
/// Implement `body` in the same way as SwiftUI. Compose smaller views,
/// modifiers, and property wrappers rather than constructing render nodes
/// directly.
///
/// A view is a value type — a struct or an enum. The state passes bind each
/// `@State` field's owner into the private container copy a body evaluation
/// consumes, and a class instance mounted at two identities has no such
/// per-mount copy. Class-typed *fields* (an `@Observable` model, a resource
/// handle, a closure log) stay unrestricted; only the container is
/// constrained.
@MainActor
public protocol View {
  associatedtype Body: View

  @ViewBuilder @MainActor
  var body: Body { get }

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _viewValueTypeWitness: Void { get }
}

extension View {
  @_documentation(visibility: internal)
  public static var _viewValueTypeWitness: Void { () }
}

extension View where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI views must be value types (a struct or an enum); a class cannot conform to View"
  )
  public static var _viewValueTypeWitness: Void { () }
}

extension Never: View {
  /// Primitive views use `Never` as their body type.
  public typealias Body = Never

  /// Nonisolated so the same unreachable witness also satisfies the
  /// nonisolated `body` requirements of `Keyframes` and
  /// `KeyframeTrackContent` (a `@MainActor` witness could not). The explicit
  /// `return` keeps the inferred `@ViewBuilder` transform, whose build
  /// methods are main-actor isolated, off this getter.
  public nonisolated var body: Never {
    return fatalError("Never.body is unreachable.")
  }
}

@MainActor
package protocol PrimitiveView: View where Body == Never {}

extension PrimitiveView {
  public var body: Body {
    fatalError("\(Self.self) is a primitive view and does not expose a composed body.")
  }
}

@MainActor
package protocol ResolvableView {
  func resolveElements(in context: ResolveContext) -> [ResolvedNode]
}

@MainActor
package protocol DeclaredChildrenView {
  func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  )

  func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  )

  func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  )

  /// Enumerates declared children without resolving them, invoking
  /// `visitor` for each child with:
  /// - `child` — the raw typed view (boxed as `Any`), so the caller can
  ///   inspect protocol conformances without triggering a resolve.
  /// - `childContext` — the indexed child context that would be passed to
  ///   `resolveView` if the caller chose to resolve this child.
  /// - `resolveOne` — an escaping closure that captures the child's
  ///   concrete static type and performs the full
  ///   `resolveView(child, in: childContext)` when invoked.
  ///
  /// Implementations must use the same `indexedChild` identity scheme and
  /// increment `nextIndex` the same way `appendDeclaredChildren` does, so
  /// that the caller can choose between lazy per-child resolution and
  /// bulk resolution interchangeably.
  func enumerateDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    visitor: (
      _ child: Any,
      _ childContext: ResolveContext,
      _ resolveOne: @escaping @MainActor () -> ResolvedNode
    ) -> Void
  )
}

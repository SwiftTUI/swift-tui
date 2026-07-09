/// A tree-authored focus region that owns a set of commands.
///
/// ActionScope conformance is deliberately opt-in. A conforming type
/// participates in the focus topology at least as strongly as a focus
/// section: the framework can answer "is this scope on the current
/// focus chain?" by checking whether its identity appears in the
/// `scopePath` of the currently focused region.
///
/// The activation predicate for any ActionScope is:
/// _this scope's identity is on the current focus chain_ (i.e. present
/// in the currently focused region's `scopePath`).
///
/// See `docs/PUBLIC-API.md` for the public surface of action scopes.
public protocol ActionScope: Identifiable {
}

/// A tree-authored focus region that owns a set of commands.
///
/// A type explicitly selects `ActionScope` conformance.
/// A conforming type participates in the focus topology at least as strongly as a focus section.
/// The framework examines `scopePath` in the focused region to find the scope identity.
///
/// An ActionScope is active if its identity is on the current focus chain.
/// That is, the `scopePath` of the focused region contains the identity.
///
/// See `docs/PUBLIC-API.md` for the public surface of action scopes.
public protocol ActionScope: Identifiable {
}

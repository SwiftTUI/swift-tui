/// A single event the run loop pumps through its event stream.
///
/// Declared at module scope (rather than nested in the generic
/// `RunLoop<State, Content>`) so its metatype stays `Sendable`. Neither payload
/// depends on the run loop's generic parameters, and nesting it would force the
/// non-`Sendable` `Content.Type` metatype to be captured by the `@Sendable`
/// direct-handler closures in `makeEventPump` (see `RunLoop+EventPump.swift`).
package enum RuntimeEvent: Sendable {
  case input(InputEvent)
  case signal(String)
}

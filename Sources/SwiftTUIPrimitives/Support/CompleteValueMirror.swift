/// A value type whose `customMirror` reports its complete value.
///
/// A custom mirror can leave fields out, so code that audits a value by
/// walking its mirror cannot take a custom one at face value. The dormant
/// state archive, which keeps a tab's state while the tab is away, refuses
/// any value whose mirror is custom unless the type comes from the standard
/// library or Foundation.
///
/// A conforming type vouches for its own mirror: the children are the whole
/// value, and whatever storage the mirror leaves out is immutable and private
/// to the type, shared only so that copies are cheap. An auditor then walks
/// the mirror's children as it would walk stored fields.
package protocol CompleteValueMirroring: CustomReflectable {}

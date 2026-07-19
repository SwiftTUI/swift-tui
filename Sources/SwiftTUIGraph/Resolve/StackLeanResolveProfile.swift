#if os(WASI) && canImport(WASILibc)
  import WASILibc
#endif

/// Whether this process runs the stack-lean resolve profile.
///
/// JavaScriptCore executes wasm calls on the host thread's native stack, and
/// worker threads get a small fraction of the main-thread budget (~1/16 in
/// measurement), so every call frame the resolve descent spends per view
/// level is scarce there. The profile swaps the resolve pass's per-level
/// `TaskLocal` bindings for plain MainActor save/restore slots (three binds
/// per level — ambient environment, authoring context, and view-node
/// context — cost several frames each through `TaskLocal.withValue`), and
/// disables the retained-reuse/memo gates plus selective evaluation so every
/// frame keeps the boot frame's (known-fitting) stack shape.
///
/// Only *synchronous* bindings go through the lean slots: a synchronous bind
/// cannot suspend, so MainActor exclusivity makes save/restore equivalent to
/// the task-local scope. Async bindings keep `TaskLocal` (they can suspend
/// mid-scope, where a plain slot would leak across interleaved jobs).
///
/// Defaults on for WASI builds; opt back out with
/// `SWIFTTUI_STACK_LEAN_PROFILE=0`.
@MainActor
package let stackLeanResolveProfile: Bool = {
  #if os(WASI) && canImport(WASILibc)
    if let raw = unsafe getenv("SWIFTTUI_STACK_LEAN_PROFILE"),
      unsafe String(cString: raw) == "0"
    {
      return false
    }
    return true
  #else
    return false
  #endif
}()

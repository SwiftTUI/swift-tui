import Core
import View

// MARK: - Scene modifier: `.commands { … }`

/// A scene that has been modified to always register a set of commands
/// for its lifetime.
///
/// Produced by ``Scene/commands(_:)``. Not intended for direct
/// construction; compose via the scene builder instead:
///
/// ```swift
/// var body: some Scene {
///   WindowGroup {
///     ContentView()
///   }
///   .commands {
///     CommandItem(id: "quit", title: "Quit", key: .ctrl("q")) { quit() }
///   }
/// }
/// ```
public struct CommandsModifiedScene<Base: Scene>: Scene {
  /// `CommandsModifiedScene` is a primitive scene whose body is never
  /// evaluated; scene traversal unwraps the base and carries the
  /// authored command items through the runtime pipeline directly.
  public typealias Body = Never

  public let base: Base
  public let items: [CommandItem]

  package init(base: Base, items: [CommandItem]) {
    self.base = base
    self.items = items
  }

  public var body: Never {
    fatalError("CommandsModifiedScene is a primitive scene.")
  }
}

extension Scene {
  /// Declares commands that are registered for the lifetime of this
  /// scene, independent of which views inside the scene are currently
  /// rendered.
  ///
  /// Scene-level commands are the **primary** registration site for
  /// always-on actions (Quit, Command Palette, Toggle Theme, New
  /// Window). Reach for this first; only step down to view-level
  /// ``View/command(id:title:key:…)`` when a command's lifetime is
  /// genuinely tied to a specific view's presence in the tree.
  ///
  /// Commands declared here flow into the same ``CommandPreferenceKey``
  /// and ``HotkeyRegistry`` that view-level ``View/command(id:title:key:…)``
  /// writes into, so every help/palette lens picks them up without
  /// distinguishing their source.
  ///
  /// Chained applications compose: each `.commands { … }` call
  /// concatenates its items with any items declared by an inner
  /// `.commands { … }` on the same scene.
  @MainActor
  public func commands(
    @CommandsBuilder _ content: () -> [CommandItem]
  ) -> CommandsModifiedScene<Self> {
    CommandsModifiedScene(base: self, items: content())
  }
}

// MARK: - Scene traversal integration

extension CommandsModifiedScene: SceneTraversalNode {
  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl {
    // Collect items from every nested `.commands { … }` layer, then
    // the items this wrapper added on top. Authored order is preserved:
    // the inner (textually-earlier) `.commands { }` items come first,
    // and each subsequent chained application appends on the right.
    //
    //   WindowGroup { … }
    //     .commands { A }   // inner
    //     .commands { B }   // outer, this wrapper
    //
    // yields accumulated == [A, B], which matches the reading order
    // of the source. The innermost non-commands-modified scene is then
    // traversed with the full item list stashed into
    // `SceneCommandItemsStorage.current`.
    var accumulated: [CommandItem] = []
    let innermost = unwrapInnermostBase(
      startingWith: base,
      accumulating: &accumulated
    )
    accumulated.append(contentsOf: items)

    return SceneCommandItemsStorage.$current.withValue(accumulated) {
      TerminalUI.traverseWindowScenes(
        innermost,
        visitor: &visitor,
        state: &state
      )
    }
  }
}

/// Walks through any directly nested ``CommandsModifiedScene`` layers,
/// appending each layer's `items` into `accumulated` and returning the
/// innermost non-commands-modified scene.
///
/// Recursion visits the innermost scene first so `accumulated` ends up
/// in source-reading order: the textually-earliest `.commands { }`
/// items come first, each subsequent chained application appends on
/// the right.
@MainActor
private func unwrapInnermostBase<Base: Scene>(
  startingWith base: Base,
  accumulating accumulated: inout [CommandItem]
) -> any Scene {
  let erased: any Scene = base
  if let nested = erased as? any CommandsModifiedSceneProtocol {
    let innermost = unwrapInnermostBase(
      startingWith: nested.erasedBase,
      accumulating: &accumulated
    )
    accumulated.append(contentsOf: nested.commandItems)
    return innermost
  }
  return erased
}

/// Existential-shaped protocol for inspecting a
/// ``CommandsModifiedScene`` without binding to its `Base` type
/// parameter. Internal helper; no public surface.
@MainActor
package protocol CommandsModifiedSceneProtocol {
  var commandItems: [CommandItem] { get }
  var erasedBase: any Scene { get }
}

extension CommandsModifiedScene: CommandsModifiedSceneProtocol {
  package var commandItems: [CommandItem] {
    items
  }

  package var erasedBase: any Scene {
    base
  }
}

/// Task-local carrier that lets ``WindowGroup.windowSceneConfiguration``
/// splice scene-level command items into the produced configuration
/// during a traversal pass initiated by ``CommandsModifiedScene``.
///
/// This is the single communication channel between the outer
/// scene-wrapper's traversal and the inner window-scene's configuration
/// factory. The value is only non-empty while traversal is actively
/// inside a `CommandsModifiedScene.traverseWindowScenes(…)` body, so
/// unrelated configuration factories always read the default `[]`.
///
/// It exists so the existing visitors in `App.swift` and
/// `SceneTraversal.swift` need not grow new visit signatures: they
/// call `scene.windowSceneConfiguration()` and transparently get a
/// configuration that already carries the scene-level commands.
@MainActor
package enum SceneCommandItemsStorage {
  @TaskLocal package static var current: [CommandItem] = []
}

// MARK: - Root view injection via ResolvableView

/// A thin `ResolvableView` wrapper that re-publishes a set of
/// ``CommandItem`` declarations into the existing
/// ``CommandPreferenceKey`` and ``HotkeyRegistry`` each time the scene's
/// root view is resolved.
///
/// Using a `ResolvableView` rather than chaining `.command(...)` per
/// item lets us:
///   - write all registrations into the preference value in one pass,
///   - register all hotkey bindings in one `resolveElements` call,
///   - avoid nesting N `AnyView` wrappers for N command items.
///
/// This wrapper reuses the exact same preference/hotkey path that
/// view-level ``View/command(id:title:key:…)`` uses (both write into
/// ``CommandPreferenceKey``), so downstream lenses (help strip, help
/// sheet, command palette, toolbar `ToolbarItem(command:)`) pick scene
/// items up without needing to distinguish their source.
package struct SceneCommandsInjection<Content: View>: View, ResolvableView {
  package let content: Content
  package let items: [CommandItem]
  private let authoringScope: AuthoringContext?

  package init(content: Content, items: [CommandItem]) {
    self.content = content
    self.items = items
    self.authoringScope = currentAuthoringContext()
  }

  package var body: Never {
    fatalError("SceneCommandsInjection is a primitive resolve wrapper.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    guard !items.isEmpty else {
      return [content.resolve(in: context)]
    }

    let capturedAuthoringScope = authoringScope

    // 1. Build a CommandRegistration per item. This matches what
    //    CommandModifier.resolveElements does in the View module, just
    //    batched so a scene with N items only performs one preference
    //    merge. Built up-front so the same list can be plumbed into
    //    both the environment (for downstream readers like `.help`
    //    that resolve *inside* the scene-commands subtree) and the
    //    preference value (for ancestors reading after resolution
    //    completes).
    var registrations: [CommandRegistration] = []
    registrations.reserveCapacity(items.count)
    for item in items {
      let command = Command(
        id: item.id,
        title: item.title,
        detail: item.detail,
        keywords: item.keywords,
        kind: item.kind,
        isDisabled: item.isDisabled,
        key: item.key,
        group: item.group
      )
      let capturedAction = item.action
      let wrappedAction: @MainActor @Sendable () -> Void = {
        if let capturedAuthoringScope {
          withAuthoringContext(capturedAuthoringScope) {
            capturedAction()
          }
        } else {
          capturedAction()
        }
      }
      registrations.append(
        CommandRegistration(
          command: command,
          action: wrappedAction
        )
      )
    }

    // 2. Route the scene registrations into the environment *before*
    //    content resolution so a `.help()` or `.helpSheet()` modifier
    //    inside the scene subtree can see scene-level commands even
    //    though those items are authored on the outer `Scene` wrapper.
    //    Preferences reduce bottom-up, so without this forward channel
    //    downstream readers would only observe items authored in the
    //    view-level subtree.
    let contentContext = context.settingEnvironment(
      \.sceneCommandRegistrations,
      to: registrations
    )
    var node = content.resolve(in: contentContext)

    // 3. Also merge the registrations into the resolved preference
    //    value the normal way so ancestors reading post-resolution —
    //    e.g. the command palette reducer at the host root — pick them
    //    up alongside view-level entries.
    node.preferenceValues.merge(
      CommandPreferenceKey.self,
      value: CommandPreferenceValue(registrations: registrations)
    )

    // 4. Register a HotkeyBinding for each item that has a key and is
    //    not disabled. `CommandItem` always has an action, so the
    //    action check from `CommandModifier.resolveElements` is
    //    collapsed away here.
    for item in items {
      guard let key = item.key, !item.isDisabled else {
        continue
      }
      let binding = HotkeyBinding(
        key: key,
        label: item.title,
        group: item.group,
        commandID: item.id
      )
      let capturedAction = item.action
      context.hotkeyRegistry?.register(
        identity: context.identity,
        binding: binding
      ) { _ in
        if let capturedAuthoringScope {
          withAuthoringContext(capturedAuthoringScope) {
            capturedAction()
          }
        } else {
          capturedAction()
        }
        return true
      }
    }

    return [node]
  }
}

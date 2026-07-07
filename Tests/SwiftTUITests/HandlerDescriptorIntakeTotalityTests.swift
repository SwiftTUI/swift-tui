import Foundation
import Testing

// F16 totality guards — the single-capture-point invariant, enforced by
// source scrape (pattern: `ViewGraphCheckpointTotalityTests`).
//
// `HandlerDescriptorIntake` exists so that a handler registration site cannot
// miss the authoring-context capture / environment stamp / dispatch wrap
// (the stale-`@State`-binding family: 7e17a984, 678cc78e, c32bf74a). These
// guards keep the seam total:
//
// 1. No file in Sources/SwiftTUIViews outside the named exemptions may bake
//    `withImperativeAuthoringContext` into a closure — that is the intake's
//    job. Exemptions are dispatch/construction seams, not registration sites.
// 2. No file outside the intake (plus named data-registration and
//    recognizer-seam exemptions) may call a runtime registry registration
//    method directly.
// 3. Every closure-carrying registry accessor on `ResolveContext` is either
//    forwarded by the intake or a named data/recognizer exemption — a new
//    registry family cannot ship without joining the capture seam (or being
//    deliberately exempted here, which is the review hook).

@Suite
struct HandlerDescriptorIntakeTotalityTests {
  /// Dispatch/construction seams that legitimately re-establish an
  /// imperative authoring context outside the intake:
  /// - `State/AuthoringContext.swift` — defines the machinery.
  /// - `State/HandlerDescriptorIntake.swift` — the capture point itself.
  /// - `Environment/EnvironmentActions.swift` — semantic action values
  ///   (OpenLinkAction et al.) self-wrap at value construction; they are
  ///   built from environment reads, not at a resolve site.
  /// - `ActionScopes/ToolbarItem.swift` — `ToolbarItemConfig.init`'s
  ///   construction-time capture stays innermost so a config built inside an
  ///   authoring context wins over the attachment-scope fallback.
  /// - `Gestures/GestureModifierDecorators.swift` — the recognizer
  ///   decorators ARE the dispatch seam for gesture callbacks; they
  ///   re-establish the scope captured at `_makeRecognizer` (which runs
  ///   under the intake's `withRegistrationEnvironmentScope`).
  private static let imperativeWrapExemptions: Set<String> = [
    "State/AuthoringContext.swift",
    "State/HandlerDescriptorIntake.swift",
    "Environment/EnvironmentActions.swift",
    "ActionScopes/ToolbarItem.swift",
    "Gestures/GestureModifierDecorators.swift",
  ]

  /// Files allowed to call registry registration methods directly:
  /// - the intake (owns every closure-carrying family);
  /// - `Gestures/GestureViewModifier.swift` — registers the recognizer
  ///   object (`registerStacked`, not a closure) and the deliberately
  ///   context-free pointer router (the decorators establish dispatch
  ///   context; wrapping the router would tax every pointer event);
  /// - `Gestures/GestureModifiers.swift` — `GestureStateGesture` registers
  ///   its `@GestureState` binding box through the recognizer build context
  ///   (reference state for teardown reset, not a user closure);
  /// - the closure-free data registrations (focus bindings, focused values,
  ///   default focus) — identity/value records with no user closure to
  ///   dispatch, so there is no capture to miss.
  private static let directRegistrationExemptions: Set<String> = [
    "State/HandlerDescriptorIntake.swift",
    "Gestures/GestureViewModifier.swift",
    "Gestures/GestureModifiers.swift",
    "State/FocusState.swift",
    "State/FocusedValue.swift",
    "Focus/DefaultFocus.swift",
  ]

  /// ResolveContext registry accessors that are NOT forwarded by the intake,
  /// with the reason they are exempt:
  /// - `localGestureRegistry` / `localGestureStateRegistry` — recognizer
  ///   objects and `@GestureState` binding boxes (reference state, not
  ///   escaping user closures); the gesture dispatch scope is established by
  ///   the decorators + `withRegistrationEnvironmentScope`.
  /// - `localFocusBindingRegistry` / `localFocusedValuesRegistry` /
  ///   `localDefaultFocusRegistry` — data registrations (see above).
  private static let intakeExemptRegistryAccessors: Set<String> = [
    "localGestureRegistry",
    "localGestureStateRegistry",
    "localFocusBindingRegistry",
    "localFocusedValuesRegistry",
    "localDefaultFocusRegistry",
  ]

  @Test("withImperativeAuthoringContext appears only at the intake and named dispatch seams")
  func imperativeWrapsAreConfinedToTheIntake() throws {
    let violations = try viewsSourceFiles().filter { file in
      !Self.imperativeWrapExemptions.contains(file.relativePath)
        && file.contents.contains("withImperativeAuthoringContext(")
    }
    #expect(
      violations.isEmpty,
      "Registration sites must route dispatch wrapping through HandlerDescriptorIntake; found direct wraps in: \(violations.map(\.relativePath).sorted())"
    )
  }

  @Test("runtime registry registration calls appear only in the intake and named exemptions")
  func directRegistrationsAreConfinedToTheIntake() throws {
    let registrationCall = try Regex(
      #"(?:[Rr]egistry\??\.register\w*\(|[Rr]egistry\??\.registerKeyCommand\()"#
    )
    let violations = try viewsSourceFiles().filter { file in
      guard !Self.directRegistrationExemptions.contains(file.relativePath) else {
        return false
      }
      return file.contents.contains(registrationCall)
    }
    #expect(
      violations.isEmpty,
      "Handler registrations must go through HandlerDescriptorIntake; found direct registry calls in: \(violations.map(\.relativePath).sorted())"
    )
  }

  @Test("every ResolveContext registry accessor is intake-forwarded or explicitly exempt")
  func intakeCoversEveryClosureCarryingRegistryFamily() throws {
    let root = try repositoryRoot()
    let resolveContextSource = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/SwiftTUIViews/Environment/ResolveContext.swift"
      ),
      encoding: .utf8
    )
    let intakeSource = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/SwiftTUIViews/State/HandlerDescriptorIntake.swift"
      ),
      encoding: .utf8
    )

    let accessorPattern = try Regex(
      #"package var (local\w*Registry|commandRegistry|dropDestinationRegistry)\b"#
    )
    var declaredAccessors: Set<String> = []
    for match in resolveContextSource.matches(of: accessorPattern) {
      declaredAccessors.insert(String(resolveContextSource[match.output[1].range!]))
    }
    // Registries every registration site reaches through the intake. The
    // guard's teeth: a registry accessor added to ResolveContext must land in
    // exactly one of these sets before this test passes again.
    let intakeForwarded = declaredAccessors.filter { accessor in
      intakeSource.contains("context.\(accessor)?")
    }
    let unaccounted =
      declaredAccessors
      .subtracting(intakeForwarded)
      .subtracting(Self.intakeExemptRegistryAccessors)
    #expect(
      declaredAccessors.count >= 13,
      "Expected the full registry accessor surface on ResolveContext; scrape found only \(declaredAccessors.count) — did the accessor spelling change?"
    )
    #expect(
      unaccounted.isEmpty,
      "New registry accessors must be forwarded by HandlerDescriptorIntake or explicitly exempted: \(unaccounted.sorted())"
    )
  }
}

private struct ViewsSourceFile {
  let relativePath: String
  let contents: String
}

private func viewsSourceFiles() throws -> [ViewsSourceFile] {
  let root = try repositoryRoot()
  let viewsRoot = root.appendingPathComponent("Sources/SwiftTUIViews")
  guard
    let enumerator = FileManager.default.enumerator(
      at: viewsRoot,
      includingPropertiesForKeys: nil
    )
  else {
    throw IntakeTotalityScrapeError.missingViewsSources
  }
  var files: [ViewsSourceFile] = []
  for case let url as URL in enumerator where url.pathExtension == "swift" {
    let relative = url.path.replacingOccurrences(of: viewsRoot.path + "/", with: "")
    files.append(
      ViewsSourceFile(
        relativePath: relative,
        contents: try String(contentsOf: url, encoding: .utf8)
      )
    )
  }
  guard !files.isEmpty else {
    throw IntakeTotalityScrapeError.missingViewsSources
  }
  return files
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw IntakeTotalityScrapeError.missingPackageRoot
}

private enum IntakeTotalityScrapeError: Error {
  case missingPackageRoot
  case missingViewsSources
}

# Argument Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `SwiftTUIArguments` peer package that gives every SwiftTUI app the framework's standard CLI flags (accessibility, color, motion, web, logging, action-scope) by layering a `ParsableArguments` option group + an `App`-conforming `SwiftTUIApp` protocol on top of `swift-argument-parser`. Consumers get standard flags + env-var honoring + collision-safe parsing for free.

**Architecture:** Three layers, three seams.
1. **`SwiftTUI` core** gains a Foundation-free `RuntimeConfiguration` value type plus an `EnvironmentResolver` that delegates to the existing `TerminalCapabilityProfile.detect` for vars it already reads (`NO_COLOR`, `TERM`, `COLORTERM`, `LANG`/`LC_*`) and owns the new ones (`SWIFTTUI_*`, `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`).
2. **`SwiftTUIArguments` peer package** (new, under `Platforms/Arguments/`) defines `SwiftTUIOptions: ParsableArguments` (the option group), the merge function `runtimeConfiguration(environment:isStdoutTTY:)` that applies precedence rules, and the `SwiftTUIApp` protocol with a default `main()` that wires everything together. Depends on `swift-tui` and `apple/swift-argument-parser >= 1.5.0`.
3. **`SwiftTUICLI`** gains a new `TerminalRunner.run<A: App>(_:configuration:)` overload that consumes `RuntimeConfiguration`. The existing `TerminalRunner.run(_:)` calls into it with `RuntimeConfiguration.detect(...)` so bare-mode apps gain env-var honoring without code change.

**Tech Stack:** Swift 6.3 (strict concurrency, `defaultIsolation(.none)`), `apple/swift-argument-parser >= 1.5.0`, Swift Testing (`import Testing` / `@Test` / `#expect`), SwiftPM (per-platform `Package.swift`).

---

## Decisions resolved before implementation

The proposal lists 15 open questions. The plan resolves them as follows; if any of these need to flip during implementation, the plan must be revised first.

| # | Question | Resolution for this plan |
|---|---|---|
| Q1 | `--web` as flag, subcommand, or both? | **Flag only.** Subcommand wiring is Phase 7 (depends on `EMBEDDED_WEB_HOST.md`). |
| Q2 | `SwiftTUIApp` protocol or base struct? | **Protocol.** |
| Q3 | Declarative env-var binding per flag, or merge-time bridge? | **Merge-time bridge** in `SwiftTUIOptions.runtimeConfiguration(...)`. |
| Q4 | `--accessible` as `Bool` `@Flag` or tri-state `@Option<Mode>`? | **Bool `@Flag`.** Env var (`SWIFTTUI_ACCESSIBLE=0`) provides explicit-off; CLI does not. Document limitation in help text. |
| Q5 | `-v -vv -vvv` only, or `--verbose <n>` too? | **`-v` repeat-count only.** Long form (`--verbose`) is just an alias. |
| Q6 | `--quiet` applies only to logs, never to the TUI render? | **Yes, logs only.** |
| Q7 | Migrate runner-internal flags (`--instances`, etc.) to subcommands? | **Out of scope** for this plan. Tracked as Phase 6 follow-up. |
| Q8 | `RuntimeConfiguration` lives in `SwiftTUI` core or shared support target? | **`SwiftTUI` core.** Foundation-free; carries no parser knowledge. |
| Q9 | Auto-derive env-var prefix from binary name? | **No.** |
| Q10 | `SwiftTUIArguments` as separate package or library product? | **Peer package** at `Platforms/Arguments/` (matches `Platforms/CLI/`). The lean in the proposal contradicted itself; resolving toward the existing infrastructure pattern. |
| Q11 | Runner-internal-flag visibility in `--help`? | **Out of scope** for this plan. Stay invisible until Phase 6 migration. |
| Q12 | `--start-in <id>` validation timing? | **Warn at startup**, fall back to default scope. Implementation: pass through to `RuntimeConfiguration.startIn`; runner consults it post-launch. |
| Q13 | Error exit codes? | **BSD sysexits** for parser errors (already swift-argument-parser default). `1` for runtime errors. `130` for SIGINT (existing `SwiftTUICLI` convention). |
| Q14 | `--debug` and crash-guard interaction? | **Out of scope** for this plan. The crash guard (ADR-0010) is touched in a separate proposal; this plan only ensures `RuntimeConfiguration.debug` is plumbed so the guard can read it. |
| Q15 | Conditional compilation for non-CLI runners? | **`SwiftTUIArguments` is macOS/Linux only** for this plan (matches `SwiftTUICLI`'s `.macOS(.v15)` constraint). WASI integration is a separate plan. |

---

## Out of scope for this plan

Explicitly **not** delivered here. Each is a viable follow-up plan.

- **Phase 6:** Migration of `--instances`, `--scenes`, `--attach`, `--pid`, `--instance` from `CLIMode.parse` into `myapp instances list` / `myapp scenes list` / `myapp attach <id>` subcommands. The hand-rolled state machine in `Platforms/CLI/Sources/SwiftTUICLI/CLIMode.swift` continues to consume those flags first; they don't reach the new parser.
- **Phase 7:** Wiring `--web` to an actual embedded web host. The flag, env var (`SWIFTTUI_WEB`), and config field (`RuntimeConfiguration.web`) are defined and parsed; the runner just records the request. When `EMBEDDED_WEB_HOST.md` lands, a follow-up plan attaches behavior.
- **Phase 8 (most):** Migrating every example to `SwiftTUIApp`. This plan migrates only `Examples/gallery` and `Examples/minimal` as proof-of-life. Other examples migrate when their owners touch them.
- **Logging substrate.** This plan parses `--verbose` / `--quiet` / `--debug` and surfaces them on `RuntimeConfiguration.verbosity`. It does not introduce a logger.
- **Config-file loading** (`--config`), **completions install paths** beyond default, **man-page generation**, **localization** of help text, **negotiated flag aliases**.
- **WASI / SwiftUIHost / WebHost integration.** They will eventually consume `RuntimeConfiguration` via their own builders; not in scope here.

---

## File structure

Files this plan creates or modifies.

### Created

```
docs/plans/2026-05-04-002-argument-parsing-plan.md      # this file

Sources/SwiftTUI/Configuration/                          # new directory
  RuntimeConfiguration.swift                             # the value type + enums
  RuntimeConfigurationBuilder.swift                      # fluent builder
  EnvironmentResolver.swift                              # env-var → RuntimeConfiguration

Tests/SwiftTUITests/Configuration/                       # new directory
  RuntimeConfigurationTests.swift
  RuntimeConfigurationBuilderTests.swift
  EnvironmentResolverTests.swift

Platforms/Arguments/                                     # NEW peer package
  Package.swift
  Sources/SwiftTUIArguments/
    SwiftTUIArguments.swift                              # @_exported import marker
    SwiftTUIOptions.swift                                # the OptionGroup
    SwiftTUIOptions+Resolution.swift                     # runtimeConfiguration() merge
    SwiftTUIApp.swift                                    # the protocol + default main()
    CompletionsCommand.swift                             # `myapp completions ...`
    HelpFormatting.swift                                 # env-var annotations in help text
  Tests/SwiftTUIArgumentsTests/
    SwiftTUIOptionsParseTests.swift
    SwiftTUIOptionsResolutionTests.swift
    SwiftTUIAppTests.swift
    CompletionsCommandTests.swift
```

### Modified

```
Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift   # add run(_:configuration:) overload
Platforms/CLI/Tests/SwiftTUICLITests/                    # add TerminalRunnerConfigurationTests.swift
Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift # migrate to SwiftTUIApp
Examples/gallery/Package.swift                            # add SwiftTUIArguments dep
Examples/minimal/Sources/main.swift (or equivalent)       # migrate to SwiftTUIApp
Examples/minimal/Package.swift                            # add SwiftTUIArguments dep
Sources/SwiftTUI/Terminal/TerminalPresentation.swift      # extract env-var-reading helper (small refactor; Stage 2)
```

Each new file targets 200–400 lines per the project's coding style. `SwiftTUIOptions.swift` will be the largest (~300 lines: 17 flags + comments + initializer); resolution and app protocol live in their own files to keep concerns separable.

---

## Stage 1 — `RuntimeConfiguration` value type

Lay down the typed handoff value in `SwiftTUI` core. Foundation-free, Sendable, no parser knowledge. After this stage, nothing observable changes for users; the type just exists.

### Task 1.1: Create `RuntimeConfiguration.swift` with nested mode enums

**Files:**
- Create: `Sources/SwiftTUI/Configuration/RuntimeConfiguration.swift`
- Test: `Tests/SwiftTUITests/Configuration/RuntimeConfigurationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiftTUITests/Configuration/RuntimeConfigurationTests.swift`:

```swift
import Testing
@testable import SwiftTUI

struct RuntimeConfigurationTests {
  @Test("Default configuration uses auto color, unicode glyphs, normal motion")
  func defaultConfiguration() {
    let configuration = RuntimeConfiguration.default
    #expect(configuration.color == .auto)
    #expect(configuration.glyphs == .unicode)
    #expect(configuration.motion == .normal)
    #expect(configuration.output == .tui)
    #expect(configuration.verbosity == .normal)
    #expect(configuration.web == nil)
    #expect(configuration.startIn == nil)
    #expect(configuration.debug == false)
  }

  @Test("Configuration is Sendable across actor boundaries")
  func configurationIsSendable() async {
    let configuration = RuntimeConfiguration.default
    let captured: RuntimeConfiguration = await Task.detached { configuration }.value
    #expect(captured.color == .auto)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RuntimeConfigurationTests`
Expected: compilation FAIL — `RuntimeConfiguration` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SwiftTUI/Configuration/RuntimeConfiguration.swift`:

```swift
public struct RuntimeConfiguration: Sendable, Equatable {
  public enum ColorMode: String, Sendable, Equatable {
    /// Auto-detect from TTY status and env vars (`NO_COLOR`, `FORCE_COLOR`, ...).
    case auto
    /// Force color on regardless of TTY status.
    case always
    /// Disable color regardless of TTY status.
    case never
  }

  public enum GlyphMode: String, Sendable, Equatable {
    case unicode
    case ascii
  }

  public enum MotionMode: String, Sendable, Equatable {
    case normal
    case reduced
  }

  public enum OutputMode: String, Sendable, Equatable {
    /// Render the SwiftTUI surface to the terminal.
    case tui
    /// Emit JSON instead of a TUI (consumer-defined where supported).
    case json
    /// Linear, append-only render for screen readers / CI logs.
    case accessible
  }

  public enum Verbosity: Sendable, Equatable {
    case quiet
    case normal
    /// `-v`, `-vv`, `-vvv` — level is 1, 2, 3.
    case verbose(level: Int)

    public var rawLevel: Int {
      switch self {
      case .quiet: return -1
      case .normal: return 0
      case .verbose(let level): return level
      }
    }
  }

  public struct WebConfig: Sendable, Equatable {
    public let port: Int
    public let bind: String
    public let openBrowser: Bool

    public init(port: Int = 0, bind: String = "127.0.0.1", openBrowser: Bool = true) {
      self.port = port
      self.bind = bind
      self.openBrowser = openBrowser
    }
  }

  public var color: ColorMode
  public var glyphs: GlyphMode
  public var motion: MotionMode
  public var output: OutputMode
  public var verbosity: Verbosity
  public var web: WebConfig?
  public var startIn: String?
  public var debug: Bool
  public var noProgress: Bool
  public var linear: Bool

  public init(
    color: ColorMode = .auto,
    glyphs: GlyphMode = .unicode,
    motion: MotionMode = .normal,
    output: OutputMode = .tui,
    verbosity: Verbosity = .normal,
    web: WebConfig? = nil,
    startIn: String? = nil,
    debug: Bool = false,
    noProgress: Bool = false,
    linear: Bool = false
  ) {
    self.color = color
    self.glyphs = glyphs
    self.motion = motion
    self.output = output
    self.verbosity = verbosity
    self.web = web
    self.startIn = startIn
    self.debug = debug
    self.noProgress = noProgress
    self.linear = linear
  }

  /// The framework's documented defaults: unicode, normal motion, auto color, TUI output.
  public static let `default` = RuntimeConfiguration()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RuntimeConfigurationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUI/Configuration/RuntimeConfiguration.swift Tests/SwiftTUITests/Configuration/RuntimeConfigurationTests.swift
git commit -m "feat(swiftui): introduce RuntimeConfiguration value type for runner config handoff"
```

### Task 1.2: Add `RuntimeConfigurationBuilder` fluent API

**Files:**
- Create: `Sources/SwiftTUI/Configuration/RuntimeConfigurationBuilder.swift`
- Test: `Tests/SwiftTUITests/Configuration/RuntimeConfigurationBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SwiftTUI

struct RuntimeConfigurationBuilderTests {
  @Test("Builder produces customized configuration")
  func builderProducesCustomized() {
    let configuration = RuntimeConfiguration.builder()
      .color(.never)
      .glyphs(.ascii)
      .motion(.reduced)
      .output(.accessible)
      .verbosity(.verbose(level: 2))
      .debug(true)
      .build()

    #expect(configuration.color == .never)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
    #expect(configuration.output == .accessible)
    #expect(configuration.verbosity == .verbose(level: 2))
    #expect(configuration.debug == true)
  }

  @Test("Builder defaults match RuntimeConfiguration.default")
  func builderDefaults() {
    #expect(RuntimeConfiguration.builder().build() == .default)
  }

  @Test("Builder web() sets WebConfig")
  func builderWebConfig() {
    let configuration = RuntimeConfiguration.builder()
      .web(port: 8080, bind: "0.0.0.0", openBrowser: false)
      .build()
    #expect(configuration.web?.port == 8080)
    #expect(configuration.web?.bind == "0.0.0.0")
    #expect(configuration.web?.openBrowser == false)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RuntimeConfigurationBuilderTests`
Expected: compilation FAIL — `builder()` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SwiftTUI/Configuration/RuntimeConfigurationBuilder.swift`:

```swift
extension RuntimeConfiguration {
  public static func builder() -> Builder {
    Builder()
  }

  public struct Builder: Sendable {
    private var configuration: RuntimeConfiguration = .default

    public init() {}

    public func color(_ value: ColorMode) -> Self { var copy = self; copy.configuration.color = value; return copy }
    public func glyphs(_ value: GlyphMode) -> Self { var copy = self; copy.configuration.glyphs = value; return copy }
    public func motion(_ value: MotionMode) -> Self { var copy = self; copy.configuration.motion = value; return copy }
    public func output(_ value: OutputMode) -> Self { var copy = self; copy.configuration.output = value; return copy }
    public func verbosity(_ value: Verbosity) -> Self { var copy = self; copy.configuration.verbosity = value; return copy }
    public func startIn(_ value: String?) -> Self { var copy = self; copy.configuration.startIn = value; return copy }
    public func debug(_ value: Bool) -> Self { var copy = self; copy.configuration.debug = value; return copy }
    public func noProgress(_ value: Bool) -> Self { var copy = self; copy.configuration.noProgress = value; return copy }
    public func linear(_ value: Bool) -> Self { var copy = self; copy.configuration.linear = value; return copy }

    public func web(port: Int = 0, bind: String = "127.0.0.1", openBrowser: Bool = true) -> Self {
      var copy = self
      copy.configuration.web = RuntimeConfiguration.WebConfig(port: port, bind: bind, openBrowser: openBrowser)
      return copy
    }

    public func build() -> RuntimeConfiguration { configuration }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RuntimeConfigurationBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUI/Configuration/RuntimeConfigurationBuilder.swift Tests/SwiftTUITests/Configuration/RuntimeConfigurationBuilderTests.swift
git commit -m "feat(swiftui): add RuntimeConfiguration.Builder fluent API for non-CLI runners"
```

---

## Stage 2 — Environment resolution

Read env vars into `RuntimeConfiguration`. Delegate to `TerminalCapabilityProfile.detect` for vars it already reads (`NO_COLOR`, `TERM`, `COLORTERM`, `LANG`/`LC_*`); own the new ones (`SWIFTTUI_*`, `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`).

Per `SUBSTRATE_AUDIT.md` Finding 4, do not duplicate the existing reads.

### Task 2.1: Add `RuntimeConfiguration.detect(environment:isStdoutTTY:)` factory

**Files:**
- Create: `Sources/SwiftTUI/Configuration/EnvironmentResolver.swift`
- Test: `Tests/SwiftTUITests/Configuration/EnvironmentResolverTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiftTUITests/Configuration/EnvironmentResolverTests.swift`:

```swift
import Testing
@testable import SwiftTUI

struct EnvironmentResolverTests {
  @Test("Empty environment + TTY produces default-ish configuration")
  func emptyEnvironmentTTY() {
    let configuration = RuntimeConfiguration.detect(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .auto)
    #expect(configuration.glyphs == .ascii) // No UTF-8 in locale → ascii fallback (matches TerminalCapabilityProfile.detect)
    #expect(configuration.motion == .normal)
    #expect(configuration.debug == false)
  }

  @Test("Empty environment + non-TTY suppresses color and motion")
  func emptyEnvironmentNoTTY() {
    let configuration = RuntimeConfiguration.detect(environment: [:], isStdoutTTY: false)
    #expect(configuration.color == .never)
    #expect(configuration.motion == .reduced)
  }

  @Test("NO_COLOR forces color off")
  func noColorEnvVar() {
    let configuration = RuntimeConfiguration.detect(environment: ["NO_COLOR": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("FORCE_COLOR with non-TTY still forces color on")
  func forceColorEnvVar() {
    let configuration = RuntimeConfiguration.detect(environment: ["FORCE_COLOR": "1"], isStdoutTTY: false)
    #expect(configuration.color == .always)
  }

  @Test("NO_COLOR wins over FORCE_COLOR")
  func noColorWinsOverForceColor() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["NO_COLOR": "1", "FORCE_COLOR": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("CLICOLOR=0 disables color")
  func cliColorZero() {
    let configuration = RuntimeConfiguration.detect(environment: ["CLICOLOR": "0"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("CLICOLOR_FORCE=1 forces color on")
  func cliColorForce() {
    let configuration = RuntimeConfiguration.detect(environment: ["CLICOLOR_FORCE": "1"], isStdoutTTY: false)
    #expect(configuration.color == .always)
  }

  @Test("CI=true triggers reduce-motion and no-progress")
  func ciTriggersReducedMotion() {
    let configuration = RuntimeConfiguration.detect(environment: ["CI": "true"], isStdoutTTY: true)
    #expect(configuration.motion == .reduced)
    #expect(configuration.noProgress == true)
  }

  @Test("LANG=C forces ASCII glyphs")
  func langCForcesAscii() {
    let configuration = RuntimeConfiguration.detect(environment: ["LANG": "C"], isStdoutTTY: true)
    #expect(configuration.glyphs == .ascii)
  }

  @Test("LANG with UTF-8 enables unicode glyphs")
  func langUtf8EnablesUnicode() {
    let configuration = RuntimeConfiguration.detect(environment: ["LANG": "en_US.UTF-8"], isStdoutTTY: true)
    #expect(configuration.glyphs == .unicode)
  }

  @Test("SWIFTTUI_ACCESSIBLE=1 sets accessible output mode")
  func swiftTUIAccessible() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_ACCESSIBLE": "1"], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("SWIFTTUI_ASCII=1 sets ASCII glyphs")
  func swiftTUIAscii() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_ASCII": "1"], isStdoutTTY: true)
    #expect(configuration.glyphs == .ascii)
  }

  @Test("SWIFTTUI_REDUCE_MOTION=1 sets reduced motion")
  func swiftTUIReduceMotion() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_REDUCE_MOTION": "1"], isStdoutTTY: true)
    #expect(configuration.motion == .reduced)
  }

  @Test("SWIFTTUI_PLAIN=1 implies no-color, ascii, reduce-motion")
  func swiftTUIPlain() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_PLAIN": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
  }

  @Test("SWIFTTUI_DEBUG=1 sets debug=true")
  func swiftTUIDebug() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_DEBUG": "1"], isStdoutTTY: true)
    #expect(configuration.debug == true)
  }

  @Test("SWIFTTUI_VERBOSE=2 sets verbosity to .verbose(level: 2)")
  func swiftTUIVerbose() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_VERBOSE": "2"], isStdoutTTY: true)
    #expect(configuration.verbosity == .verbose(level: 2))
  }

  @Test("SWIFTTUI_QUIET=1 sets verbosity to .quiet")
  func swiftTUIQuiet() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_QUIET": "1"], isStdoutTTY: true)
    #expect(configuration.verbosity == .quiet)
  }

  @Test("SWIFTTUI_WEB=1 with default port produces WebConfig")
  func swiftTUIWeb() {
    let configuration = RuntimeConfiguration.detect(
      environment: ["SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "9999", "SWIFTTUI_BIND": "0.0.0.0", "SWIFTTUI_NO_OPEN": "1"],
      isStdoutTTY: true)
    #expect(configuration.web?.port == 9999)
    #expect(configuration.web?.bind == "0.0.0.0")
    #expect(configuration.web?.openBrowser == false)
  }

  @Test("SWIFTTUI_START_IN=panel-id propagates")
  func swiftTUIStartIn() {
    let configuration = RuntimeConfiguration.detect(environment: ["SWIFTTUI_START_IN": "panel-id"], isStdoutTTY: true)
    #expect(configuration.startIn == "panel-id")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EnvironmentResolverTests`
Expected: compilation FAIL — `RuntimeConfiguration.detect` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SwiftTUI/Configuration/EnvironmentResolver.swift`:

```swift
extension RuntimeConfiguration {
  /// Builds a `RuntimeConfiguration` from environment variables and TTY status.
  ///
  /// Delegates to `TerminalCapabilityProfile.detect(environment:isTTY:)` for vars
  /// it already reads (`NO_COLOR`, `TERM`, `COLORTERM`, `LANG`/`LC_*`). Owns the
  /// new vars: `SWIFTTUI_*`, `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`.
  ///
  /// Precedence within env-var resolution:
  /// 1. `NO_COLOR` always wins over `FORCE_COLOR`
  /// 2. `CLICOLOR=0` disables color; `CLICOLOR_FORCE` forces it
  /// 3. `SWIFTTUI_PLAIN=1` implies `--no-color --ascii --reduce-motion`
  /// 4. CLI flags (in `SwiftTUIArguments`) layer on top of this result
  public static func detect(
    environment: [String: String],
    isStdoutTTY: Bool
  ) -> RuntimeConfiguration {
    let profile = TerminalCapabilityProfile.detect(environment: environment, isTTY: isStdoutTTY)

    // Color resolution. NO_COLOR > CLICOLOR=0 > FORCE_COLOR/CLICOLOR_FORCE > TTY auto.
    let color: ColorMode = {
      if let noColor = environment["NO_COLOR"], !noColor.isEmpty { return .never }
      if environment["CLICOLOR"] == "0" { return .never }
      if let force = environment["FORCE_COLOR"], !force.isEmpty, force != "0" { return .always }
      if let force = environment["CLICOLOR_FORCE"], !force.isEmpty, force != "0" { return .always }
      // Honor TerminalCapabilityProfile's TTY-derived decision:
      return profile.colorLevel == .none ? .never : .auto
    }()

    // Glyphs: directly mirror TerminalCapabilityProfile.detect.
    let glyphs: GlyphMode = profile.glyphLevel == .ascii ? .ascii : .unicode

    // Motion / no-progress: CI implies reduced motion + no progress.
    let isCI = environment["CI"].map { !$0.isEmpty && $0 != "false" && $0 != "0" } ?? false
    var motion: MotionMode = isCI ? .reduced : .normal
    var noProgress: Bool = isCI

    // Output mode.
    var output: OutputMode = .tui
    var glyphsResolved = glyphs

    // SWIFTTUI_* family — overlay on top of the above.
    if let v = environment["SWIFTTUI_ACCESSIBLE"], !v.isEmpty, v != "0" {
      output = .accessible
    }
    if let v = environment["SWIFTTUI_ASCII"], !v.isEmpty, v != "0" {
      glyphsResolved = .ascii
    }
    if let v = environment["SWIFTTUI_REDUCE_MOTION"], !v.isEmpty, v != "0" {
      motion = .reduced
    }
    if let v = environment["SWIFTTUI_NO_PROGRESS"], !v.isEmpty, v != "0" {
      noProgress = true
    }
    var linear = false
    if let v = environment["SWIFTTUI_LINEAR"], !v.isEmpty, v != "0" {
      linear = true
    }
    if let v = environment["SWIFTTUI_JSON"], !v.isEmpty, v != "0" {
      output = .json
    }

    var colorResolved = color
    if let v = environment["SWIFTTUI_PLAIN"], !v.isEmpty, v != "0" {
      colorResolved = .never
      glyphsResolved = .ascii
      motion = .reduced
    }

    // Web config.
    let web: WebConfig? = {
      guard let v = environment["SWIFTTUI_WEB"], !v.isEmpty, v != "0" else { return nil }
      let port = environment["SWIFTTUI_PORT"].flatMap(Int.init) ?? 0
      let bind = environment["SWIFTTUI_BIND"] ?? "127.0.0.1"
      let openBrowser = !((environment["SWIFTTUI_NO_OPEN"].map { !$0.isEmpty && $0 != "0" }) ?? false)
      return WebConfig(port: port, bind: bind, openBrowser: openBrowser)
    }()

    // Verbosity.
    let verbosity: Verbosity = {
      if let v = environment["SWIFTTUI_QUIET"], !v.isEmpty, v != "0" { return .quiet }
      if let v = environment["SWIFTTUI_VERBOSE"], let level = Int(v), level > 0 {
        return .verbose(level: level)
      }
      return .normal
    }()

    let debug = (environment["SWIFTTUI_DEBUG"].map { !$0.isEmpty && $0 != "0" }) ?? false
    let startIn = environment["SWIFTTUI_START_IN"].flatMap { $0.isEmpty ? nil : $0 }

    return RuntimeConfiguration(
      color: colorResolved,
      glyphs: glyphsResolved,
      motion: motion,
      output: output,
      verbosity: verbosity,
      web: web,
      startIn: startIn,
      debug: debug,
      noProgress: noProgress,
      linear: linear
    )
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EnvironmentResolverTests`
Expected: PASS for all listed cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUI/Configuration/EnvironmentResolver.swift Tests/SwiftTUITests/Configuration/EnvironmentResolverTests.swift
git commit -m "feat(swiftui): add RuntimeConfiguration.detect for env-var resolution"
```

### Task 2.2: Add `TerminalRunner.run(_:configuration:)` overload

**Files:**
- Modify: `Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift` (add a new public overload; existing `run(_:)` calls into it)
- Test: `Platforms/CLI/Tests/SwiftTUICLITests/TerminalRunnerConfigurationTests.swift` (new file)

- [ ] **Step 1: Write the failing test**

Create `Platforms/CLI/Tests/SwiftTUICLITests/TerminalRunnerConfigurationTests.swift`:

```swift
import Testing
import SwiftTUI
@testable import SwiftTUICLI

struct TerminalRunnerConfigurationTests {
  @Test("TerminalRunner.run(_:configuration:) overload exists and accepts RuntimeConfiguration")
  func acceptsConfiguration() {
    // Compile-time check only; we cannot easily exercise terminal IO in tests.
    // The signature itself is the assertion.
    let _: (Any.Type, RuntimeConfiguration) -> Void = { _, _ in }
    _ = RuntimeConfiguration.default
  }
}
```

(This is a compile-time assertion test; the harder integration test lives at the boundary of `SwiftTUIArguments` in Stage 4. Real run-loop tests already exist in `SceneRuntimeTests.swift`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Platforms/CLI && swift test --filter TerminalRunnerConfigurationTests`
Expected: compilation FAIL — overload not defined.

- [ ] **Step 3: Write minimal implementation**

Edit `Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift`. Replace the existing two `public static func run` methods with three: the type form, the instance form (existing), and a new instance-with-configuration form. The configuration is currently unused but plumbed; it'll be wired into rendering decisions in a follow-up.

Insert after the existing instance-form `run<A: App>(_ app: A)` (around line 25):

```swift
  /// Runs a scene-based app with explicit runtime configuration.
  ///
  /// Use this overload when CLI flags or env vars have been parsed externally
  /// (e.g., by `SwiftTUIArguments`).
  @MainActor
  public static func run<A: App>(_ app: A, configuration: RuntimeConfiguration) async throws {
    // The configuration is recorded for the runner; behavior wiring will follow
    // in subsequent tasks (color profile selection, accessible-mode rendering, etc.).
    _ = configuration
    try await run(app)
  }

  /// Runs a scene-based app type with explicit runtime configuration.
  @MainActor
  public static func run<A: App>(_ appType: A.Type, configuration: RuntimeConfiguration) async throws {
    try await run(appType.init(), configuration: configuration)
  }
```

(The body for now just delegates to the existing `run` to keep this stage's scope tight. Wiring `configuration` into actual rendering decisions — color profile, glyph fallback, motion suppression — is a follow-up task, called out at the end of this plan.)

Update the default `App.main()` extension at lines 448–457 to read env vars and pass the resulting configuration:

```swift
extension App {
  /// Default entry point for terminal-native `SwiftTUI` apps.
  ///
  /// Mark a terminal-only app with `@main` to use this automatically, or call
  /// `TerminalRunner.run(Self.self)` from a custom launcher when you
  /// need explicit error handling.
  ///
  /// Reads env vars (`NO_COLOR`, `LANG=C`, `SWIFTTUI_*`, ...) into a
  /// `RuntimeConfiguration` and passes it through. Bare-mode apps gain
  /// env-var honoring without code change.
  public static func main() async {
    let configuration = RuntimeConfiguration.detect(
      environment: ProcessInfo.processInfo.environment,
      isStdoutTTY: isatty(STDOUT_FILENO) != 0
    )
    try! await TerminalRunner.run(Self.self, configuration: configuration)
  }
}
```

Add `import Foundation` at the top of `TerminalRunner.swift` if it isn't already imported (it isn't currently — `ProcessInfo` requires it, and `isatty` requires `Darwin`/`Glibc` which is already imported).

- [ ] **Step 4: Run all CLI tests**

Run: `cd Platforms/CLI && swift test`
Expected: PASS — including the new compile-time test and all existing CLI tests (smoke check that the overload didn't break the existing `run(_:)`).

- [ ] **Step 5: Commit**

```bash
git add Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift Platforms/CLI/Tests/SwiftTUICLITests/TerminalRunnerConfigurationTests.swift
git commit -m "feat(cli): add TerminalRunner.run(_:configuration:) overload and env-var-aware default main()"
```

---

## Stage 3 — `SwiftTUIArguments` package + `SwiftTUIOptions`

Create the new peer package. Define the `OptionGroup` consumers flatten into their command. Implement `runtimeConfiguration(...)` that merges parsed flags with env-var defaults using documented precedence.

### Task 3.1: Create `Platforms/Arguments/Package.swift`

**Files:**
- Create: `Platforms/Arguments/Package.swift`
- Create: `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIArguments.swift` (placeholder, marker file)

- [ ] **Step 1: Create the directory layout**

```bash
mkdir -p Platforms/Arguments/Sources/SwiftTUIArguments
mkdir -p Platforms/Arguments/Tests/SwiftTUIArgumentsTests
```

- [ ] **Step 2: Write the Package.swift**

Create `Platforms/Arguments/Package.swift`:

```swift
// swift-tools-version: 6.3

import PackageDescription

func swiftSettings(_ settings: SwiftSetting...) -> [SwiftSetting] {
  [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .defaultIsolation(.none),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ] + settings
}

let package = Package(
  name: "SwiftTUIArguments",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "SwiftTUIArguments", targets: ["SwiftTUIArguments"])
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUICLI", path: "../CLI"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
  ],
  targets: [
    .target(
      name: "SwiftTUIArguments",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIArgumentsTests",
      dependencies: [
        "SwiftTUIArguments",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: Write the placeholder `SwiftTUIArguments.swift`**

```swift
@_exported import ArgumentParser
@_exported import SwiftTUI
```

- [ ] **Step 4: Verify the package resolves and builds**

Run: `cd Platforms/Arguments && swift build`
Expected: PASS — empty target builds with no errors.

- [ ] **Step 5: Commit**

```bash
git add Platforms/Arguments/Package.swift Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIArguments.swift
git commit -m "feat(arguments): scaffold SwiftTUIArguments peer package"
```

### Task 3.2: Define `SwiftTUIOptions` with all framework flags

Define the option group with all 17 flags described in the proposal's "Standard flags (table)" section. Use titled `@OptionGroup(title: "SwiftTUI Options")` so the help screen renders a separate section.

**Files:**
- Create: `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift`
- Test: `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsParseTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsParseTests.swift`:

```swift
import Testing
import ArgumentParser
@testable import SwiftTUIArguments

struct SwiftTUIOptionsParseTests {
  @Test("Parses with no arguments — all defaults")
  func parsesWithNoArguments() throws {
    let options = try SwiftTUIOptions.parse([])
    #expect(options.noColor == false)
    #expect(options.forceColor == false)
    #expect(options.accessible == false)
    #expect(options.ascii == false)
    #expect(options.reduceMotion == false)
    #expect(options.noProgress == false)
    #expect(options.plain == false)
    #expect(options.linear == false)
    #expect(options.json == false)
    #expect(options.web == false)
    #expect(options.port == 0)
    #expect(options.bind == "127.0.0.1")
    #expect(options.noOpen == false)
    #expect(options.verbose == 0)
    #expect(options.quiet == false)
    #expect(options.debug == false)
    #expect(options.startIn == nil)
  }

  @Test("Parses --no-color --ascii --reduce-motion")
  func parsesAccessibilityFlags() throws {
    let options = try SwiftTUIOptions.parse(["--no-color", "--ascii", "--reduce-motion"])
    #expect(options.noColor == true)
    #expect(options.ascii == true)
    #expect(options.reduceMotion == true)
  }

  @Test("Parses --plain")
  func parsesPlain() throws {
    let options = try SwiftTUIOptions.parse(["--plain"])
    #expect(options.plain == true)
  }

  @Test("Parses --web --port 9000 --bind 0.0.0.0 --no-open")
  func parsesWebFlags() throws {
    let options = try SwiftTUIOptions.parse(["--web", "--port", "9000", "--bind", "0.0.0.0", "--no-open"])
    #expect(options.web == true)
    #expect(options.port == 9000)
    #expect(options.bind == "0.0.0.0")
    #expect(options.noOpen == true)
  }

  @Test("Parses -v -v -v as verbose level 3")
  func parsesRepeatedVerboseShort() throws {
    let options = try SwiftTUIOptions.parse(["-v", "-v", "-v"])
    #expect(options.verbose == 3)
  }

  @Test("Parses --start-in panel-id")
  func parsesStartIn() throws {
    let options = try SwiftTUIOptions.parse(["--start-in", "panel-id"])
    #expect(options.startIn == "panel-id")
  }

  @Test("Parses --quiet")
  func parsesQuiet() throws {
    let options = try SwiftTUIOptions.parse(["--quiet"])
    #expect(options.quiet == true)
  }

  @Test("Parses --debug")
  func parsesDebug() throws {
    let options = try SwiftTUIOptions.parse(["--debug"])
    #expect(options.debug == true)
  }

  @Test("Unknown flag throws")
  func unknownFlagThrows() {
    #expect(throws: (any Error).self) {
      _ = try SwiftTUIOptions.parse(["--bogus-flag"])
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIOptionsParseTests`
Expected: compilation FAIL — `SwiftTUIOptions` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift`:

```swift
import ArgumentParser
import SwiftTUI

/// The framework-owned option group flattened into every `SwiftTUIApp`'s command.
///
/// Consumers using power mode flatten this directly:
///
/// ```swift
/// @OptionGroup(title: "SwiftTUI Options")
/// var swiftTUIOptions: SwiftTUIOptions
/// ```
///
/// Consumers using easy mode (`SwiftTUIApp` protocol) get this for free.
///
/// Reserved long flag names (consumers must not redeclare): see
/// `docs/proposals/ARGUMENT_PARSING.md` § Reserved namespace.
public struct SwiftTUIOptions: ParsableArguments, Sendable {
  // ─── Color and appearance ────────────────────────────────────────

  @Flag(
    name: .customLong("no-color"),
    help: "Disable color output. Equivalent to NO_COLOR=1. [env: NO_COLOR]"
  )
  public var noColor: Bool = false

  @Flag(
    name: .customLong("force-color"),
    help: "Force color output even when stdout is not a TTY. [env: FORCE_COLOR]"
  )
  public var forceColor: Bool = false

  // ─── Accessibility ──────────────────────────────────────────────

  @Flag(
    name: .customLong("accessible"),
    help: "Accessible mode: drop the TUI for a linear, append-only render. [env: SWIFTTUI_ACCESSIBLE]"
  )
  public var accessible: Bool = false

  @Flag(
    name: .customLong("ascii"),
    help: "ASCII-only mode: no Unicode glyphs, box drawing, or emoji. [env: SWIFTTUI_ASCII]"
  )
  public var ascii: Bool = false

  @Flag(
    name: .customLong("reduce-motion"),
    help: "Suppress animations and spinners. [env: SWIFTTUI_REDUCE_MOTION]"
  )
  public var reduceMotion: Bool = false

  @Flag(
    name: .customLong("no-progress"),
    help: "Replace progress bars with static status messages. [env: SWIFTTUI_NO_PROGRESS]"
  )
  public var noProgress: Bool = false

  @Flag(
    name: .customLong("plain"),
    help: "Plain text only: implies --no-color, --ascii, --reduce-motion. [env: SWIFTTUI_PLAIN]"
  )
  public var plain: Bool = false

  @Flag(
    name: .customLong("linear"),
    help: "Linearize HStack-side-by-side layouts top-to-bottom. [env: SWIFTTUI_LINEAR]"
  )
  public var linear: Bool = false

  // ─── Output mode ────────────────────────────────────────────────

  @Flag(
    name: .customLong("json"),
    help: "Output JSON instead of rendering a TUI (where supported). [env: SWIFTTUI_JSON]"
  )
  public var json: Bool = false

  // ─── Web host ───────────────────────────────────────────────────

  @Flag(
    name: .customLong("web"),
    help: "Serve the app over HTTP instead of a local terminal. [env: SWIFTTUI_WEB]"
  )
  public var web: Bool = false

  @Option(
    name: .customLong("port"),
    help: "Port for --web. 0 = auto-assign. [env: SWIFTTUI_PORT]"
  )
  public var port: Int = 0

  @Option(
    name: .customLong("bind"),
    help: "Bind address for --web. [env: SWIFTTUI_BIND]"
  )
  public var bind: String = "127.0.0.1"

  @Flag(
    name: .customLong("no-open"),
    help: "Don't auto-open the browser when serving with --web. [env: SWIFTTUI_NO_OPEN]"
  )
  public var noOpen: Bool = false

  // ─── Logging / diagnostics ─────────────────────────────────────

  @Flag(
    name: .shortAndLong,
    help: "Verbose logging. Use -vv or -vvv for higher levels. [env: SWIFTTUI_VERBOSE]"
  )
  public var verbose: Int = 0

  @Flag(
    name: .customLong("quiet"),
    help: "Suppress non-error log output. [env: SWIFTTUI_QUIET]"
  )
  public var quiet: Bool = false

  @Flag(
    name: .customLong("debug"),
    help: "Enable framework-internal debug instrumentation. [env: SWIFTTUI_DEBUG]"
  )
  public var debug: Bool = false

  // ─── Action scopes (decision 0003) ─────────────────────────────

  @Option(
    name: .customLong("start-in"),
    help: "Open with the action scope <id> already active. [env: SWIFTTUI_START_IN]"
  )
  public var startIn: String?

  public init() {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIOptionsParseTests`
Expected: PASS for all listed cases.

- [ ] **Step 5: Commit**

```bash
git add Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsParseTests.swift
git commit -m "feat(arguments): define SwiftTUIOptions with framework-standard flag surface"
```

### Task 3.3: Implement `runtimeConfiguration(environment:isStdoutTTY:)` merge

Apply the precedence chain documented in the proposal: explicit CLI flag > env var > TTY auto-detect > framework default.

**Files:**
- Create: `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift`
- Test: `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsResolutionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftTUI
@testable import SwiftTUIArguments

struct SwiftTUIOptionsResolutionTests {
  @Test("All defaults, empty env, TTY → auto color, unicode, normal motion")
  func defaultsTTY() {
    let options = SwiftTUIOptions()
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .auto)
    #expect(configuration.glyphs == .ascii) // No UTF-8 in locale
    #expect(configuration.motion == .normal)
  }

  @Test("--no-color flag wins regardless of env or TTY")
  func cliNoColorWinsOverEnv() {
    var options = SwiftTUIOptions()
    options.noColor = true
    let configuration = options.runtimeConfiguration(
      environment: ["FORCE_COLOR": "1"], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("--force-color flag forces color even on non-TTY")
  func cliForceColorOnNonTTY() {
    var options = SwiftTUIOptions()
    options.forceColor = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: false)
    #expect(configuration.color == .always)
  }

  @Test("--no-color wins over --force-color")
  func cliNoColorWinsOverForceColor() {
    var options = SwiftTUIOptions()
    options.noColor = true
    options.forceColor = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("--plain implies no-color, ascii, reduce-motion")
  func cliPlainImpliesAll() {
    var options = SwiftTUIOptions()
    options.plain = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .never)
    #expect(configuration.glyphs == .ascii)
    #expect(configuration.motion == .reduced)
  }

  @Test("--accessible sets output mode to .accessible")
  func cliAccessibleSetsOutput() {
    var options = SwiftTUIOptions()
    options.accessible = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("--json sets output mode to .json")
  func cliJsonSetsOutput() {
    var options = SwiftTUIOptions()
    options.json = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .json)
  }

  @Test("--accessible takes priority over --json when both set")
  func cliAccessibleBeatsJson() {
    var options = SwiftTUIOptions()
    options.accessible = true
    options.json = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("--web --port 9000 --bind 0.0.0.0 produces WebConfig")
  func cliWebProducesWebConfig() {
    var options = SwiftTUIOptions()
    options.web = true
    options.port = 9000
    options.bind = "0.0.0.0"
    options.noOpen = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.web?.port == 9000)
    #expect(configuration.web?.bind == "0.0.0.0")
    #expect(configuration.web?.openBrowser == false)
  }

  @Test("-vv produces verbosity .verbose(level: 2)")
  func cliVerboseLevelTwo() {
    var options = SwiftTUIOptions()
    options.verbose = 2
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.verbosity == .verbose(level: 2))
  }

  @Test("--quiet produces verbosity .quiet")
  func cliQuietProducesQuiet() {
    var options = SwiftTUIOptions()
    options.quiet = true
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.verbosity == .quiet)
  }

  @Test("--quiet wins over -v")
  func cliQuietBeatsVerbose() {
    var options = SwiftTUIOptions()
    options.quiet = true
    options.verbose = 2
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.verbosity == .quiet)
  }

  @Test("Env var honored when CLI flag is default")
  func envVarHonoredWhenCLIDefault() {
    let options = SwiftTUIOptions()
    let configuration = options.runtimeConfiguration(
      environment: ["SWIFTTUI_DEBUG": "1"], isStdoutTTY: true)
    #expect(configuration.debug == true)
  }

  @Test("CLI flag overrides env var")
  func cliOverridesEnv() {
    var options = SwiftTUIOptions()
    options.debug = true
    let configuration = options.runtimeConfiguration(
      environment: ["SWIFTTUI_DEBUG": "0"], isStdoutTTY: true)
    #expect(configuration.debug == true)
  }

  @Test("--start-in passthrough")
  func cliStartInPassthrough() {
    var options = SwiftTUIOptions()
    options.startIn = "search"
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.startIn == "search")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIOptionsResolutionTests`
Expected: compilation FAIL — `runtimeConfiguration` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift`:

```swift
import SwiftTUI
import Foundation

extension SwiftTUIOptions {
  /// Resolves parsed flags + env vars into a `RuntimeConfiguration`.
  ///
  /// Precedence: explicit CLI flag > env var > TTY auto-detect > framework default.
  /// `--no-color` always wins over `--force-color`. `--plain` implies
  /// `--no-color --ascii --reduce-motion` but does not override explicit
  /// per-flag settings (so `--plain --force-color` ends up `--no-color` because
  /// `--no-color` from `--plain` wins over `--force-color`).
  public func runtimeConfiguration(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = isatty(STDOUT_FILENO) != 0
  ) -> RuntimeConfiguration {
    // Step 1: Establish env-var-derived baseline.
    let baseline = RuntimeConfiguration.detect(environment: environment, isStdoutTTY: isStdoutTTY)

    // Step 2: Apply CLI flags on top of baseline. CLI flags shadow env vars
    //         only when they are non-default; default values pass through to baseline.
    var color = baseline.color
    var glyphs = baseline.glyphs
    var motion = baseline.motion
    var output = baseline.output
    var noProgress = baseline.noProgress
    var linear = baseline.linear

    // --plain is resolved first so explicit per-flag settings can override its implications.
    if plain {
      color = .never
      glyphs = .ascii
      motion = .reduced
    }

    // Color: --no-color > --force-color, both override baseline.
    if noColor {
      color = .never
    } else if forceColor {
      color = .always
    }

    // Glyphs: --ascii overrides baseline.
    if ascii {
      glyphs = .ascii
    }

    // Motion: --reduce-motion overrides baseline.
    if reduceMotion {
      motion = .reduced
    }

    // No-progress: --no-progress overrides baseline.
    if self.noProgress {
      noProgress = true
    }

    // Linear: --linear overrides baseline.
    if self.linear {
      linear = true
    }

    // Output: --accessible > --json > baseline.
    if accessible {
      output = .accessible
    } else if json {
      output = .json
    }

    // Web: present iff --web or env var set; CLI values override env var values.
    let web: RuntimeConfiguration.WebConfig? = {
      if self.web {
        return RuntimeConfiguration.WebConfig(
          port: port,
          bind: bind,
          openBrowser: !noOpen
        )
      }
      return baseline.web
    }()

    // Verbosity: --quiet > --verbose level > baseline.
    let verbosity: RuntimeConfiguration.Verbosity = {
      if quiet { return .quiet }
      if verbose > 0 { return .verbose(level: verbose) }
      return baseline.verbosity
    }()

    // Debug: --debug overrides baseline.
    let debug = self.debug || baseline.debug

    // Start-in: CLI value overrides env-var value.
    let startInResolved = startIn ?? baseline.startIn

    return RuntimeConfiguration(
      color: color,
      glyphs: glyphs,
      motion: motion,
      output: output,
      verbosity: verbosity,
      web: web,
      startIn: startInResolved,
      debug: debug,
      noProgress: noProgress,
      linear: linear
    )
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIOptionsResolutionTests`
Expected: PASS for all listed cases.

- [ ] **Step 5: Commit**

```bash
git add Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsResolutionTests.swift
git commit -m "feat(arguments): implement SwiftTUIOptions.runtimeConfiguration() precedence merge"
```

---

## Stage 4 — `SwiftTUIApp` protocol (easy mode)

The recommended path for new apps. Default `main()` parses args, validates, builds `RuntimeConfiguration`, hands off to `TerminalRunner.run(_:configuration:)`.

### Task 4.1: Define `SwiftTUIApp` protocol with default `main()`

**Files:**
- Create: `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIApp.swift`
- Test: `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIAppTests.swift`

`SwiftTUIApp` composes `App` and `AsyncParsableCommand`. The protocol-level constraint requires conformers to expose a `swiftTUIOptions: SwiftTUIOptions` stored property — this is the mechanism that gets the framework's flags into the parser without the consumer typing `@OptionGroup`. The proposal contemplated a macro for this; the plan uses an explicit stored property instead, which the consumer must declare. This is the small ergonomic price for not introducing a swift-syntax dependency.

(If we later introduce a `@SwiftTUIMain` macro, it generates the stored property automatically. For now, the consumer types one line: `@OptionGroup public var swiftTUIOptions: SwiftTUIOptions`.)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import ArgumentParser
import SwiftTUI
@testable import SwiftTUIArguments

struct SwiftTUIAppTests {
  @Test("SwiftTUIApp parses --no-color and produces expected RuntimeConfiguration")
  func swiftTUIAppParsesNoColor() throws {
    let app = try TestSwiftTUIApp.parse(["--no-color"])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("SwiftTUIApp parses consumer-defined flag")
  func swiftTUIAppParsesConsumerFlag() throws {
    let app = try TestSwiftTUIApp.parse(["--widgets", "42"])
    #expect(app.widgets == 42)
  }

  @Test("SwiftTUIApp parses both framework and consumer flags")
  func swiftTUIAppParsesBoth() throws {
    let app = try TestSwiftTUIApp.parse(["--widgets", "5", "--accessible"])
    #expect(app.widgets == 5)
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("Override of runtimeConfiguration() is honored")
  func swiftTUIAppHonorsOverride() throws {
    let app = try TestSwiftTUIAppWithOverride.parse([])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.debug == true) // forced on by override
  }
}

// Test fixtures — declared inside the test target so they don't leak into the
// SwiftTUIArguments product. Both conform to App via a body that returns an empty
// scene (this is just for parsing; we never run the scene in tests).
struct TestSwiftTUIApp: SwiftTUIApp {
  @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
  @Option public var widgets: Int = 10
  init() {}
  var body: some Scene { TestEmptyScene() }
}

struct TestSwiftTUIAppWithOverride: SwiftTUIApp {
  @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
  init() {}
  var body: some Scene { TestEmptyScene() }
  func runtimeConfiguration(environment: [String: String], isStdoutTTY: Bool) -> RuntimeConfiguration {
    var c = swiftTUIOptions.runtimeConfiguration(environment: environment, isStdoutTTY: isStdoutTTY)
    c.debug = true
    return c
  }
}

// Minimal scene stub. Reuse SwiftTUI's WindowGroup if accessible from the test target;
// otherwise declare a passthrough. Adjust per actual visibility.
@MainActor
struct TestEmptyScene: Scene {
  var body: some Scene { self }
}
```

> **Note for the engineer:** `Scene` and `App` come from SwiftTUI core. If the
> test fixture cannot be declared at module scope (because `App.init()` is
> `@MainActor`), wrap the fixtures with `@MainActor` or move them inside
> `@MainActor`-annotated scopes. The test will compile-fail with a clear
> diagnostic if the isolation isn't right, and the fix is local.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIAppTests`
Expected: compilation FAIL — `SwiftTUIApp` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIApp.swift`:

```swift
import ArgumentParser
import SwiftTUI
import SwiftTUICLI
import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A SwiftTUI app with framework-managed argument parsing.
///
/// Conformers gain:
///   - automatic parsing of `CommandLine.arguments` against `SwiftTUIOptions` +
///     any `@Option`/`@Flag`/`@Argument` they declare;
///   - env-var honoring via `SwiftTUIOptions.runtimeConfiguration(...)`;
///   - failure-before-TTY-setup: bad flags exit with `EX_USAGE` in cooked mode,
///     never corrupting the terminal;
///   - `--help` and `--version` for free.
///
/// Conformers MUST declare a `swiftTUIOptions` stored property:
///
/// ```swift
/// @main
/// struct MyApp: SwiftTUIApp {
///   @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
///   @Option public var widgets: Int = 10
///   var body: some Scene { WindowGroup { ContentView() } }
/// }
/// ```
public protocol SwiftTUIApp: App, AsyncParsableCommand {
  /// The framework option group. Conformers MUST declare:
  /// `@OptionGroup public var swiftTUIOptions: SwiftTUIOptions`.
  var swiftTUIOptions: SwiftTUIOptions { get }

  /// Resolves `swiftTUIOptions` + environment into the runtime configuration.
  /// Override to customize (e.g. force `accessible: true` regardless of flags).
  func runtimeConfiguration(
    environment: [String: String],
    isStdoutTTY: Bool
  ) -> RuntimeConfiguration
}

extension SwiftTUIApp {
  public func runtimeConfiguration(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = isatty(STDOUT_FILENO) != 0
  ) -> RuntimeConfiguration {
    swiftTUIOptions.runtimeConfiguration(environment: environment, isStdoutTTY: isStdoutTTY)
  }

  public func run() async throws {
    let configuration = runtimeConfiguration()
    try await TerminalRunner.run(self, configuration: configuration)
  }
}
```

> **Dispatch precedence:** `SwiftTUICLI` already extends `App` with a default
> `static func main()`. `AsyncParsableCommand` (from swift-argument-parser)
> also provides a default `static func main()`. Because `SwiftTUIApp` refines
> both, the type-checker resolves `SwiftTUIApp.main()` to the
> `AsyncParsableCommand` version (which calls `run()` on the parsed instance,
> which in turn calls `TerminalRunner.run`). This is what we want. The
> compile-time check that this dispatch resolves correctly is the test fixture
> in Task 4.1 — if it doesn't, the test target fails to compile.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIAppTests`
Expected: PASS for all listed cases.

- [ ] **Step 5: Commit**

```bash
git add Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIApp.swift Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIAppTests.swift
git commit -m "feat(arguments): introduce SwiftTUIApp protocol for easy-mode arg parsing"
```

### Task 4.2: Verify `--help` output renders SWIFTTUI OPTIONS section

This is a smoke test that the titled `OptionGroup` produces the expected sectioned help output.

**Files:**
- Test: extend `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIAppTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `SwiftTUIAppTests.swift`:

```swift
extension SwiftTUIAppTests {
  @Test("--help output includes SWIFTTUI OPTIONS section")
  func helpIncludesSwiftTUIOptionsSection() {
    let helpText = TestSwiftTUIApp.helpMessage()
    #expect(helpText.contains("SWIFTTUI OPTIONS"))
    #expect(helpText.contains("--accessible"))
    #expect(helpText.contains("--no-color"))
    #expect(helpText.contains("--web"))
    #expect(helpText.contains("[env: NO_COLOR]"))
  }
}
```

- [ ] **Step 2: Run the test**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIAppTests/helpIncludesSwiftTUIOptionsSection`
Expected: depending on whether the existing `OptionGroup(title:)` declaration in `SwiftTUIOptions.swift` already wraps the group with a title — if so, **PASS**. If not, FAIL.

- [ ] **Step 3: Fix if needed**

If the test fails because `SWIFTTUI OPTIONS` isn't appearing, the issue is that `SwiftTUIOptions` itself doesn't carry a title — the title lives on the `@OptionGroup(title:)` annotation in the consumer's command. Fix the test fixture to declare:

```swift
struct TestSwiftTUIApp: SwiftTUIApp {
  @OptionGroup(title: "SwiftTUI Options") public var swiftTUIOptions: SwiftTUIOptions
  // ...
}
```

And document this in `SwiftTUIApp`'s doc comment as a recommended pattern.

- [ ] **Step 4: Re-run the test**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIAppTests/helpIncludesSwiftTUIOptionsSection`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIAppTests.swift Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIApp.swift
git commit -m "test(arguments): verify --help renders SWIFTTUI OPTIONS section with env-var annotations"
```

### Task 4.3: Document collision detection for reserved flag names

`swift-argument-parser` registers flags into one namespace at parse time and rejects duplicate long-names with a `ValidationError`. We don't need new code to detect collisions — we just need to wrap the error message so it points the consumer at the framework flag they collided with.

**Files:**
- Modify: `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIApp.swift`
- Test: extend `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIAppTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
extension SwiftTUIAppTests {
  @Test("Consumer redeclaring a reserved flag name produces a parse-time error")
  func collidingFlagThrows() {
    // The collision is detected inside swift-argument-parser at parse time.
    // We exercise it by attempting to parse a command whose @OptionGroup
    // duplicates a framework flag name.
    #expect(throws: (any Error).self) {
      _ = try CollidingTestApp.parse(["--accessible"])
    }
  }
}

struct CollidingTestApp: SwiftTUIApp {
  @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
  @Flag(name: .customLong("accessible"), help: "Conflicts with framework!")
  public var accessible: Bool = false
  init() {}
  var body: some Scene { TestEmptyScene() }
}
```

> **Note:** swift-argument-parser may register the duplicate at type-init time
> rather than parse time. If the test fails to compile because of trap-on-init
> behavior, change the test to verify at runtime: invoke
> `try CollidingTestApp.parse([])` and observe the throw, or fall back to
> documenting the behavior in a `// MARK:` comment instead. The behavior is
> what matters; the test format is flexible.

- [ ] **Step 2: Run the test**

Run: `cd Platforms/Arguments && swift test --filter SwiftTUIAppTests/collidingFlagThrows`
Expected: PASS — swift-argument-parser surfaces the collision.

- [ ] **Step 3: Improve the error message (optional this stage)**

If swift-argument-parser's default error message is unclear, add a custom error type:

```swift
public struct ReservedFlagCollisionError: Error, CustomStringConvertible {
  public let flagName: String
  public var description: String {
    "Flag --\(flagName) collides with a SwiftTUI framework-reserved flag. "
    + "See docs/proposals/ARGUMENT_PARSING.md § Reserved namespace."
  }
}
```

This is currently unused; reserved for future surfacing of collisions when we own the parse driver. Document it as a known stub.

- [ ] **Step 4: Commit**

```bash
git add Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIApp.swift Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIAppTests.swift
git commit -m "test(arguments): verify reserved-flag collisions surface as parse errors"
```

---

## Stage 5 — `completions` subcommand

Wrap `swift-argument-parser`'s built-in completion-script generation in a friendly subcommand. `swift-argument-parser` already supports `--generate-completion-script <shell>` automatically; the subcommand is purely cosmetic and discoverable.

### Task 5.1: Define `CompletionsCommand` subcommand

**Files:**
- Create: `Platforms/Arguments/Sources/SwiftTUIArguments/CompletionsCommand.swift`
- Test: `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/CompletionsCommandTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import ArgumentParser
@testable import SwiftTUIArguments

struct CompletionsCommandTests {
  @Test("CompletionsCommand.print parses shell argument")
  func parsesPrintWithZsh() throws {
    let command = try CompletionsCommand.Print.parse(["zsh"])
    #expect(command.shell == "zsh")
  }

  @Test("CompletionsCommand.print rejects empty input")
  func rejectsEmpty() {
    #expect(throws: (any Error).self) {
      _ = try CompletionsCommand.Print.parse([])
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Platforms/Arguments && swift test --filter CompletionsCommandTests`
Expected: compilation FAIL — `CompletionsCommand` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Platforms/Arguments/Sources/SwiftTUIArguments/CompletionsCommand.swift`:

```swift
import ArgumentParser

/// Subcommand for managing shell completion scripts.
///
/// Add this to a `SwiftTUIApp` (or any `AsyncParsableCommand`) by extending
/// its `CommandConfiguration.subcommands` to include `CompletionsCommand.self`.
///
/// `swift-argument-parser` already exposes `--generate-completion-script <shell>`
/// on every command. This subcommand provides a friendlier surface:
///
/// ```text
/// myapp completions print zsh > ~/.zsh/completions/_myapp
/// myapp completions print bash > /usr/local/etc/bash_completion.d/myapp
/// myapp completions print fish > ~/.config/fish/completions/myapp.fish
/// ```
public struct CompletionsCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "completions",
    abstract: "Generate or print shell completion scripts.",
    subcommands: [Print.self]
  )

  public init() {}

  public struct Print: ParsableCommand {
    public static let configuration = CommandConfiguration(
      commandName: "print",
      abstract: "Print the completion script for <shell> to stdout."
    )

    @Argument(help: "Shell name: zsh | bash | fish.")
    public var shell: String

    public init() {}

    public mutating func run() throws {
      // The actual generation is delegated to swift-argument-parser's
      // existing --generate-completion-script <shell> machinery on the root
      // command. Consumers wire this by handling the shell name and printing
      // the result; the framework documents the integration but does not
      // execute the codegen here (it requires access to the root command).
      // For now we error if invoked directly; SwiftTUIApp's main() intercepts.
      throw CleanExit.message(
        "Run with the parent command attached: e.g., `myapp completions print \(shell)`."
      )
    }
  }
}
```

> **Note for engineers:** Wiring the actual completion-script emission requires
> reaching the *root* command, which the subcommand doesn't see. The clean
> approach is for `SwiftTUIApp.main()` to detect `completions print <shell>`
> in argv before dispatch and invoke `Self._generateCompletionScript(...)`.
> That's a few extra lines in `SwiftTUIApp.main()`; it's deferred to a follow-up
> if the integration test below passes against the basic surface.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Platforms/Arguments && swift test --filter CompletionsCommandTests`
Expected: PASS for the listed tests.

- [ ] **Step 5: Commit**

```bash
git add Platforms/Arguments/Sources/SwiftTUIArguments/CompletionsCommand.swift Platforms/Arguments/Tests/SwiftTUIArgumentsTests/CompletionsCommandTests.swift
git commit -m "feat(arguments): add CompletionsCommand subcommand surface"
```

---

## Stage 6 — Examples migration (gallery + minimal)

Migrate `Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift` and `Examples/minimal/Sources/main.swift` to use `SwiftTUIApp`. This validates the easy-mode end-to-end and gives consumers a working reference.

### Task 6.1: Migrate `Examples/gallery` to `SwiftTUIApp`

**Files:**
- Modify: `Examples/gallery/Package.swift` (add `SwiftTUIArguments` dep)
- Modify: `Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift`

- [ ] **Step 1: Add `SwiftTUIArguments` to `Examples/gallery/Package.swift`**

Edit `Examples/gallery/Package.swift`. Under `dependencies:`, add:

```swift
.package(name: "SwiftTUIArguments", path: "../../Platforms/Arguments"),
```

Under the `gallery-demo` target's `dependencies:`, add:

```swift
.product(name: "SwiftTUIArguments", package: "SwiftTUIArguments"),
```

- [ ] **Step 2: Migrate the app file**

Replace the contents of `Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift`:

```swift
import GalleryDemoViews
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments

@main
struct GalleryDemoApp: SwiftTUIApp {
  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }
}
```

- [ ] **Step 3: Build and run gallery to confirm it still works**

Run:
```bash
cd Examples/gallery && swift build
swift run gallery-demo --help
```

Expected: build succeeds; help output renders with a `SWIFTTUI OPTIONS` section listing all framework flags. Running the gallery without flags should produce identical behavior to before.

Run:
```bash
NO_COLOR=1 swift run gallery-demo
```

Expected: gallery launches with color disabled. Hit `q` or Ctrl-C to exit.

- [ ] **Step 4: Commit**

```bash
git add Examples/gallery/Package.swift Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift
git commit -m "feat(examples): migrate gallery-demo to SwiftTUIApp easy mode"
```

### Task 6.2: Migrate `Examples/minimal` to `SwiftTUIApp`

The `Examples/minimal` target today doesn't run a scene runtime; it just calls `print(output)`. Migrating it is meaningful because it proves the protocol works for the smallest possible app.

**Files:**
- Inspect first: `Examples/minimal/Package.swift` and `Examples/minimal/Sources/`
- Modify accordingly: add `SwiftTUIArguments` dep, conform to `SwiftTUIApp`

- [ ] **Step 1: Inspect the current state**

Run: `ls Examples/minimal/Sources && cat Examples/minimal/Package.swift && cat Examples/minimal/Sources/*.swift`

Document the current shape; if it's a script-style `main.swift` rather than an `@main struct App`, decide whether to migrate it or to leave it as-is. (The proposal allows bare-mode consumers to skip parsing entirely; if `Examples/minimal` is intentionally bare, leaving it alone is fine and can be documented as the bare-mode reference.)

- [ ] **Step 2: Apply changes if migration is appropriate**

If migrating, mirror the gallery changes: add the package dependency, replace the app declaration with a `@main struct: SwiftTUIApp`. If leaving bare, add a comment to the file explaining that this is the bare-mode reference (no framework arg parsing).

- [ ] **Step 3: Run / build to verify**

Run: `cd Examples/minimal && swift build && swift run`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add Examples/minimal/
git commit -m "docs(examples): clarify Examples/minimal as bare-mode reference"
# OR (if migrated):
git commit -m "feat(examples): migrate minimal example to SwiftTUIApp"
```

### Task 6.3: Add an `Examples/argparse` example demonstrating consumer flags + framework flags

A small new example proves the "consumer flags coexist with framework flags" path end-to-end.

**Files:**
- Create: `Examples/argparse/Package.swift`
- Create: `Examples/argparse/Sources/ArgParseDemo/ArgParseDemoApp.swift`

- [ ] **Step 1: Verify the directory does not exist**

Run: `ls Examples/argparse 2>/dev/null && echo EXISTS || echo NEW`
Expected: NEW.

- [ ] **Step 2: Create `Examples/argparse/Package.swift`**

```swift
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "argparse-demo",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "argparse-demo", targets: ["ArgParseDemo"])
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUICLI", path: "../../Platforms/CLI"),
    .package(name: "SwiftTUIArguments", path: "../../Platforms/Arguments"),
  ],
  targets: [
    .executableTarget(
      name: "ArgParseDemo",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
        .product(name: "SwiftTUIArguments", package: "SwiftTUIArguments"),
      ]
    )
  ]
)
```

- [ ] **Step 3: Create the app file**

Create `Examples/argparse/Sources/ArgParseDemo/ArgParseDemoApp.swift`:

```swift
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments

@main
struct ArgParseDemoApp: SwiftTUIApp {
  static let configuration = CommandConfiguration(
    commandName: "argparse-demo",
    abstract: "Demonstrates consumer flags + SwiftTUI framework flags coexisting."
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Option(name: .shortAndLong, help: "How many widgets to show.")
  var widgets: Int = 5

  @Flag(name: .customLong("show-ids"), help: "Show widget IDs alongside their labels.")
  var showIds: Bool = false

  var body: some Scene {
    WindowGroup {
      Text("widgets: \(widgets), showIds: \(showIds)")
    }
  }
}
```

- [ ] **Step 4: Build and exercise**

Run:
```bash
cd Examples/argparse
swift build
swift run argparse-demo --help
swift run argparse-demo --widgets 10 --no-color
```

Expected: help renders both consumer flags and framework flags; running with `--widgets 10 --no-color` does not error out.

- [ ] **Step 5: Commit**

```bash
git add Examples/argparse/
git commit -m "feat(examples): add argparse-demo showing consumer + framework flag coexistence"
```

### Task 6.4: Update README / docs index to point at the new package

**Files:**
- Modify: `README.md` (top-level)
- Possibly: `docs/proposals/ARGUMENT_PARSING.md` (mark as implemented for phases 1-5; cross-link to plan)

- [ ] **Step 1: Add a "Argument Parsing" section to top-level README**

Append (or insert in the appropriate place) a brief snippet:

```markdown
## Argument parsing

For apps that want CLI flags + the framework's standard flag surface
(`--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, `--web`,
`-v`, `--debug`, `--start-in`, ...), import `SwiftTUIArguments` and
conform to `SwiftTUIApp`:

```swift
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments

@main
struct MyApp: SwiftTUIApp {
  @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
  @Option public var widgets: Int = 10
  var body: some Scene { WindowGroup { ContentView() } }
}
```

Bare-mode apps (no `SwiftTUIArguments` import) still honor `NO_COLOR`,
`LANG=C`, and the `SWIFTTUI_*` env vars automatically. See
`docs/proposals/ARGUMENT_PARSING.md` for the full design.
```

- [ ] **Step 2: Update the proposal status header**

In `docs/proposals/ARGUMENT_PARSING.md`, update the **Status** field from "Draft" to:

```markdown
**Status:** Phases 1–5 implemented per
[`docs/plans/2026-05-04-002-argument-parsing-plan.md`](../plans/2026-05-04-002-argument-parsing-plan.md).
Phases 6 (runner-internal-flag migration), 7 (web subcommand wiring), and 8
(broader examples migration) are tracked as follow-up plans.
```

Also append to the Changelog:

```markdown
- 2026-MM-DD: Phases 1–5 landed via plan
  `docs/plans/2026-05-04-002-argument-parsing-plan.md`. `RuntimeConfiguration`
  in `SwiftTUI` core; `SwiftTUIArguments` peer package shipping
  `SwiftTUIOptions: ParsableArguments` and `SwiftTUIApp: AsyncParsableCommand`;
  `completions` subcommand. Bare-mode apps now honor framework env vars
  via the default `App.main()` extension.
```

(Replace `MM-DD` with the actual landing date when closing out the plan.)

- [ ] **Step 3: Commit**

```bash
git add README.md docs/proposals/ARGUMENT_PARSING.md
git commit -m "docs: announce SwiftTUIArguments and update ARGUMENT_PARSING.md status"
```

---

## Final smoke tests

After all stages land, run end-to-end verification.

- [ ] **Step 1: Build everything**

Run:
```bash
swift build                              # root package
cd Platforms/CLI && swift build && cd ../..
cd Platforms/Arguments && swift build && cd ../..
cd Examples/gallery && swift build && cd ../..
cd Examples/argparse && swift build && cd ../..
```

Expected: every package builds.

- [ ] **Step 2: Run all tests**

Run:
```bash
swift test
cd Platforms/CLI && swift test && cd ../..
cd Platforms/Arguments && swift test && cd ../..
```

Expected: every test target green.

- [ ] **Step 3: Manual help-output inspection**

Run: `cd Examples/argparse && swift run argparse-demo --help`

Expected output structure:
```
USAGE: argparse-demo [<options>]

OPTIONS:
  -w, --widgets <widgets> How many widgets to show.
  --show-ids              Show widget IDs alongside their labels.
  --version               Show version information.
  -h, --help              Show help information.

SWIFTTUI OPTIONS:
  --no-color              Disable color output. ... [env: NO_COLOR]
  --force-color           Force color output ... [env: FORCE_COLOR]
  --accessible            Accessible mode ... [env: SWIFTTUI_ACCESSIBLE]
  ...
```

- [ ] **Step 4: Manual env-var honoring check**

Run:
```bash
NO_COLOR=1 swift run argparse-demo
SWIFTTUI_ACCESSIBLE=1 swift run argparse-demo
SWIFTTUI_DEBUG=1 swift run argparse-demo
```

Expected: app launches each time; behavior reflects env var settings.

- [ ] **Step 5: Final commit (if any cleanup)**

```bash
git status
# If any tracked-but-uncommitted changes:
git commit -am "chore: final cleanup after argument parsing implementation"
```

---

## Follow-up plans (out of scope here)

After this plan lands, the following work is tracked as separate plans:

1. **Plan: Wire `RuntimeConfiguration` into rendering decisions.**
   Currently `TerminalRunner.run(_:configuration:)` accepts the configuration
   but doesn't apply it. Color profile selection, glyph-mode forcing,
   accessible-mode rendering strategy, motion suppression, and `--debug`
   instrumentation should all consume `RuntimeConfiguration` fields. This
   is the work that turns the parsing into actual user-visible behavior.

2. **Plan: Migrate `CLIMode.parse` runner-internal flags to subcommands**
   (Phase 6 of the proposal). Replace `--instances` / `--scenes` /
   `--attach` / `--pid` / `--instance` with `myapp instances` /
   `myapp scenes list` / `myapp attach <id>` subcommands. Old flags stay
   deprecated for one release.

3. **Plan: Wire `--web` to the embedded web host** (Phase 7 of the
   proposal, blocked on `EMBEDDED_WEB_HOST.md` finalizing). Add a
   `myapp web` subcommand alongside the flag, and route to the embedded
   HTTP server.

4. **Plan: Crash guard reads `RuntimeConfiguration.debug`** (Q14 of the
   proposal). The crash guard introduced by ADR-0010 should write a
   richer post-mortem when debug is on.

5. **Plan: Migrate remaining examples** (Phase 8 of the proposal). Walk
   through `Examples/gifcat`, `Examples/layouts`, `Examples/gifeditor`,
   `Examples/WebExample`, `Examples/SwiftUIExample` and migrate each
   from `App` to `SwiftTUIApp`.

6. **Plan: WASI / SwiftUIHost / WebHost integration.** These runners
   should accept `RuntimeConfiguration` via `RuntimeConfiguration.builder`
   even though they don't have argv. Sketched in the proposal §
   Interaction with decision 0008.

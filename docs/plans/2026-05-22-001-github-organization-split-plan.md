# GitHub Organization Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split SwiftTUI across a small GitHub organization without making the
default Swift terminal and WebHost consumer path harder, and without losing a
single coherent public documentation site.

**Architecture:** Keep `SwiftTUI/swift-tui` as the canonical SwiftPM package and
release anchor. Extract browser TypeScript sources, examples, and the website
into separate repos only after the main package has explicit bundle, release,
and documentation contracts. The docs site then composes DocC archives from
released Swift repos plus non-DocC web/example content.

**Tech Stack:** SwiftPM, Swift 6.3.1 via `swiftly`, Swift-DocC plugin combined
documentation and external-link support, Bun 1.3.13, TypeScript, Astro,
Cloudflare Pages, GitHub Actions, npm package publishing for `@swifttui/web`
and `@swifttui/build`.

---

## Repository Targets

| Repository | Owns | Does not own |
| --- | --- | --- |
| `SwiftTUI/swift-tui` | SwiftPM package, core/views/runtime, terminal CLI, native WebHost Swift runner, WASI Swift runner, embedded WebHost browser bundle, Swift DocC source, Swift release tags | Website deployment, example app regression matrix after extraction, TypeScript browser source after extraction |
| `SwiftTUI/swift-tui-web` | `@swifttui/web`, `@swifttui/build`, browser runtime, WASI/browser bridge, WebHost browser bundle source, npm releases | SwiftPM products, Cloudflare site deployment |
| `SwiftTUI/swift-tui-examples` | Runnable examples, demo package tests, WebExample static deployment source, example screenshots/assets | Public Swift framework products, required DocC coverage |
| `SwiftTUI/swift-tui-site` | Astro website, Cloudflare Pages deployment, docs composition, release landing pages | Framework implementation and package releases |

Leave `SwiftTUICharts`, `SwiftTUIAnimatedImage`, `SwiftTUITerminal`,
`SwiftTUITerminalWorkspace`, `SwiftTUIWASI`, `SwiftTUIWebHost`, and
`SwiftTUIWebHostCLI` in `swift-tui` for this split. Several of those targets
use `package` access or runner SPI today; extracting them now would force
implementation seams into public API before they are stable.

## Invariants

- A normal Swift app depends on one package and imports one module:

  ```swift
  .package(url: "https://github.com/SwiftTUI/swift-tui", .upToNextMinor(from: "0.1.0"))
  ```

  ```swift
  import SwiftTUI
  ```

- `SwiftTUI` keeps terminal launch and localhost WebHost launch through
  `SwiftTUIWebHostCLI`; `--web` remains a runtime flag, not a second package
  integration.
- `swift-tui` stores a checked-in browser bundle under
  `Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser` so Swift
  consumers do not need Bun or npm to use WebHost.
- Every public Swift repo intended for external users has DocC catalogs and is
  included in the web build. Example repos are runnable samples and regression
  surfaces, so they do not require DocC.
- Public documentation is served from one site. Source-authored DocC links are
  preferred over post-processing generated archives.

## File Structure To Create Or Modify

- Create `docs/REPOSITORY-SPLIT.md` in `swift-tui`: stable decision record for
  the organization split, repository ownership table, and release invariants.
- Modify `docs/README.md` in `swift-tui`: link `docs/REPOSITORY-SPLIT.md` and
  this plan.
- Modify `docs/ARCHITECTURE.md` in `swift-tui`: replace the absolute "one Swift
  package" statement with "one SwiftPM package in the `swift-tui` repo" and
  clarify which code is intentionally external.
- Modify `docs/DEVELOPMENT.md` in `swift-tui`: describe the post-split release
  flow, WebHost bundle update command, and DocC ownership.
- Create `Scripts/update_webhost_bundle.sh` in `swift-tui`: copy a built
  `swift-tui-web` browser bundle into the SwiftPM resource path.
- Modify `Scripts/build-webhost-bundle.sh` in `swift-tui`: delegate to
  `Scripts/update_webhost_bundle.sh` once `Platforms/Web` leaves the repo.
- Modify `Scripts/test_all.sh`, `Scripts/test_gate.sh`, and
  `Scripts/check_demo_builds.sh` in `swift-tui`: remove extracted example/web
  package steps from the core repo gate and replace them with WebHost bundle
  integrity checks.
- Create `package.json`, `bun.lock`, and CI workflows in `swift-tui-web`:
  publish the TypeScript runtime/build packages and bundle artifact.
- Create `Scripts/check_examples.sh` and CI workflows in `swift-tui-examples`:
  carry the current example build/test matrix that moves out of `swift-tui`.
- Create `docs/docc-repos.yml` and a docs composition workflow in
  `swift-tui-site`: build or fetch DocC archives for public Swift repos and
  compose the Cloudflare Pages artifact.

---

### Task 1: Record The Split Decision In `swift-tui`

**Files:**
- Create: `docs/REPOSITORY-SPLIT.md`
- Modify: `docs/README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DEVELOPMENT.md`

- [ ] **Step 1: Write `docs/REPOSITORY-SPLIT.md`**

  Use this structure and fill it with the repository table and invariants from
  this plan:

  ```markdown
  # Repository Split

  SwiftTUI uses multiple GitHub repositories, but one repo remains the Swift
  release anchor: `SwiftTUI/swift-tui`.

  ## Consumer Contract

  A terminal or localhost-browser app depends on `SwiftTUI/swift-tui` and imports
  `SwiftTUI`. The package continues to include terminal launch and WebHost launch
  through `SwiftTUIWebHostCLI`, so `--web` remains a runtime mode selection.

  ## Repository Ownership

  | Repository | Owns | Does not own |
  | --- | --- | --- |
  | `SwiftTUI/swift-tui` | SwiftPM products, runtime, terminal CLI, WebHost Swift runner, WASI Swift runner, embedded WebHost browser bundle, Swift DocC source | Website deployment, example regression matrix after extraction, TypeScript browser source after extraction |
  | `SwiftTUI/swift-tui-web` | `@swifttui/web`, `@swifttui/build`, browser runtime, WebHost browser bundle source, npm releases | SwiftPM products, Cloudflare site deployment |
  | `SwiftTUI/swift-tui-examples` | Runnable examples, demo package tests, WebExample static deployment source | Public Swift framework products, required DocC coverage |
  | `SwiftTUI/swift-tui-site` | Astro website, Cloudflare Pages deployment, docs composition, release landing pages | Framework implementation and package releases |

  ## Extraction Boundary

  `SwiftTUICore`, `SwiftTUIViews`, `SwiftTUIRuntime`, `SwiftTUICLI`,
  `SwiftTUIWASI`, `SwiftTUIWebHost`, `SwiftTUIWebHostCLI`,
  `SwiftTUIAnimatedImage`, `SwiftTUICharts`, `SwiftTUITerminal`, and
  `SwiftTUITerminalWorkspace` stay in `swift-tui` for this split.

  ## Documentation Contract

  Every externally linkable Swift product has DocC and is included in the public
  web build. Example repositories are excluded from DocC coverage unless an
  example becomes a published library product.
  ```

- [ ] **Step 2: Link the decision and plan from `docs/README.md`**

  Add a `Planning documents` section after `Proposal documents`:

  ```markdown
  ## Planning documents

  - [REPOSITORY-SPLIT.md](REPOSITORY-SPLIT.md) - repository ownership,
    release boundaries, and public documentation invariants.
  - [plans/2026-05-22-001-github-organization-split-plan.md](plans/2026-05-22-001-github-organization-split-plan.md)
    - execution plan for moving browser source, examples, and the website into
      separate GitHub repositories.
  ```

- [ ] **Step 3: Update architecture wording**

  In `docs/ARCHITECTURE.md`, replace:

  ```markdown
  SwiftTUI is one Swift package.
  ```

  with:

  ```markdown
  `SwiftTUI/swift-tui` is one SwiftPM package. Browser TypeScript source,
  examples, and the public website may live in sibling organization repositories,
  but the public Swift products below remain in this package unless a later
  extraction explicitly promotes their package-private seams into stable public
  API.
  ```

- [ ] **Step 4: Update development wording**

  Add a short section to `docs/DEVELOPMENT.md` under `Releases`:

  ```markdown
  ## Repository split release flow

  The Swift release anchor is `SwiftTUI/swift-tui`. Release tags in sibling repos
  must reference a released `swift-tui` tag, not an arbitrary branch SHA, unless
  the release is an internal preview.

  `SwiftTUIWebHost` ships a checked-in browser bundle. When the browser runtime
  source changes in `SwiftTUI/swift-tui-web`, update the bundle in `swift-tui`
  with `Scripts/update_webhost_bundle.sh --web-checkout ../swift-tui-web`, run
  `bun run test`, and commit the resource update with the matching web release
  version in the commit message.
  ```

- [ ] **Step 5: Verify documentation edits**

  Run:

  ```bash
  rg -n "Repository Split|swift-tui-web|update_webhost_bundle|Planning documents" docs
  git diff --check
  ```

  Expected: `rg` prints the new links and release-flow text; `git diff --check`
  exits with status 0.

- [ ] **Step 6: Commit the decision**

  ```bash
  git add docs/REPOSITORY-SPLIT.md docs/README.md docs/ARCHITECTURE.md docs/DEVELOPMENT.md
  git commit -m "docs: record repository split plan"
  ```

---

### Task 2: Freeze The Main Swift Package Boundary

**Files:**
- Modify: `Package.swift`
- Modify: `Scripts/check_webhost_package_boundary.sh`
- Create: `Scripts/check_repository_split_boundary.sh`
- Modify: `Scripts/lib/repo_policy_checks.sh`
- Modify: `docs/DEVELOPMENT.md`

- [ ] **Step 1: Add a repository split boundary check**

  Create `Scripts/check_repository_split_boundary.sh`:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
  cd "$repo_root"

  fail() {
    printf '[check_repository_split_boundary] %s\n' "$1" >&2
    exit 1
  }

  if ! rg -n --fixed-strings --quiet 'SwiftTUIWebHostCLI' Package.swift; then
    fail 'SwiftTUI must keep the combined terminal/WebHost runner in the main Swift package.'
  fi

  if ! rg -n --fixed-strings --quiet 'SwiftTUIAnimatedImage' Package.swift; then
    fail 'SwiftTUI must keep animated image support in the convenience product.'
  fi

  if rg -n --fixed-strings '@swifttui/web' Sources Platforms/CLI Platforms/WASI Platforms/Embedding --glob '*.swift'; then
    fail 'Swift source must not depend on the npm browser package.'
  fi

  if [ ! -f Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser/index.html ]; then
    fail 'SwiftTUIWebHost must ship a checked-in browser bundle.'
  fi

  if ! find Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser -type f -name '*.js' -print | grep -q .; then
    fail 'SwiftTUIWebHost browser bundle must include a JavaScript asset.'
  fi

  printf '[check_repository_split_boundary] ok\n'
  ```

- [ ] **Step 2: Add the check to the policy phase**

  In `Scripts/lib/repo_policy_checks.sh`, add this block after
  `Check WebHost package boundary`:

  ```bash
  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check repository split boundary" \
    "./Scripts/check_repository_split_boundary.sh" \
    ./Scripts/check_repository_split_boundary.sh
  ```

- [ ] **Step 3: Confirm package products still expose the consumer contract**

  Run:

  ```bash
  swiftly run swift package describe --type json > /tmp/swift-tui-package.json
  rg -n '"name" : "SwiftTUI"|"name" : "SwiftTUIWebHostCLI"|"name" : "SwiftTUICLI"' /tmp/swift-tui-package.json
  ./Scripts/check_repository_split_boundary.sh
  ```

  Expected: the package description contains `SwiftTUI`, `SwiftTUIWebHostCLI`,
  and `SwiftTUICLI`; the new script prints
  `[check_repository_split_boundary] ok`.

- [ ] **Step 4: Run the focused gate**

  ```bash
  bun run test
  ```

  Expected: the repo gate passes.

- [ ] **Step 5: Commit the boundary guard**

  ```bash
  git add Scripts/check_repository_split_boundary.sh Scripts/lib/repo_policy_checks.sh docs/DEVELOPMENT.md
  git commit -m "chore: guard repository split boundaries"
  ```

---

### Task 3: Extract Browser Source Into `swift-tui-web`

**Files:**
- Create in `SwiftTUI/swift-tui-web`: `package.json`
- Create in `SwiftTUI/swift-tui-web`: `bun.lock`
- Create in `SwiftTUI/swift-tui-web`: `packages/web/`
- Create in `SwiftTUI/swift-tui-web`: `packages/build/`
- Create in `SwiftTUI/swift-tui-web`: `.github/workflows/test.yml`
- Modify in `swift-tui`: `Scripts/build-webhost-bundle.sh`
- Create in `swift-tui`: `Scripts/update_webhost_bundle.sh`

- [ ] **Step 1: Create the new repository and copy sources**

  ```bash
  cd /Users/adamz/Developer/repos
  gh repo create SwiftTUI/swift-tui-web --public --clone
  cd swift-tui-web
  mkdir -p packages/web packages/build
  rsync -a --delete ../swift-tui/Platforms/Web/ packages/web/
  rsync -a --delete ../swift-tui/Platforms/WebBuild/ packages/build/
  ```

  Expected: `packages/web/package.json` has package name `@swifttui/web` and
  `packages/build/package.json` has package name `@swifttui/build`.

- [ ] **Step 2: Add root workspace metadata**

  Create `package.json` in `swift-tui-web`:

  ```json
  {
    "name": "swift-tui-web-workspace",
    "private": true,
    "version": "0.1.0",
    "license": "MIT",
    "workspaces": [
      "packages/web",
      "packages/build"
    ],
    "scripts": {
      "test": "bun test packages/web packages/build",
      "build:web": "bun run --cwd packages/web build:web",
      "build": "bun run --cwd packages/web build",
      "ci": "bun install --frozen-lockfile && bun run test && bun run build:web"
    }
  }
  ```

- [ ] **Step 3: Rewrite workspace-relative imports and scripts**

  In `packages/web/package.json`, replace references to `../WebBuild` with
  `../build`. In `packages/build/package.json`, keep the package export
  `@swifttui/build` and replace the dependency on `@swifttui/web` with:

  ```json
  "dependencies": {
    "@swifttui/web": "workspace:*"
  }
  ```

  Run:

  ```bash
  rg -n "../WebBuild|Platforms/Web|Platforms/WebBuild" packages
  ```

  Expected: no matches remain.

- [ ] **Step 4: Add CI**

  Create `.github/workflows/test.yml`:

  ```yaml
  name: Test

  on:
    pull_request:
    push:
      branches: [main]

  jobs:
    test:
      runs-on: macos-26
      steps:
        - uses: actions/checkout@v6
        - uses: oven-sh/setup-bun@v2
          with:
            bun-version: "1.3.13"
        - run: bun install --frozen-lockfile
        - run: bun run test
        - run: bun run build:web
  ```

- [ ] **Step 5: Validate the extracted web repo**

  ```bash
  bun install
  bun run test
  bun run build:web
  ```

  Expected: tests pass and `packages/web/dist/index.html` exists.

- [ ] **Step 6: Add the Swift repo bundle update script**

  In `swift-tui`, create `Scripts/update_webhost_bundle.sh`:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
  web_checkout=""

  usage() {
    cat <<'EOF'
  Usage: Scripts/update_webhost_bundle.sh --web-checkout PATH

  Builds the browser runtime from SwiftTUI/swift-tui-web and copies the output
  into SwiftTUIWebHost's checked-in SwiftPM resource bundle.
  EOF
  }

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --web-checkout)
        web_checkout=$2
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  [ -n "$web_checkout" ] || {
    echo "Missing --web-checkout" >&2
    usage >&2
    exit 1
  }

  web_checkout="$(cd "$web_checkout" && pwd)"
  dist_dir="$web_checkout/packages/web/dist"
  resource_dir="$repo_root/Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser"

  (cd "$web_checkout" && bun install --frozen-lockfile && bun run build:web)

  [ -f "$dist_dir/index.html" ] || {
    echo "Missing $dist_dir/index.html" >&2
    exit 1
  }

  rm -rf "$resource_dir"
  mkdir -p "$resource_dir"
  cp -R "$dist_dir"/. "$resource_dir"/

  find "$resource_dir" -type f -name '*.js' -print | grep -q . || {
    echo "Browser bundle does not contain JavaScript" >&2
    exit 1
  }

  printf '[update_webhost_bundle] copied %s to %s\n' "$dist_dir" "$resource_dir"
  ```

- [ ] **Step 7: Validate bundle update from the new repo**

  ```bash
  cd /Users/adamz/Developer/repos/swift-tui
  chmod +x Scripts/update_webhost_bundle.sh
  Scripts/update_webhost_bundle.sh --web-checkout ../swift-tui-web
  ./Scripts/check_repository_split_boundary.sh
  swiftly run swift build --target SwiftTUIWebHost --target SwiftTUIWebHostCLI
  ```

  Expected: the bundle copy succeeds, the boundary check passes, and both
  WebHost Swift targets build.

- [ ] **Step 8: Commit both repositories**

  In `swift-tui-web`:

  ```bash
  git add .
  git commit -m "chore: create browser runtime workspace"
  git push -u origin main
  ```

  In `swift-tui`:

  ```bash
  git add Scripts/update_webhost_bundle.sh Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser
  git commit -m "chore: source WebHost browser bundle from swift-tui-web"
  ```

---

### Task 4: Move Examples Into `swift-tui-examples`

**Files:**
- Create in `SwiftTUI/swift-tui-examples`: `Examples/`
- Create in `SwiftTUI/swift-tui-examples`: `Scripts/check_examples.sh`
- Create in `SwiftTUI/swift-tui-examples`: `.github/workflows/test.yml`
- Modify in `swift-tui`: `Scripts/test_all.sh`
- Modify in `swift-tui`: `Scripts/test_gate.sh`
- Modify in `swift-tui`: `Scripts/check_demo_builds.sh`
- Modify in `swift-tui`: `docs/DEVELOPMENT.md`

- [ ] **Step 1: Create the examples repository and copy examples**

  ```bash
  cd /Users/adamz/Developer/repos
  gh repo create SwiftTUI/swift-tui-examples --public --clone
  cd swift-tui-examples
  rsync -a --delete ../swift-tui/Examples/ Examples/
  cp ../swift-tui/Scripts/check_demo_builds.sh Scripts/check_examples.sh
  cp ../swift-tui/Scripts/stack_safety_harness.py Scripts/stack_safety_harness.py
  ```

- [ ] **Step 2: Update local package paths**

  Replace each example manifest dependency on the root package with:

  ```swift
  .package(name: "swift-tui", path: "../../../swift-tui")
  ```

  for examples under `Examples/<name>/Package.swift`, and:

  ```swift
  .package(name: "swift-tui", path: "../../../../swift-tui")
  ```

  for nested packages such as `Examples/WebExample/TerminalApp`.

  Run:

  ```bash
  rg -n 'package\\(name: "swift-tui"|github.com/SwiftTUI/swift-tui|path: "../.."' Examples
  ```

  Expected: every example resolves either to `../../../swift-tui` or
  `../../../../swift-tui`; no example points back to an in-repo root package
  path.

- [ ] **Step 3: Rewrite `Scripts/check_examples.sh`**

  Keep the same build/test list currently in `Scripts/check_demo_builds.sh`, but
  change `repo_root` assumptions so the script runs from `swift-tui-examples`
  with `../swift-tui` as the framework checkout. The script must still run:

  ```bash
  swiftly run swift build --package-path Examples/gallery
  swiftly run swift test --package-path Examples/WebHostExample
  bun run --cwd Examples/WebExample build
  python3 Scripts/stack_safety_harness.py --binary Examples/gallery/.build/debug/gallery-demo --count 20
  ```

- [ ] **Step 4: Add examples CI**

  Create `.github/workflows/test.yml`:

  ```yaml
  name: Test

  on:
    pull_request:
    push:
      branches: [main]

  jobs:
    test:
      runs-on: macos-26
      steps:
        - name: Checkout examples
          uses: actions/checkout@v6
          with:
            path: swift-tui-examples
        - name: Checkout swift-tui
          uses: actions/checkout@v6
          with:
            repository: SwiftTUI/swift-tui
            path: swift-tui
        - uses: oven-sh/setup-bun@v2
          with:
            bun-version: "1.3.13"
        - name: Install swiftly and Swift toolchain
          working-directory: swift-tui
          run: |
            curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg
            installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
            ~/.swiftly/bin/swiftly init --skip-install --quiet-shell-followup --assume-yes
            . "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"
            swiftly install --use --assume-yes "$(tr -d '[:space:]' < .swift-version)"
            echo "$HOME/.swiftly/bin" >> "$GITHUB_PATH"
        - name: Run examples
          working-directory: swift-tui-examples
          run: Scripts/check_examples.sh --skip-clean
  ```

- [ ] **Step 5: Remove examples from the main repo gate**

  In `swift-tui`, update `Scripts/test_all.sh` and `Scripts/test_gate.sh` help
  text and command lists so the core repo gate no longer invokes
  `Examples/*` packages after they move. Keep root Swift package tests, platform
  product tests, policy checks, `Platforms/WebHost` Swift target builds, and the
  WebHost browser bundle integrity check.

- [ ] **Step 6: Validate both repos**

  In `swift-tui-examples`:

  ```bash
  Scripts/check_examples.sh --skip-clean
  ```

  In `swift-tui`:

  ```bash
  bun run test
  ```

  Expected: examples pass in the examples repo; the main repo gate passes
  without example-package steps.

- [ ] **Step 7: Commit both repositories**

  In `swift-tui-examples`:

  ```bash
  git add .
  git commit -m "chore: create SwiftTUI examples workspace"
  git push -u origin main
  ```

  In `swift-tui`:

  ```bash
  git add Scripts/test_all.sh Scripts/test_gate.sh Scripts/check_demo_builds.sh docs/DEVELOPMENT.md
  git commit -m "chore: move example matrix to examples repo"
  ```

---

### Task 5: Move Website And Docs Composition Into `swift-tui-site`

**Files:**
- Create in `SwiftTUI/swift-tui-site`: `Website/`
- Create in `SwiftTUI/swift-tui-site`: `.github/workflows/cloudflare-pages.yml`
- Create in `SwiftTUI/swift-tui-site`: `docs/docc-repos.yml`
- Create in `SwiftTUI/swift-tui-site`: `Scripts/build_docc_site.sh`
- Modify in `swift-tui`: `.github/workflows/cloudflare-pages.yml`
- Modify in `swift-tui`: `package.json`

- [ ] **Step 1: Create the site repository and copy the current site**

  ```bash
  cd /Users/adamz/Developer/repos
  gh repo create SwiftTUI/swift-tui-site --public --clone
  cd swift-tui-site
  rsync -a --delete ../swift-tui/Website/ Website/
  mkdir -p Scripts docs .github/workflows
  cp ../swift-tui/.github/workflows/cloudflare-pages.yml .github/workflows/cloudflare-pages.yml
  ```

- [ ] **Step 2: Add the DocC repository manifest**

  Create `docs/docc-repos.yml`:

  ```yaml
  swiftRepos:
    - name: swift-tui
      repository: SwiftTUI/swift-tui
      ref: main
      doccCommand: Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs
      outputPath: .build-docs
      mountPath: docs
  ```

  Keep only `swift-tui` in this manifest for the initial split. Add-on Swift
  repos enter the manifest only after they exist and have DocC archives with
  external link metadata.

- [ ] **Step 3: Add the docs composition script**

  Create `Scripts/build_docc_site.sh`:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  site_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
  work_root="${site_root}/.build-docs-work"
  output_root="${site_root}/Website/dist/docs"

  rm -rf "$work_root" "$output_root"
  mkdir -p "$work_root" "$output_root"

  git clone https://github.com/SwiftTUI/swift-tui "$work_root/swift-tui"
  (
    cd "$work_root/swift-tui"
    Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs
  )

  cp -R "$work_root/swift-tui/.build-docs"/. "$output_root"/
  printf '[build_docc_site] copied swift-tui DocC archive to %s\n' "$output_root"
  ```

- [ ] **Step 4: Rewrite the Cloudflare workflow**

  In `swift-tui-site/.github/workflows/cloudflare-pages.yml`, replace the
  single-repo assumptions with explicit checkouts:

  ```yaml
  - name: Checkout site
    uses: actions/checkout@v6
    with:
      path: swift-tui-site

  - name: Checkout swift-tui
    uses: actions/checkout@v6
    with:
      repository: SwiftTUI/swift-tui
      path: swift-tui

  - name: Checkout examples
    uses: actions/checkout@v6
    with:
      repository: SwiftTUI/swift-tui-examples
      path: swift-tui-examples
  ```

  Build DocC from `swift-tui`, build WebExample from `swift-tui-examples`, and
  compose the artifact under `swift-tui-site/_cf-pages-artifact`.

- [ ] **Step 5: Validate the site repo locally**

  ```bash
  cd /Users/adamz/Developer/repos/swift-tui-site
  bun install --cwd Website
  bun run --cwd Website check
  bun run --cwd Website build
  Scripts/build_docc_site.sh
  ```

  Expected: Astro checks pass, Astro build passes, and `Website/dist/docs`
  contains the `swift-tui` DocC archive.

- [ ] **Step 6: Remove site workspace ownership from `swift-tui`**

  In `swift-tui/package.json`, remove `Website` from `workspaces` and remove
  scripts whose only purpose is site deployment:

  ```json
  "build:website": "bun run --cwd Website build:full",
  "build:website:dev": "bun run --cwd Website build:dev",
  "dev:website": "bun run --cwd Website dev"
  ```

  Keep framework, WebHost bundle, and repo-gate scripts in `swift-tui`.

- [ ] **Step 7: Commit both repositories**

  In `swift-tui-site`:

  ```bash
  git add .
  git commit -m "chore: create SwiftTUI website repo"
  git push -u origin main
  ```

  In `swift-tui`:

  ```bash
  git add package.json bun.lock
  git rm -r Website .github/workflows/cloudflare-pages.yml
  git commit -m "chore: move website deployment to site repo"
  ```

---

### Task 6: Remove Extracted Source From `swift-tui`

**Files:**
- Modify in `swift-tui`: `package.json`
- Modify in `swift-tui`: `bun.lock`
- Delete from `swift-tui`: `Platforms/Web/`
- Delete from `swift-tui`: `Platforms/WebBuild/`
- Delete from `swift-tui`: `Examples/`
- Modify in `swift-tui`: `Scripts/check_demo_builds.sh`
- Modify in `swift-tui`: `Scripts/build-webhost-bundle.sh`
- Modify in `swift-tui`: `docs/HOSTS-AND-PLATFORMS.md`
- Modify in `swift-tui`: `docs/DEVELOPMENT.md`

- [ ] **Step 1: Delete extracted source directories**

  ```bash
  git rm -r Platforms/Web Platforms/WebBuild Examples
  ```

- [ ] **Step 2: Shrink the Bun workspace**

  In `package.json`, replace:

  ```json
  "workspaces": [
    "Platforms/Web",
    "Platforms/WebBuild",
    "Examples/WebExample",
    "Website"
  ]
  ```

  with:

  ```json
  "workspaces": []
  ```

  If no root Bun dependencies remain after this change, keep `package.json`
  only for `bun run test`, `bun run test:all`, and perf script aliases.

- [ ] **Step 3: Update WebHost bundle script**

  Replace `Scripts/build-webhost-bundle.sh` with a wrapper that points maintainers
  to the extracted source:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
  default_web_checkout="${repo_root}/../swift-tui-web"

  exec "$repo_root/Scripts/update_webhost_bundle.sh" --web-checkout "$default_web_checkout"
  ```

- [ ] **Step 4: Update host docs**

  In `docs/HOSTS-AND-PLATFORMS.md`, replace the `The web packages` section with:

  ```markdown
  ## The web packages

  The Swift products that run browser surfaces live in this repo:
  `SwiftTUIWASI`, `SwiftTUIWebHost`, and `SwiftTUIWebHostCLI`.

  Browser TypeScript source lives in `SwiftTUI/swift-tui-web` as
  `@swifttui/web` and `@swifttui/build`. `SwiftTUIWebHost` consumes a checked-in
  browser bundle under `Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser`
  so Swift package consumers do not need Bun or npm for localhost WebHost use.
  ```

- [ ] **Step 5: Validate `swift-tui` after deletion**

  ```bash
  ./Scripts/check_repository_split_boundary.sh
  swiftly run swift build
  bun run test
  Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs
  ```

  Expected: boundary check passes, Swift build passes, repo gate passes, and
  DocC archive generation succeeds.

- [ ] **Step 6: Commit extracted-source removal**

  ```bash
  git add package.json bun.lock Scripts/build-webhost-bundle.sh docs/HOSTS-AND-PLATFORMS.md docs/DEVELOPMENT.md
  git commit -m "chore: remove extracted web and example sources"
  ```

---

### Task 7: Wire Cross-Repo Releases And Documentation

**Files:**
- Create in `swift-tui-site`: `docs/releases.yml`
- Modify in `swift-tui-site`: `docs/docc-repos.yml`
- Modify in `swift-tui-site`: `.github/workflows/cloudflare-pages.yml`
- Modify in `swift-tui`: `docs/DEVELOPMENT.md`
- Modify in `swift-tui-web`: `package.json`
- Modify in `swift-tui-examples`: `README.md`

- [ ] **Step 1: Add release manifest**

  In `swift-tui-site`, create `docs/releases.yml`:

  ```yaml
  current:
    swiftTUI: 0.1.0
    web: 0.1.0
    examplesRef: main
  repos:
    swift-tui:
      url: https://github.com/SwiftTUI/swift-tui
      doccMount: docs
    swift-tui-web:
      url: https://github.com/SwiftTUI/swift-tui-web
      npmPackages:
        - "@swifttui/web"
        - "@swifttui/build"
    swift-tui-examples:
      url: https://github.com/SwiftTUI/swift-tui-examples
  ```

- [ ] **Step 2: Build DocC from release tags**

  Update `swift-tui-site/docs/docc-repos.yml` so `ref` can be changed by release:

  ```yaml
  swiftRepos:
    - name: swift-tui
      repository: SwiftTUI/swift-tui
      ref: v0.1.0
      doccCommand: Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs
      outputPath: .build-docs
      mountPath: docs
  ```

- [ ] **Step 3: Add web package release scripts**

  In `swift-tui-web/package.json`, add:

  ```json
  "scripts": {
    "test": "bun test packages/web packages/build",
    "build:web": "bun run --cwd packages/web build:web",
    "ci": "bun install --frozen-lockfile && bun run test && bun run build:web",
    "pack:web": "cd packages/web && bun pm pack",
    "pack:build": "cd packages/build && bun pm pack"
  }
  ```

- [ ] **Step 4: Run release validation in order**

  In `swift-tui`:

  ```bash
  bun run test
  Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs
  git tag v0.1.0
  ```

  In `swift-tui-web`:

  ```bash
  bun run ci
  bun run pack:web
  bun run pack:build
  git tag v0.1.0
  ```

  In `swift-tui-examples`:

  ```bash
  Scripts/check_examples.sh --skip-clean
  git tag v0.1.0
  ```

  In `swift-tui-site`:

  ```bash
  bun run --cwd Website check
  bun run --cwd Website build
  Scripts/build_docc_site.sh
  git tag v0.1.0
  ```

- [ ] **Step 5: Push tags after all validation passes**

  ```bash
  git push origin v0.1.0
  ```

  Run that command separately in each repo only after every repo has passed its
  validation command.

---

### Task 8: Close The Split With Compatibility Proof

**Files:**
- Modify in `swift-tui`: `Tests/SwiftTUITests/SwiftTUIConvenienceImportTests.swift`
- Modify in `swift-tui`: `docs/REPOSITORY-SPLIT.md`
- Modify in `swift-tui-site`: `Website/src/components/Quickstart.astro`

- [ ] **Step 1: Extend the consumer import contract test**

  In `Tests/SwiftTUITests/SwiftTUIConvenienceImportTests.swift`, add this test
  and file-scope fixture:

  ```swift
  @MainActor
  @Test("SwiftTUI import exposes command conformance surface")
  func swiftTUIImportExposesCommandConformanceSurface() throws {
    let app = try ImportSmokeCommand.parse(["--web"])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)

    #expect(configuration.web != nil)
    #expect(ImportSmokeCommand.configuration.subcommands.count == 1)
  }

  private struct ImportSmokeCommand: App, SwiftTUICommand {
    @OptionGroup(title: "SwiftTUI Options") public var swiftTUIOptions: SwiftTUIOptions

    init() {}

    var body: some Scene {
      WindowGroup {
        Text("Smoke")
      }
    }
  }
  ```

- [ ] **Step 2: Validate the consumer contract**

  ```bash
  swiftly run swift test --filter SwiftTUITests.SwiftTUIConvenienceImportTests/swiftTUIImportExposesCommandConformanceSurface
  bun run test
  ```

  Expected: the focused test and repo gate pass.

- [ ] **Step 3: Verify docs site quickstart still shows one Swift dependency**

  In `swift-tui-site/Website/src/components/Quickstart.astro`, keep the SwiftPM
  snippet on `SwiftTUI/swift-tui` and keep the import snippet as:

  ```swift
  import SwiftTUI
  ```

  Run:

  ```bash
  rg -n "github.com/SwiftTUI/swift-tui|import SwiftTUI|--web" Website/src
  bun run --cwd Website check
  ```

  Expected: the quickstart references one Swift package and one Swift import;
  Astro check passes.

- [ ] **Step 4: Commit compatibility proof**

  In `swift-tui`:

  ```bash
  git add Tests/SwiftTUITests/SwiftTUIConvenienceImportTests.swift docs/REPOSITORY-SPLIT.md
  git commit -m "test: lock SwiftTUI consumer import contract"
  ```

  In `swift-tui-site`:

  ```bash
  git add Website/src/components/Quickstart.astro
  git commit -m "docs: keep SwiftTUI quickstart on one package"
  ```

---

## Execution Order

1. Land Task 1 and Task 2 in `swift-tui` first. These make the intended split
   explicit and protect the consumer contract before files move.
2. Land Task 3 in `swift-tui-web`, then update the checked-in WebHost browser
   bundle in `swift-tui`.
3. Land Task 4 in `swift-tui-examples`, then remove example-package coverage
   from the `swift-tui` gate.
4. Land Task 5 in `swift-tui-site`, then remove site ownership from `swift-tui`.
5. Land Task 6 after the sibling repos are green.
6. Land Task 7 and Task 8 as the release/compatibility closeout.

## Self-Review

- Consumer ease is covered by Tasks 1, 2, and 8: the main Swift package remains
  the release anchor, `SwiftTUI` remains the one-import product, and a consumer
  import test locks the contract.
- Coherent DocC generation is covered by Tasks 1, 5, 6, and 7: public Swift
  products keep DocC in their source repos, the site composes archives, and
  release refs are explicit.
- The browser extraction is staged so Swift consumers keep a checked-in WebHost
  bundle before TypeScript source leaves `swift-tui`.
- Examples are moved after their own CI exists, so the main repo does not lose
  regression coverage before the replacement gate is available.

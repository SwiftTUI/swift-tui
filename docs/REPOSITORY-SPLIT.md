# Repository Split

SwiftTUI uses multiple GitHub repositories, but one repo remains the Swift
release anchor: `SwiftTUI/swift-tui`.

## Consumer Contract

A terminal or localhost-browser app depends on `SwiftTUI/swift-tui` and imports
`SwiftTUI`. The package continues to include terminal launch and WebHost launch
through `SwiftTUIWebHostCLI`, so `--web` remains a runtime mode selection.

`Tests/SwiftTUITests/SwiftTUIConvenienceImportTests.swift` locks this contract
with a consumer-shaped `App, SwiftTUICommand` fixture. The split can move
browser TypeScript, examples, and site deployment out of this repository without
requiring downstream apps to add extra SwiftPM dependencies or import lower-level
SwiftTUI products directly.

## Repository Ownership

| Repository | Owns | Does not own |
| --- | --- | --- |
| `SwiftTUI/swift-tui` | SwiftPM products, runtime, terminal CLI, WebHost Swift runner, WASI Swift runner, embedded WebHost browser bundle, Swift DocC source | Website deployment, example regression matrix after extraction, TypeScript browser source after extraction |
| `SwiftTUI/swift-tui-web` | `@swifttui/web`, `@swifttui/build`, browser runtime, WebHost browser bundle source, npm releases | SwiftPM products, Cloudflare site deployment |
| `SwiftTUI/swift-tui-examples` | Runnable examples, demo package tests, WebExample static deployment source | Public Swift framework products, required DocC coverage |
| `SwiftTUI/swift-tui-site` | Astro website, Cloudflare Pages deployment, docs composition, release landing pages | Framework implementation and package releases |

## Extraction Boundary

No Swift target leaves `swift-tui` in this split: every target in
`Package.swift` stays. Only TypeScript browser source (`@swifttui/web`,
`@swifttui/build`), the runnable examples, and the website move to sibling
repos. A Swift target is extracted only when a later, explicit decision
promotes its package-private seams into stable public API.

## Documentation Contract

Every externally linkable Swift product has DocC and is included in the public
web build. Example repositories are excluded from DocC coverage unless an
example becomes a published library product.

# Repository Split

SwiftTUI uses several GitHub repositories. `SwiftTUI/swift-tui` remains the
anchor for Swift releases.

## Consumer Contract

A terminal app or localhost browser app depends on `SwiftTUI/swift-tui` and
imports `SwiftTUI`. The package includes terminal launch and WebHost launch
through `SwiftTUIWebHostCLI`. The `--web` option selects a runtime mode.

`Tests/SwiftTUITests/SwiftTUIConvenienceImportTests.swift` protects this contract
with an `App, SwiftTUICommand` fixture that represents a consumer. This split
moves browser TypeScript, examples, and site deployment out of this repository.
Downstream apps do not need extra SwiftPM dependencies or direct imports of
lower-level SwiftTUI products.

## Repository Ownership

| Repository | Owns | Does not own |
| --- | --- | --- |
| `SwiftTUI/swift-tui` | SwiftPM products, runtime, terminal CLI, WebHost Swift runner, WASI Swift runner, embedded WebHost browser bundle, Swift DocC source | Website deployment, example regression matrix after extraction, TypeScript browser source after extraction |
| `SwiftTUI/swift-tui-web` | `@swifttui/web`, `@swifttui/build`, browser runtime, WebHost browser bundle source, npm releases | SwiftPM products, Cloudflare site deployment |
| `SwiftTUI/swift-tui-examples` | Runnable examples, demo package tests, WebExample static deployment source | Public Swift framework products, required DocC coverage |
| `SwiftTUI/swift-tui-site` | Astro website, Cloudflare Pages deployment, docs composition, release landing pages | Framework implementation and package releases |

## Extraction Boundary

This split keeps every Swift target in `swift-tui`. Every target in
`Package.swift` stays. Only the TypeScript browser source (`@swifttui/web` and
`@swifttui/build`), runnable examples, and website move to sibling repositories.
A later explicit decision can extract a Swift target after its package-private
seams become stable public API.

## Documentation Contract

Every externally linkable Swift product provides DocC documentation. The public
web build includes this documentation. DocC coverage excludes example
repositories. When an example becomes a published library product, DocC
coverage includes its repository.

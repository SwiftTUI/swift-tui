# swift-figlet (vendored)

A reimplementation of figlet, distributed as a CLI and an SPM library, and
bundled with a curated set of fonts. SwiftTUI consumes it as the
`SwiftTUIVendorFiglet` / `SwiftTUIVendorFigletEmbeddedFonts` targets behind
the public `TextFigure` view. The embedded fonts let banner text answer normal
layout proposals without external font files.

## Provenance and license

Upstream: GoodHats LLC's `swift-figlet`. Licensed under the MIT License — see
[LICENSE](LICENSE) in this directory. The `Fonts/` directory carries the
curated FIGlet font set; individual FIGfonts retain their original headers.
These targets stay Foundation-free because the Foundation-free `SwiftTUIViews`
layer re-exports them (enforced by the repo's
`no-foundation-in-library-products` hook).

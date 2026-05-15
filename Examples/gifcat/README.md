# gifcat

`gifcat` is a small terminal-native GIF player. It loads the GIF paths passed
on the command line through the `AnimatedImage` library and shows them with
SwiftTUI's image renderer. Multiple GIFs are shown at their regular decoded
size, animated with their source frame delays, and tiled in row-major order with
one terminal cell between images.

## Demonstrates

- `SwiftTUIAnimatedImage` decoding and frame timing.
- Rendering image attachments through the standard SwiftTUI image surface.
- Argument-order-preserving layout for multiple animated inputs.
- A tiny app/library split: `GifCat` owns the view and `GifCatApp` owns the
  executable.

## Run

```bash
swiftly run swift run --package-path Examples/gifcat gifcat nyan.gif
swiftly run swift run --package-path Examples/gifcat gifcat first.gif second.gif third.gif
```

`Ctrl+D` exits.

## Test

```bash
swiftly run swift test --package-path Examples/gifcat
```

The tests cover input path normalization, row-major tiling, image attachment
placement, animated frame advancement, missing-file diagnostics, and empty
invocation usage text.

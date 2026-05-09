# gifcat

`gifcat` is a small terminal-native GIF player. It loads the GIF paths passed
on the command line through the `AnimatedImage` library and shows them with
SwiftTUI's image renderer. Multiple GIFs are shown at their regular decoded
size, animated with their source frame delays, and tiled in row-major order with
one terminal cell between images.

```bash
cd Examples/gifcat
swift run gifcat ../../nyan.gif
swift run gifcat first.gif second.gif third.gif
```

`Ctrl+D` exits.

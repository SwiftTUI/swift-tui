# ``SwiftTUIAnimatedImage``

Animate finite pre-composed image sequences and import or export GIFs.

## Overview

`SwiftTUIAnimatedImage` is included by the default `SwiftTUI` convenience
product and is also available as a standalone product for narrower
compositions. It keeps animated-image concerns out of the core runtime while
reusing the same `SwiftTUIViews` surface.

Create an animation from frames plus either a display frame rate or explicit
frame delays:

```swift
AnimatedImage(frames: frames, framesPerSecond: 12)
AnimatedImage(frames: frames, frameDelays: [.milliseconds(80), .milliseconds(120)])
```

The frame list is finite and fully pre-composed. The module does not provide
closure-based or arbitrary dynamic frame producers.

## Topics

### Views

- ``AnimatedImage``

### Sequences

- ``AnimatedImageSequence``
- ``AnimatedImageFrame``
- ``AnimatedImagePixel``

### GIF

- ``AnimatedGIF``

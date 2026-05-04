# ``SwiftTUIAnimatedImage``

Animate finite pre-composed image sequences and import or export GIFs.

## Overview

`SwiftTUIAnimatedImage` is a peer product to `SwiftTUICharts`. It keeps animated-image
concerns out of the core `SwiftTUI` runtime while reusing the same `SwiftTUIViews`
surface.

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

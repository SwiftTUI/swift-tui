@testable import SwiftTUIAnimatedImage
import Testing

/// F153 — `AnimatedImageSequence` caches each frame's encoded PNG bytes so
/// playback ticks stop re-running the encoder. These tests pin the cache
/// contract: cached bytes match a fresh encode, repeated reads serve the
/// same storage, and mutating `frames` invalidates.
@Suite
struct AnimatedImageEncodedCacheTests {
  private static func makeFrame(seed: UInt8) -> AnimatedImageFrame {
    let width = 8
    let height = 4
    let pixels = (0..<(width * height)).map { ordinal in
      AnimatedImagePixel(
        red: UInt8((ordinal + Int(seed)) % 256),
        green: seed,
        blue: UInt8(ordinal % 256),
        alpha: 255
      )
    }
    return AnimatedImageFrame(width: width, height: height, pixels: pixels)
  }

  @Test("cached bytes match a fresh per-frame encode")
  func cachedBytesMatchFreshEncode() {
    let sequence = AnimatedImageSequence(
      frames: [Self.makeFrame(seed: 1), Self.makeFrame(seed: 2)],
      framesPerSecond: 30
    )
    for index in sequence.frames.indices {
      #expect(sequence.encodedImageData(at: index) == sequence.frames[index].imageData)
    }
  }

  @Test("repeated reads serve the cached encoding")
  func repeatedReadsServeCachedStorage() {
    let sequence = AnimatedImageSequence(
      frames: [Self.makeFrame(seed: 3)],
      framesPerSecond: 30
    )
    let first = sequence.encodedImageData(at: 0)
    let second = sequence.encodedImageData(at: 0)
    // Same storage instance proves the second read was a cache hit rather
    // than a fresh encode (equal values could come from either).
    #expect(
      first.withUnsafeBufferPointer { firstBuffer in
        second.withUnsafeBufferPointer { secondBuffer in
          firstBuffer.baseAddress == secondBuffer.baseAddress
        }
      }
    )
  }

  @Test("mutating frames invalidates the cached encoding")
  func frameMutationInvalidates() {
    var sequence = AnimatedImageSequence(
      frames: [Self.makeFrame(seed: 4)],
      framesPerSecond: 30
    )
    let original = sequence.encodedImageData(at: 0)
    sequence.frames[0] = Self.makeFrame(seed: 5)
    let replaced = sequence.encodedImageData(at: 0)
    #expect(replaced != original)
    #expect(replaced == sequence.frames[0].imageData)
  }

  @Test("value copies never see a mutated copy's bytes")
  func valueCopiesStayIsolated() {
    let original = AnimatedImageSequence(
      frames: [Self.makeFrame(seed: 6)],
      framesPerSecond: 30
    )
    var mutated = original
    mutated.frames[0] = Self.makeFrame(seed: 7)
    #expect(original.encodedImageData(at: 0) == original.frames[0].imageData)
    #expect(mutated.encodedImageData(at: 0) == mutated.frames[0].imageData)
    #expect(original.encodedImageData(at: 0) != mutated.encodedImageData(at: 0))
  }

  @Test("equality and hashing ignore the cache population state")
  func equalitySpeaksForAuthoredValue() {
    let populated = AnimatedImageSequence(
      frames: [Self.makeFrame(seed: 8)],
      framesPerSecond: 30
    )
    _ = populated.encodedImageData(at: 0)
    let fresh = AnimatedImageSequence(
      frames: [Self.makeFrame(seed: 8)],
      framesPerSecond: 30
    )
    #expect(populated == fresh)
    #expect(populated.hashValue == fresh.hashValue)
  }
}

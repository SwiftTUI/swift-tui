import { expect, test } from "bun:test";

import {
  SharedInputQueueReader,
  SharedInputQueueWriter,
  createSharedInputQueue,
} from "./SharedInputQueue.ts";

test("shared input queue preserves write order across partial reads", () => {
  const queue = createSharedInputQueue(8);
  const writer = new SharedInputQueueWriter(queue);
  const reader = new SharedInputQueueReader(queue);

  writer.write("abcdef");

  expect(decode(reader.readAvailable(2))).toBe("ab");
  expect(decode(reader.readAvailable(4))).toBe("cdef");
  expect(reader.readAvailable(4)).toBeUndefined();
});

test("shared input queue wraps around the ring buffer", () => {
  const queue = createSharedInputQueue(8);
  const writer = new SharedInputQueueWriter(queue);
  const reader = new SharedInputQueueReader(queue);

  writer.write("abcdef");
  expect(decode(reader.readAvailable(4))).toBe("abcd");

  writer.write("gh");
  expect(decode(reader.readAvailable(4))).toBe("efgh");
  expect(reader.readAvailable(4)).toBeUndefined();
});

test("shared input queue reports EOF after close once buffered data is drained", () => {
  const queue = createSharedInputQueue(8);
  const writer = new SharedInputQueueWriter(queue);
  const reader = new SharedInputQueueReader(queue);

  writer.write("ok");
  writer.close();

  expect(decode(reader.readAvailable(8))).toBe("ok");
  expect(reader.readAvailable(8)).toBeUndefined();
  expect(reader.read(8)).toBeUndefined();
});

function decode(
  chunk: Uint8Array | undefined
): string | undefined {
  return chunk ? new TextDecoder().decode(chunk) : undefined;
}

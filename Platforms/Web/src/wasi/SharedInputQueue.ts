const controlSlots = 3;

const enum ControlSlot {
  readIndex = 0,
  writeIndex = 1,
  closed = 2,
}

export const sharedInputQueueDefaultCapacity = 64 * 1024;

export interface SharedInputQueueBuffers {
  readonly controlBuffer: SharedArrayBuffer;
  readonly dataBuffer: SharedArrayBuffer;
}

interface SharedInputQueueState {
  readonly control: Int32Array;
  readonly data: Uint8Array;
}

export function createSharedInputQueue(
  capacity: number = sharedInputQueueDefaultCapacity
): SharedInputQueueBuffers {
  if (typeof SharedArrayBuffer === "undefined") {
    throw new Error(
      "SharedArrayBuffer is unavailable. Serve the app with COOP/COEP headers so browser WASI stdin can stay live."
    );
  }

  if (!Number.isInteger(capacity) || capacity <= 0) {
    throw new Error(`Shared input queue capacity must be a positive integer, received ${capacity}.`);
  }

  return {
    controlBuffer: new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * controlSlots),
    dataBuffer: new SharedArrayBuffer(capacity),
  };
}

export function hydrateSharedInputQueue(
  buffers: SharedInputQueueBuffers
): SharedInputQueueState {
  return {
    control: new Int32Array(buffers.controlBuffer),
    data: new Uint8Array(buffers.dataBuffer),
  };
}

export class SharedInputQueueWriter {
  private readonly queue: SharedInputQueueState;

  constructor(buffers: SharedInputQueueBuffers) {
    this.queue = hydrateSharedInputQueue(buffers);
  }

  write(chunk: Uint8Array | string): void {
    if (Atomics.load(this.queue.control, ControlSlot.closed) !== 0) {
      return;
    }

    const bytes = normalizeChunk(chunk);
    if (bytes.length == 0) {
      return;
    }

    const readIndex = Atomics.load(this.queue.control, ControlSlot.readIndex);
    const writeIndex = Atomics.load(this.queue.control, ControlSlot.writeIndex);
    const usedCapacity = writeIndex - readIndex;
    const availableCapacity = this.queue.data.length - usedCapacity;

    if (bytes.length > availableCapacity) {
      throw new Error(
        `Shared input queue overflow: cannot enqueue ${bytes.length} byte(s) into ${availableCapacity} byte(s) of free space.`
      );
    }

    writeToRingBuffer(this.queue.data, bytes, writeIndex);
    Atomics.store(this.queue.control, ControlSlot.writeIndex, writeIndex + bytes.length);
    Atomics.notify(this.queue.control, ControlSlot.writeIndex);
  }

  close(): void {
    Atomics.store(this.queue.control, ControlSlot.closed, 1);
    Atomics.notify(this.queue.control, ControlSlot.writeIndex);
  }
}

export class SharedInputQueueReader {
  private readonly queue: SharedInputQueueState;

  constructor(buffers: SharedInputQueueBuffers) {
    this.queue = hydrateSharedInputQueue(buffers);
  }

  read(maxBytes: number): Uint8Array | undefined {
    while (true) {
      const next = this.readAvailable(maxBytes);
      if (next) {
        return next;
      }

      if (this.isClosed()) {
        return undefined;
      }

      const writeIndex = Atomics.load(this.queue.control, ControlSlot.writeIndex);
      Atomics.wait(this.queue.control, ControlSlot.writeIndex, writeIndex);
    }
  }

  readAvailable(maxBytes: number): Uint8Array | undefined {
    if (!Number.isInteger(maxBytes) || maxBytes <= 0) {
      return new Uint8Array();
    }

    const readIndex = Atomics.load(this.queue.control, ControlSlot.readIndex);
    const writeIndex = Atomics.load(this.queue.control, ControlSlot.writeIndex);
    const availableBytes = writeIndex - readIndex;

    if (availableBytes <= 0) {
      return undefined;
    }

    const byteCount = Math.min(maxBytes, availableBytes);
    const chunk = readFromRingBuffer(this.queue.data, readIndex, byteCount);
    Atomics.store(this.queue.control, ControlSlot.readIndex, readIndex + byteCount);
    return chunk;
  }

  isClosed(): boolean {
    return Atomics.load(this.queue.control, ControlSlot.closed) !== 0;
  }
}

function normalizeChunk(
  chunk: Uint8Array | string
): Uint8Array {
  return typeof chunk == "string" ? new TextEncoder().encode(chunk) : new Uint8Array(chunk);
}

function writeToRingBuffer(
  buffer: Uint8Array,
  chunk: Uint8Array,
  startIndex: number
): void {
  const offset = startIndex % buffer.length;
  const firstSegmentLength = Math.min(chunk.length, buffer.length - offset);
  buffer.set(chunk.subarray(0, firstSegmentLength), offset);
  if (firstSegmentLength < chunk.length) {
    buffer.set(chunk.subarray(firstSegmentLength), 0);
  }
}

function readFromRingBuffer(
  buffer: Uint8Array,
  startIndex: number,
  byteCount: number
): Uint8Array {
  const chunk = new Uint8Array(byteCount);
  const offset = startIndex % buffer.length;
  const firstSegmentLength = Math.min(byteCount, buffer.length - offset);
  chunk.set(buffer.subarray(offset, offset + firstSegmentLength), 0);
  if (firstSegmentLength < byteCount) {
    chunk.set(buffer.subarray(0, byteCount - firstSegmentLength), firstSegmentLength);
  }
  return chunk;
}

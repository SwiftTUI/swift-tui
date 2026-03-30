export class StdIOPipe implements AsyncIterable<Uint8Array> {
  private readonly chunks: Uint8Array[] = [];
  private readonly waiters: Array<(value: IteratorResult<Uint8Array>) => void> = [];
  private readonly listeners = new Set<(chunk: Uint8Array) => void>();
  private closed = false;

  write(chunk: Uint8Array | string): void {
    if (this.closed) {
      return;
    }

    const bytes = typeof chunk === "string" ? new TextEncoder().encode(chunk) : new Uint8Array(chunk);
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter({ done: false, value: bytes });
      return;
    }

    this.chunks.push(bytes);
    for (const listener of this.listeners) {
      listener(bytes);
    }
  }

  close(): void {
    if (this.closed) {
      return;
    }

    this.closed = true;
    while (this.waiters.length > 0) {
      const waiter = this.waiters.shift();
      waiter?.({ done: true, value: undefined as never });
    }
  }

  async read(): Promise<Uint8Array | undefined> {
    const next = this.chunks.shift();
    if (next) {
      return next;
    }

    if (this.closed) {
      return undefined;
    }

    return await new Promise<Uint8Array | undefined>((resolve) => {
      this.waiters.push((result) => {
        resolve(result.done ? undefined : result.value);
      });
    });
  }

  subscribe(
    listener: (chunk: Uint8Array) => void
  ): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  async *[Symbol.asyncIterator](): AsyncIterator<Uint8Array> {
    while (true) {
      const next = await this.read();
      if (!next) {
        return;
      }
      yield next;
    }
  }
}

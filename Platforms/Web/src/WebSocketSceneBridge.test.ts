import { expect, test } from "bun:test";

import {
  WebSocketSceneBridge,
  webSocketSceneURL,
  type WebSocketSceneSocket,
} from "./WebSocketSceneBridge.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

class FakeWebSocket implements WebSocketSceneSocket {
  binaryType: BinaryType = "blob";
  readyState = 0;
  readonly sent: Uint8Array[] = [];
  closeCode?: number;
  closeReason?: string;

  private readonly listeners = new Map<string, Set<(event: unknown) => void>>();

  send(
    data: string | ArrayBufferLike | Blob | ArrayBufferView
  ): void {
    if (typeof data === "string") {
      this.sent.push(encoder.encode(data));
    } else if (data instanceof Uint8Array) {
      this.sent.push(new Uint8Array(data));
    } else if (data instanceof ArrayBuffer) {
      this.sent.push(new Uint8Array(data));
    } else if (ArrayBuffer.isView(data)) {
      this.sent.push(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
    } else {
      throw new Error("fake socket does not support Blob sends");
    }
  }

  close(
    code?: number,
    reason?: string
  ): void {
    this.closeCode = code;
    this.closeReason = reason;
    this.readyState = 3;
  }

  addEventListener(
    type: string,
    listener: (event: unknown) => void
  ): void {
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener);
    this.listeners.set(type, listeners);
  }

  removeEventListener(
    type: string,
    listener: (event: unknown) => void
  ): void {
    this.listeners.get(type)?.delete(listener);
  }

  open(): void {
    this.readyState = 1;
    this.emit("open", {});
  }

  message(
    data: unknown
  ): void {
    this.emit("message", { data });
  }

  private emit(
    type: string,
    event: unknown
  ): void {
    for (const listener of this.listeners.get(type) ?? []) {
      listener(event);
    }
  }
}

test("websocket scene URLs use the embedded host path and token", () => {
  expect(String(webSocketSceneURL({
    sceneId: "main",
    token: "test-token",
    baseURL: "http://127.0.0.1:9123/",
  }))).toBe("ws://127.0.0.1:9123/ws/scene/main?token=test-token");

  expect(String(webSocketSceneURL({
    sceneId: "main",
    token: "secure-token",
    baseURL: "https://localhost:9443/app/",
  }))).toBe("wss://localhost:9443/app/ws/scene/main?token=secure-token");
});

test("bridge decodes websocket output and sends queued input when the socket opens", async () => {
  const socket = new FakeWebSocket();
  const bridge = new WebSocketSceneBridge({
    sceneId: "main",
    token: "test-token",
    baseURL: "http://127.0.0.1:9123/",
    webSocketFactory: () => socket,
  });
  const frames: unknown[] = [];
  const text: string[] = [];

  bridge.bindOutput({
    presentSurface: (frame) => frames.push(frame),
    writeOutput: (chunk) => text.push(chunk),
  });

  bridge.resize(100, 32, 9, 18);
  expect(socket.sent).toHaveLength(0);

  socket.open();
  expect(decoder.decode(socket.sent[0])).toBe("\u001Eresize:100:32:9:18\n");

  socket.message(encoder.encode(
    '\u001Esurface:{"version":2,"width":2,"height":1,"styles":[null],"rows":[[]],'
      + '"accessibilityTree":[{"id":"root","rect":[0,0,2,1],"role":"group"}]}\n'
      + "legacy output\n"
  ));
  await Promise.resolve();

  expect(frames).toHaveLength(1);
  expect(frames[0]).toMatchObject({
    version: 2,
    width: 2,
    accessibilityTree: [{ id: "root", role: "group" }],
  });
  expect(text).toEqual(["legacy output\n"]);

  bridge.sendInput(encoder.encode("\u001Ekey:return:0\n"));
  expect(decoder.decode(socket.sent.at(-1))).toBe("\u001Ekey:return:0\n");

  bridge.dispose();
  expect(socket.closeCode).toBe(1000);
  expect(socket.closeReason).toBe("WebHost scene disposed");
});

test("bridge buffers output until a runtime binds a sink", async () => {
  const socket = new FakeWebSocket();
  const bridge = new WebSocketSceneBridge({
    sceneId: "main",
    token: "test-token",
    baseURL: "http://127.0.0.1:9123/",
    webSocketFactory: () => socket,
  });
  const frames: unknown[] = [];

  socket.message(encoder.encode(
    '\u001Esurface:{"version":1,"width":3,"height":1,"styles":[null],"rows":[[]]}\n'
  ));
  await Promise.resolve();

  bridge.bindOutput({
    presentSurface: (frame) => frames.push(frame),
  });

  expect(frames).toEqual([
    {
      version: 1,
      width: 3,
      height: 1,
      styles: [null],
      rows: [[]],
    },
  ]);
});

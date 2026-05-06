import {
  WebHostOutputDecoder,
  encodeRenderStyleControlMessage,
  encodeResizeControlMessage,
  type WebHostOutputRecord,
  type WebHostOutputSink,
} from "./WebHostSurfaceTransport.ts";
import type { WebHostTerminalStyle } from "./WebHostTerminalStyle.ts";
import type { WebHostSceneBridge } from "./WebHostSceneRuntime.ts";

export interface WebSocketSceneBridgeOptions {
  sceneId: string;
  token: string;
  baseURL?: string | URL;
  webSocketURL?: string | URL;
  webSocketFactory?: WebSocketSceneBridgeFactory;
}

export type WebSocketSceneBridgeFactory = (url: string | URL) => WebSocketSceneSocket;

export interface WebSocketSceneSocket {
  binaryType: BinaryType;
  readonly readyState: number;
  send(data: string | ArrayBufferLike | Blob | ArrayBufferView): void;
  close(code?: number, reason?: string): void;
  addEventListener(type: "open", listener: (event: Event) => void): void;
  addEventListener(type: "message", listener: (event: MessageEvent) => void): void;
  addEventListener(type: "close", listener: (event: CloseEvent) => void): void;
  addEventListener(type: "error", listener: (event: Event) => void): void;
  removeEventListener(type: "open", listener: (event: Event) => void): void;
  removeEventListener(type: "message", listener: (event: MessageEvent) => void): void;
  removeEventListener(type: "close", listener: (event: CloseEvent) => void): void;
  removeEventListener(type: "error", listener: (event: Event) => void): void;
}

const socketOpenState = 1;
const textEncoder = new TextEncoder();

export class WebSocketSceneBridge implements WebHostSceneBridge {
  readonly url: URL;

  private readonly socket: WebSocketSceneSocket;
  private readonly decoder = new WebHostOutputDecoder();
  private readonly queuedInput: Uint8Array[] = [];
  private readonly queuedOutput: WebHostOutputRecord[] = [];
  private sink?: WebHostOutputSink;
  private disposed = false;

  private readonly handleOpen = () => {
    this.flushQueuedInput();
  };

  private readonly handleMessage = (event: MessageEvent) => {
    void this.receive(event.data);
  };

  private readonly handleClose = () => {
    for (const record of this.decoder.flush()) {
      this.deliver(record);
    }
  };

  private readonly handleError = () => {};

  constructor(options: WebSocketSceneBridgeOptions) {
    this.url = webSocketSceneURL(options);
    this.socket = (options.webSocketFactory ?? defaultWebSocketFactory)(this.url);
    this.socket.binaryType = "arraybuffer";
    this.socket.addEventListener("open", this.handleOpen);
    this.socket.addEventListener("message", this.handleMessage);
    this.socket.addEventListener("close", this.handleClose);
    this.socket.addEventListener("error", this.handleError);
  }

  bindOutput(
    sink: WebHostOutputSink
  ): void {
    this.sink = sink;
    while (this.queuedOutput.length > 0) {
      this.deliver(this.queuedOutput.shift()!);
    }
  }

  resize(
    columns: number,
    rows: number,
    cellWidth?: number,
    cellHeight?: number
  ): void {
    this.sendInput(encodeResizeControlMessage(columns, rows, cellWidth, cellHeight));
  }

  updateRenderStyle(
    style: WebHostTerminalStyle
  ): void {
    this.sendInput(encodeRenderStyleControlMessage(style));
  }

  sendInput(
    chunk: Uint8Array
  ): void {
    if (this.disposed) {
      return;
    }

    const copy = new Uint8Array(chunk);
    if (this.socket.readyState === socketOpenState) {
      this.socket.send(copy);
    } else {
      this.queuedInput.push(copy);
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.socket.removeEventListener("open", this.handleOpen);
    this.socket.removeEventListener("message", this.handleMessage);
    this.socket.removeEventListener("close", this.handleClose);
    this.socket.removeEventListener("error", this.handleError);
    this.queuedInput.length = 0;
    this.queuedOutput.length = 0;
    this.socket.close(1000, "WebHost scene disposed");
  }

  private async receive(
    message: unknown
  ): Promise<void> {
    if (this.disposed) {
      return;
    }

    const bytes = await bytesFromWebSocketMessage(message);
    if (!bytes) {
      return;
    }

    for (const record of this.decoder.feed(bytes)) {
      this.deliver(record);
    }
  }

  private deliver(
    record: WebHostOutputRecord
  ): void {
    const sink = this.sink;
    if (!sink) {
      this.queuedOutput.push(record);
      return;
    }

    switch (record.type) {
    case "surface":
      sink.presentSurface(record.frame);
      break;
    case "text":
      sink.writeOutput?.(record.text);
      break;
    }
  }

  private flushQueuedInput(): void {
    if (this.disposed || this.socket.readyState !== socketOpenState) {
      return;
    }
    while (this.queuedInput.length > 0) {
      this.socket.send(this.queuedInput.shift()!);
    }
  }
}

export function webSocketSceneURL(
  options: Pick<WebSocketSceneBridgeOptions, "baseURL" | "webSocketURL" | "sceneId" | "token">
): URL {
  if (options.webSocketURL) {
    const explicit = new URL(String(options.webSocketURL), currentPageURL());
    explicit.searchParams.set("token", options.token);
    return explicit;
  }

  const url = new URL(String(options.baseURL ?? currentPageURL()), currentPageURL());
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  const basePath = url.pathname.endsWith("/") ? url.pathname.slice(0, -1) : url.pathname;
  url.pathname = `${basePath}/ws/scene/${encodeURIComponent(options.sceneId)}`;
  url.search = "";
  url.searchParams.set("token", options.token);
  return url;
}

async function bytesFromWebSocketMessage(
  message: unknown
): Promise<Uint8Array | undefined> {
  if (typeof message === "string") {
    return textEncoder.encode(message);
  }
  if (message instanceof Uint8Array) {
    return message;
  }
  if (message instanceof ArrayBuffer) {
    return new Uint8Array(message);
  }
  if (ArrayBuffer.isView(message)) {
    return new Uint8Array(message.buffer, message.byteOffset, message.byteLength);
  }
  if (typeof Blob !== "undefined" && message instanceof Blob) {
    return new Uint8Array(await message.arrayBuffer());
  }
  return undefined;
}

function defaultWebSocketFactory(
  url: string | URL
): WebSocketSceneSocket {
  if (typeof WebSocket === "undefined") {
    throw new Error("WebSocket is not available");
  }
  return new WebSocket(url) as WebSocketSceneSocket;
}

function currentPageURL(): string {
  return globalThis.location?.href ?? "http://127.0.0.1/";
}

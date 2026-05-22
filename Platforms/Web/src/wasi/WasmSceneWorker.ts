import { ConsoleStdout, Fd, WASI, wasi } from "@bjorn3/browser_wasi_shim";
import {
  SharedInputQueueReader,
  type SharedInputQueueBuffers,
} from "./SharedInputQueue.ts";

export interface StartWasmSceneWorkerMessage {
  type: "start";
  wasmURL: string;
  environment: Record<string, string>;
  inputQueue: SharedInputQueueBuffers;
}

export interface OutputWasmSceneWorkerMessage {
  type: "stdout" | "stderr";
  chunk: Uint8Array;
}

export interface ExitWasmSceneWorkerMessage {
  type: "exit";
  code: number;
}

export interface ErrorWasmSceneWorkerMessage {
  type: "error";
  message: string;
}

export type WasmSceneWorkerMessage = StartWasmSceneWorkerMessage;
export type WasmSceneWorkerResponse =
  | OutputWasmSceneWorkerMessage
  | ExitWasmSceneWorkerMessage
  | ErrorWasmSceneWorkerMessage;

export function startWasmSceneWorker(): void {
  globalThis.addEventListener("message", (event: MessageEvent<WasmSceneWorkerMessage>) => {
    if (event.data.type !== "start") {
      return;
    }

    void startWasmScene(event.data);
  });
}

class BlockingInputFileDescriptor extends Fd {
  private readonly reader: SharedInputQueueReader;
  private readonly fdstat = (() => {
    const fdstat = new wasi.Fdstat(wasi.FILETYPE_CHARACTER_DEVICE, 0);
    fdstat.fs_rights_base = BigInt(wasi.RIGHTS_FD_READ);
    return fdstat;
  })();

  constructor(inputQueue: SharedInputQueueBuffers) {
    super();
    this.reader = new SharedInputQueueReader(inputQueue);
  }

  override fd_fdstat_get(): { ret: number; fdstat: wasi.Fdstat } {
    return {
      ret: wasi.ERRNO_SUCCESS,
      fdstat: this.fdstat,
    };
  }

  override fd_filestat_get(): { ret: number; filestat: wasi.Filestat } {
    return {
      ret: wasi.ERRNO_SUCCESS,
      filestat: new wasi.Filestat(0n, wasi.FILETYPE_CHARACTER_DEVICE, 0n),
    };
  }

  override fd_read(size: number): { ret: number; data: Uint8Array } {
    const chunk = this.reader.readAvailable(size);
    if (chunk) {
      return {
        ret: wasi.ERRNO_SUCCESS,
        data: chunk,
      };
    }

    if (this.reader.isClosed()) {
      return {
        ret: wasi.ERRNO_SUCCESS,
        data: new Uint8Array(),
      };
    }

    return {
      ret: wasi.ERRNO_AGAIN,
      data: new Uint8Array(),
    };
  }
}

function installEfficientClockPoll(
  wasiBridge: WASI
): void {
  const originalPoll = wasiBridge.wasiImport.poll_oneoff;
  if (typeof originalPoll !== "function") {
    return;
  }

  if (typeof SharedArrayBuffer === "undefined" || typeof Atomics.wait !== "function") {
    return;
  }

  const waitBuffer = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT));
  wasiBridge.wasiImport.poll_oneoff = (inPtr: number, outPtr: number, nsubscriptions: number) => {
    if (nsubscriptions !== 1) {
      return originalPoll(inPtr, outPtr, nsubscriptions);
    }

    const memory = wasiBridge.inst?.exports.memory;
    if (!memory) {
      return originalPoll(inPtr, outPtr, nsubscriptions);
    }

    const view = new DataView(memory.buffer);
    const subscription = wasi.Subscription.read_bytes(view, inPtr);
    if (subscription.eventtype !== wasi.EVENTTYPE_CLOCK) {
      return originalPoll(inPtr, outPtr, nsubscriptions);
    }

    const now = () => {
      switch (subscription.clockid) {
      case wasi.CLOCKID_MONOTONIC:
        return BigInt(Math.round(performance.now() * 1_000_000));
      case wasi.CLOCKID_REALTIME:
        return BigInt(Date.now()) * 1_000_000n;
      default:
        return undefined;
      }
    };

    const start = now();
    if (start === undefined) {
      return wasi.ERRNO_INVAL;
    }

    const deadline = (subscription.flags & wasi.SUBCLOCKFLAGS_SUBSCRIPTION_CLOCK_ABSTIME) !== 0
      ? subscription.timeout
      : start + subscription.timeout;
    const remainingNanoseconds = deadline - start;
    if (remainingNanoseconds > 0n) {
      Atomics.wait(
        waitBuffer,
        0,
        0,
        Math.min(Number(remainingNanoseconds) / 1_000_000, 2_147_483_647)
      );
    }

    new wasi.Event(
      subscription.userdata,
      wasi.ERRNO_SUCCESS,
      subscription.eventtype
    ).write_bytes(view, outPtr);
    return wasi.ERRNO_SUCCESS;
  };
}

async function startWasmScene(
  message: StartWasmSceneWorkerMessage
): Promise<void> {
  try {
    const wasiBridge = new WASI(
      ["app.wasm"],
      Object.entries(message.environment).map(([key, value]) => `${key}=${value}`),
      [
        new BlockingInputFileDescriptor(message.inputQueue),
        new ConsoleStdout((chunk) => {
          postWorkerMessage({
            type: "stdout",
            chunk,
          });
        }),
        new ConsoleStdout((chunk) => {
          postWorkerMessage({
            type: "stderr",
            chunk,
          });
        }),
      ]
    );
    installEfficientClockPoll(wasiBridge);

    const response = await fetch(message.wasmURL);
    if (!response.ok) {
      throw new Error(`failed to load ${message.wasmURL}: ${response.status} ${response.statusText}`);
    }

    const module = await WebAssembly.compile(await response.arrayBuffer());
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: wasiBridge.wasiImport,
    });

    const exitCode = wasiBridge.start(instance as WebAssembly.Instance);
    postWorkerMessage({
      type: "exit",
      code: exitCode,
    });
  } catch (error) {
    postWorkerMessage({
      type: "error",
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

function postWorkerMessage(
  message: WasmSceneWorkerResponse
): void {
  globalThis.postMessage(message);
}

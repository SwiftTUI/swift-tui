import { BrowserWASIBridge } from "./wasi/BrowserWASIBridge.ts";
import {
  WebSocketSceneBridge,
  type WebSocketSceneBridgeOptions,
} from "./WebSocketSceneBridge.ts";
import {
  loadWebHostSceneManifest,
  normalizeWebHostSceneManifest,
  type WebHostSceneDescriptor,
  type WebHostSceneManifest,
  type WebHostSceneManifestSource,
} from "./WebHostSceneManifest.ts";
import {
  mergeWebHostTerminalStyle,
  normalizeWebHostTerminalStyle,
  type ResolvedWebHostTerminalStyle,
  type WebHostTerminalStyle,
} from "./WebHostTerminalStyle.ts";
import {
  WebHostSceneRuntime,
  type WebHostSceneBridge,
  type WebHostSceneRuntimeOptions,
} from "./WebHostSceneRuntime.ts";

export interface WebHostEmbeddedHostConfig {
  token: string;
  webSocketBaseURL?: string | URL;
  webSocketFactory?: WebSocketSceneBridgeOptions["webSocketFactory"];
}

export interface WebHostBridgeFactoryOptions {
  sceneId: string;
  descriptor: WebHostSceneDescriptor;
  style: WebHostTerminalStyle;
  environment?: Record<string, string>;
}

export type WebHostBridgeFactory = (options: WebHostBridgeFactoryOptions) => WebHostSceneBridge;

export interface WebHostAppOptions {
  mount: HTMLElement;
  manifest?: WebHostSceneManifestSource;
  manifestUrl?: string | URL;
  initialSceneId?: string;
  style?: WebHostTerminalStyle;
  environment?: Record<string, string>;
  embeddedHost?: WebHostEmbeddedHostConfig;
  bridgeFactory?: WebHostBridgeFactory;
  createElement?: (tagName: string) => HTMLElement;
  sceneRuntimeFactory?: (options: WebHostSceneRuntimeOptions) => WebHostSceneRuntime;
}

export interface WebHostAppController {
  scenes: WebHostSceneDescriptor[];
  selectedSceneId: string;
  switchScene(id: string): Promise<void>;
  setStyle(style: WebHostTerminalStyle): void;
  dispose(): Promise<void>;
}

type RuntimeFactory = (options: WebHostSceneRuntimeOptions) => WebHostSceneRuntime;

export async function createWebHostApp(
  options: WebHostAppOptions
): Promise<WebHostAppController> {
  const manifest = await resolveManifest(options);
  const controller = new InternalWebHostAppController({
    mount: options.mount,
    manifest,
    style: options.style,
    environment: options.environment,
    embeddedHost: options.embeddedHost,
    bridgeFactory: options.bridgeFactory,
    initialSceneId: options.initialSceneId,
    createElement: options.createElement,
    sceneRuntimeFactory: options.sceneRuntimeFactory ?? ((runtimeOptions) => new WebHostSceneRuntime(runtimeOptions)),
  });
  await controller.initialize();
  return controller;
}

class InternalWebHostAppController implements WebHostAppController {
  readonly scenes: WebHostSceneDescriptor[];
  selectedSceneId: string;

  private readonly mount: HTMLElement;
  private readonly sceneRoot: HTMLElement;
  private style: ResolvedWebHostTerminalStyle;
  private readonly environment?: Record<string, string>;
  private readonly embeddedHost?: WebHostEmbeddedHostConfig;
  private readonly bridgeFactory?: WebHostBridgeFactory;
  private readonly sceneRuntimeFactory: RuntimeFactory;
  private readonly runtimes = new Map<string, WebHostSceneRuntime>();
  private readonly bridges = new Map<string, WebHostSceneBridge>();

  constructor(options: {
    mount: HTMLElement;
    manifest: WebHostSceneManifest;
    style?: WebHostTerminalStyle;
    environment?: Record<string, string>;
    embeddedHost?: WebHostEmbeddedHostConfig;
    bridgeFactory?: WebHostBridgeFactory;
    initialSceneId?: string;
    createElement?: (tagName: string) => HTMLElement;
    sceneRuntimeFactory: RuntimeFactory;
  }) {
    this.mount = options.mount;
    this.style = normalizeWebHostTerminalStyle(options.style ?? {});
    this.environment = options.environment;
    this.embeddedHost = options.embeddedHost;
    this.bridgeFactory = options.bridgeFactory;
    this.sceneRuntimeFactory = options.sceneRuntimeFactory;
    this.scenes = options.manifest.scenes;
    this.selectedSceneId =
      options.initialSceneId &&
      options.manifest.scenes.some((scene) => scene.id === options.initialSceneId)
        ? options.initialSceneId
        : options.manifest.scenes.find((scene) => scene.id === options.manifest.defaultSceneId)?.id ??
          options.manifest.defaultSceneId;

    this.sceneRoot = (options.createElement ?? defaultCreateElement)("div");
    this.sceneRoot.className = "webhost-scene-root";
    this.mount.replaceChildren(this.sceneRoot);
    this.applyHostFrameStyle();
  }

  async initialize(): Promise<void> {
    await this.ensureRuntime(this.selectedSceneId);
    await this.switchScene(this.selectedSceneId);
  }

  async switchScene(
    id: string
  ): Promise<void> {
    const descriptor = this.scenes.find((scene) => scene.id === id);
    if (!descriptor) {
      throw new Error(`Unknown scene: ${id}`);
    }

    for (const [sceneId, runtime] of this.runtimes) {
      runtime.setVisible(sceneId === id);
    }

    const runtime = await this.ensureRuntime(id);
    runtime.setVisible(true);
    this.selectedSceneId = id;
  }

  setStyle(
    style: WebHostTerminalStyle
  ): void {
    const merged = mergeWebHostTerminalStyle(this.style, style);
    this.style = merged;

    for (const runtime of this.runtimes.values()) {
      runtime.setStyle(this.style);
    }
    this.applyHostFrameStyle();
  }

  async dispose(): Promise<void> {
    for (const runtime of this.runtimes.values()) {
      runtime.dispose();
    }
    for (const bridge of this.bridges.values()) {
      bridge.dispose();
    }
    this.runtimes.clear();
    this.bridges.clear();
    this.mount.replaceChildren();
  }

  private async ensureRuntime(
    id: string
  ): Promise<WebHostSceneRuntime> {
    const existing = this.runtimes.get(id);
    if (existing) {
      return existing;
    }

    const descriptor = this.scenes.find((scene) => scene.id === id);
    if (!descriptor) {
      throw new Error(`Unknown scene: ${id}`);
    }

    const bridge = this.makeBridge(id, descriptor);
    const runtime = this.sceneRuntimeFactory({
      mount: this.sceneRoot,
      descriptor,
      style: this.style,
      bridge,
      onInput: (chunk) => bridge.sendInput(chunk),
    });

    this.bridges.set(id, bridge);
    this.runtimes.set(id, runtime);
    await runtime.mount();
    runtime.setVisible(id === this.selectedSceneId);
    return runtime;
  }

  private makeBridge(
    sceneId: string,
    descriptor: WebHostSceneDescriptor
  ): WebHostSceneBridge {
    if (this.bridgeFactory) {
      return this.bridgeFactory({
        sceneId,
        descriptor,
        style: this.style,
        environment: this.environment,
      });
    }

    if (this.embeddedHost) {
      return new WebSocketSceneBridge({
        sceneId,
        token: this.embeddedHost.token,
        baseURL: this.embeddedHost.webSocketBaseURL,
        webSocketFactory: this.embeddedHost.webSocketFactory,
      });
    }

    return new BrowserWASIBridge({
      sceneId,
      columns: 80,
      rows: 24,
      environment: this.environment,
      renderStyle: this.style,
    });
  }

  private applyHostFrameStyle(): void {
    this.mount.style.background = "linear-gradient(180deg, #0f172a 0%, #111827 100%)";
    this.mount.style.minHeight = "100%";
    this.mount.style.display = "block";
    this.mount.style.padding = "1rem";
  }
}

function defaultCreateElement(
  tagName: string
): HTMLElement {
  if (typeof document === "undefined") {
    throw new Error("document is not available");
  }

  return document.createElement(tagName);
}

async function resolveManifest(
  options: WebHostAppOptions
): Promise<WebHostSceneManifest> {
  if (options.manifest) {
    return loadWebHostSceneManifest(options.manifest);
  }

  if (options.manifestUrl) {
    return loadWebHostSceneManifest(options.manifestUrl);
  }

  return normalizeWebHostSceneManifest([
    {
      id: "main",
      title: "Main",
      isDefault: true,
    },
  ]);
}

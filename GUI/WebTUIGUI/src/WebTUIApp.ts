import { BrowserWASIBridge } from "./wasi/BrowserWASIBridge.ts";
import {
  loadWebTUISceneManifest,
  normalizeWebTUISceneManifest,
  type WebTUISceneDescriptor,
  type WebTUISceneManifest,
  type WebTUISceneManifestSource,
} from "./WebTUISceneManifest.ts";
import {
  mergeWebTUITerminalStyle,
  normalizeWebTUITerminalStyle,
  resolveWebTUIColorScheme,
  type ResolvedWebTUITerminalStyle,
  type WebTUIColorScheme,
  type WebTUITerminalStyle,
} from "./WebTUITerminalStyle.ts";
import { WebTUISceneRuntime, type WebTUISceneRuntimeOptions } from "./WebTUISceneRuntime.ts";

export interface WebTUIAppOptions {
  mount: HTMLElement;
  manifest?: WebTUISceneManifestSource;
  manifestUrl?: string | URL;
  initialSceneId?: string;
  style?: WebTUITerminalStyle;
  environment?: Record<string, string>;
  createElement?: (tagName: string) => HTMLElement;
  sceneRuntimeFactory?: (options: WebTUISceneRuntimeOptions) => WebTUISceneRuntime;
}

export interface WebTUIAppController {
  scenes: WebTUISceneDescriptor[];
  selectedSceneId: string;
  switchScene(id: string): Promise<void>;
  setStyle(style: WebTUITerminalStyle): void;
  dispose(): Promise<void>;
}

type RuntimeFactory = (options: WebTUISceneRuntimeOptions) => WebTUISceneRuntime;

export async function createWebTUIApp(
  options: WebTUIAppOptions
): Promise<WebTUIAppController> {
  const manifest = await resolveManifest(options);
  const controller = new InternalWebTUIAppController({
    mount: options.mount,
    manifest,
    style: options.style,
    environment: options.environment,
    initialSceneId: options.initialSceneId,
    createElement: options.createElement,
    sceneRuntimeFactory: options.sceneRuntimeFactory ?? ((runtimeOptions) => new WebTUISceneRuntime(runtimeOptions)),
  });
  await controller.initialize();
  return controller;
}

class InternalWebTUIAppController implements WebTUIAppController {
  readonly scenes: WebTUISceneDescriptor[];
  selectedSceneId: string;

  private readonly mount: HTMLElement;
  private readonly sceneRoot: HTMLElement;
  private style: ResolvedWebTUITerminalStyle;
  private readonly environment?: Record<string, string>;
  private readonly sceneRuntimeFactory: RuntimeFactory;
  private readonly runtimes = new Map<string, WebTUISceneRuntime>();
  private readonly bridges = new Map<string, BrowserWASIBridge>();
  private currentColorScheme: WebTUIColorScheme;
  private colorSchemeMediaQuery?: MediaQueryList;
  private readonly colorSchemeListener = () => {
    const nextScheme = this.resolveActiveColorScheme();
    if (nextScheme === this.currentColorScheme) {
      return;
    }

    this.currentColorScheme = nextScheme;
    for (const runtime of this.runtimes.values()) {
      runtime.setStyleAndScheme(this.style, this.currentColorScheme);
    }
  };

  constructor(options: {
    mount: HTMLElement;
    manifest: WebTUISceneManifest;
    style?: WebTUITerminalStyle;
    environment?: Record<string, string>;
    initialSceneId?: string;
    createElement?: (tagName: string) => HTMLElement;
    sceneRuntimeFactory: RuntimeFactory;
  }) {
    this.mount = options.mount;
    this.style = normalizeWebTUITerminalStyle(options.style ?? {});
    this.environment = options.environment;
    this.sceneRuntimeFactory = options.sceneRuntimeFactory;
    this.scenes = options.manifest.scenes;
    this.selectedSceneId =
      options.initialSceneId &&
      options.manifest.scenes.some((scene) => scene.id === options.initialSceneId)
        ? options.initialSceneId
        : options.manifest.scenes.find((scene) => scene.id === options.manifest.defaultSceneId)?.id ??
          options.manifest.defaultSceneId;
    this.currentColorScheme = this.resolveActiveColorScheme();

    this.sceneRoot = (options.createElement ?? defaultCreateElement)("div");
    this.sceneRoot.className = "webtuigui-scene-root";
    this.mount.replaceChildren(this.sceneRoot);
    this.applyHostFrameStyle();
  }

  async initialize(): Promise<void> {
    this.bindColorSchemeListener();
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
    style: WebTUITerminalStyle
  ): void {
    const merged = mergeWebTUITerminalStyle(this.style, style);
    this.style = merged;
    this.currentColorScheme = this.resolveActiveColorScheme();
    this.bindColorSchemeListener();

    for (const runtime of this.runtimes.values()) {
      runtime.setStyleAndScheme(this.style, this.currentColorScheme);
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
  ): Promise<WebTUISceneRuntime> {
    const existing = this.runtimes.get(id);
    if (existing) {
      return existing;
    }

    const descriptor = this.scenes.find((scene) => scene.id === id);
    if (!descriptor) {
      throw new Error(`Unknown scene: ${id}`);
    }

    const bridge = new BrowserWASIBridge({
      sceneId: id,
      columns: 80,
      rows: 24,
      environment: this.environment,
      renderStyle: this.style,
      colorScheme: this.currentColorScheme,
    });
    const runtime = this.sceneRuntimeFactory({
      mount: this.sceneRoot,
      descriptor,
      style: this.style,
      colorScheme: this.currentColorScheme,
      bridge,
      onInput: (chunk) => bridge.sendInput(chunk),
    });

    this.bridges.set(id, bridge);
    this.runtimes.set(id, runtime);
    await runtime.mount();
    runtime.setVisible(id === this.selectedSceneId);
    return runtime;
  }

  private resolveActiveColorScheme(): WebTUIColorScheme {
    return resolveWebTUIColorScheme(this.style, this.detectSystemColorScheme());
  }

  private detectSystemColorScheme(): WebTUIColorScheme {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return "dark";
    }

    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  private bindColorSchemeListener(): void {
    this.unbindColorSchemeListener();

    if (this.style.colorSchemeMode !== "system") {
      return;
    }

    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return;
    }

    this.colorSchemeMediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    this.colorSchemeMediaQuery.addEventListener("change", this.colorSchemeListener);
  }

  private unbindColorSchemeListener(): void {
    if (!this.colorSchemeMediaQuery) {
      return;
    }

    this.colorSchemeMediaQuery.removeEventListener("change", this.colorSchemeListener);
    this.colorSchemeMediaQuery = undefined;
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
  options: WebTUIAppOptions
): Promise<WebTUISceneManifest> {
  if (options.manifest) {
    return loadWebTUISceneManifest(options.manifest);
  }

  if (options.manifestUrl) {
    return loadWebTUISceneManifest(options.manifestUrl);
  }

  return normalizeWebTUISceneManifest([
    {
      id: "main",
      title: "Main",
      isDefault: true,
    },
  ]);
}

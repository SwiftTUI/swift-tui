import {
  createWebTUIApp,
  type WebTUIAppController,
} from "webtuigui";
import "./index.css";
import {
  defaultStyle,
  fallbackManifest,
  terminalAppManifestPath,
  terminalAppWasmPath,
} from "./app-data.ts";
import terminalShotUrl from "./assets/terminal-ui-capture.png";
import {
  createWasmSceneRuntimeFactory,
  type WasmSceneRuntimeHandle,
  type WasmSceneResizeEvent,
} from "./scene-runtime.ts";

declare global {
  interface Window {
    coi?: Record<string, unknown>;
  }
}

const coiServiceWorkerUrl = new URL("./coi-serviceworker.js", import.meta.url);
const terminalAppManifestUrl = new URL(terminalAppManifestPath, import.meta.url);
const terminalAppWasmUrl = new URL(terminalAppWasmPath, import.meta.url);
const minimumFrameWidth = 320;
const minimumFrameHeight = 240;
const backtabSequence = new TextEncoder().encode("\u001B[Z");
const repositoryUrl = "https://github.com/GoodHatsLLC/swift-terminal-ui";
const architectureUrl = `${repositoryUrl}/blob/main/docs/ARCHITECTURE.md`;
const runtimeUrl = `${repositoryUrl}/blob/main/docs/RUNTIME.md`;

const pipelinePhases = [
  "resolve",
  "measure",
  "place",
  "semantics",
  "draw",
  "raster",
  "commit",
];

const platformFrames = [
  {
    name: "Terminal",
    detail: "Alternate-screen, raw-mode, capability-aware output. The native runtime.",
    chrome: "platform-terminal",
  },
  {
    name: "macOS",
    detail: "SwiftUI host chrome via HostedSceneSession.",
    chrome: "platform-macos",
  },
  {
    name: "iOS",
    detail: "Same surface, native app chrome, touch input.",
    chrome: "platform-ios",
  },
  {
    name: "Web",
    detail: "WASI build mounted in the browser via WebTUIGUI.",
    chrome: "platform-web",
  },
];

const parityPoints = [
  {
    title: "Same authoring surface",
    body:
      "@State, @Binding, @FocusState, environment values, Layout protocol, Scene declarations. The types you already know.",
  },
  {
    title: "Same layout contract",
    body:
      "Parents propose, children choose. Modifier order matters. Measurement and placement are recursive — no terminal shortcuts.",
  },
  {
    title: "Same identity model",
    body:
      "State keyed by tree identity + source location. View-local state survives rerenders exactly as SwiftUI authors expect.",
  },
  {
    title: "Terminal-native runtime",
    body:
      "Input parsing, focus routing, alternate-screen ownership, lifecycle staging, commit planning, and incremental presentation.",
  },
];

const syntaxSample = `import TerminalUI
import TerminalUICLI

@main
struct DeployApp: App {
  @State private var releases = 18

  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      VStack(alignment: .leading, spacing: 1) {
        Text("Deploy Queue").bold()
        ProgressView("Release", value: Double(releases), total: 24)
        Button("Ship it") { releases += 1 }
      }
      .padding(1)
    }
  }
}`;

if (await ensureCrossOriginIsolation()) {
  await bootstrap();
}

async function ensureCrossOriginIsolation(): Promise<boolean> {
  if (typeof window === "undefined") {
    return true;
  }

  if (window.crossOriginIsolated !== false) {
    return true;
  }

  if (!window.isSecureContext || !("serviceWorker" in navigator)) {
    return true;
  }

  const root = document.querySelector<HTMLDivElement>("#root");
  if (root) {
    root.innerHTML = `
      <div class="page-shell">
        <main class="marketing-site">
          <section class="hero" id="top">
            <div class="hero-copy">
              <p class="eyebrow">Preparing browser runtime</p>
              <h1>Enabling cross-origin isolation…</h1>
              <p class="hero-lede">
                GitHub Pages cannot set the COOP/COEP headers this demo needs, so the page is
                installing a small service worker workaround and will reload once it is ready.
              </p>
            </div>
          </section>
        </main>
      </div>
    `;
  }

  window.coi = {
    ...(window.coi ?? {}),
    quiet: true,
  };

  await new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = coiServiceWorkerUrl.href;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error("failed to load COI service worker helper"));
    document.head.append(script);
  });

  await new Promise((resolve) => window.setTimeout(resolve, 50));
  return window.crossOriginIsolated !== false;
}

async function bootstrap(): Promise<void> {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) {
    throw new Error("missing root element");
  }

  root.innerHTML = `
    <div class="page-shell">
      <header class="site-header" data-reveal>
        <a class="brand" href="#top" aria-label="TerminalUI home">
          <span class="brand-mark">TerminalUI</span>
          <span class="brand-note">SwiftUI's authoring model for the terminal</span>
        </a>
        <nav class="site-nav" aria-label="Primary">
          <a href="#demo">Demo</a>
          <a href="#syntax">Syntax</a>
          <a href="#platforms">Platforms</a>
          <a href="#why-swiftui">Why SwiftUI</a>
        </nav>
        <a
          class="header-cta"
          href="${repositoryUrl}"
          target="_blank"
          rel="noreferrer"
        >
          GitHub
        </a>
      </header>

      <main class="marketing-site">
        <section class="hero" id="top">
          <div class="hero-copy" data-reveal>
            <p class="eyebrow">import TerminalUI</p>
            <h1>A real view system for the terminal.</h1>
            <p class="hero-lede">
              SwiftUI's authoring model — body-based views, recursive layout, identity-keyed state,
              focus routing — applied to terminal apps. Built on a strict 7-phase rendering pipeline.
            </p>
            <div class="pipeline-strip" aria-label="Rendering pipeline">
              ${renderPipeline()}
            </div>
            <div class="hero-actions">
              <a class="button button-primary" href="${repositoryUrl}" target="_blank" rel="noreferrer">
                Explore the repo
              </a>
              <a class="button button-secondary" href="${architectureUrl}" target="_blank" rel="noreferrer">
                Read the architecture
              </a>
            </div>
          </div>

          <div class="hero-stage" id="demo" data-reveal>
            <div class="hero-stage-header">
              <div>
                <p class="section-label">Live demo</p>
                <h2>The real app, running in the browser.</h2>
              </div>
              <p class="hero-stage-note">
                This is the actual WASI binary. Resize it and interact with the curated wasm-safe scene.
              </p>
            </div>

            <div class="terminal-shell">
              <div class="terminal-topline">
                <div class="terminal-topline-copy">
                  <span class="terminal-label">WebExample</span>
                  <span class="terminal-caption">TerminalUI running through WebTUIGUI</span>
                </div>
                <div class="scene-select" data-scenes aria-label="Scene selector"></div>
              </div>

              <div class="terminal-frame-shell">
                <div class="terminal-frame" data-terminal-frame>
                  <div class="terminal-host" data-terminal-host></div>
                </div>
              </div>

              <div class="terminal-resize-bar">
                <div class="terminal-status">
                  <span class="status-label">Live canvas</span>
                  <span class="status-item" data-status aria-live="polite">
                    Booting the browser demo…
                  </span>
                </div>
                <button
                  class="terminal-resize-handle"
                  data-resize-handle
                  type="button"
                  aria-label="Resize terminal demo"
                  title="Resize terminal demo"
                ></button>
              </div>
            </div>
          </div>
        </section>

        <section class="info-block info-block-syntax" id="syntax">
          <div class="info-copy" data-reveal>
            <p class="section-label">01 / Syntax</p>
            <h2>The DSL is SwiftUI. Not a sketch of it.</h2>
            <p>
              Views have bodies. State is identity-keyed. Layout is recursive — parents propose,
              children choose. It's not a string builder with SwiftUI names.
            </p>
          </div>

          <div class="info-panel" data-reveal>
            <pre class="code-sample"><code>${highlightSwift(syntaxSample)}</code></pre>
          </div>
        </section>

        <section class="info-block info-block-platforms" id="platforms">
          <div class="info-copy" data-reveal>
            <p class="section-label">02 / Platforms</p>
            <h2>One codebase. Terminal, macOS, iOS, web.</h2>
            <p>
              Same rendering pipeline, different host chrome. The terminal runtime, SwiftUI
              wrapper, and Bun-based web host all ship in the repo.
            </p>
          </div>

          <div class="platform-grid">
            ${renderPlatformFrames()}
          </div>
        </section>

        <section class="info-block info-block-parity" id="why-swiftui">
          <div class="info-copy" data-reveal>
            <p class="section-label">03 / SwiftUI parity</p>
            <h2>Parity in syntax and implementation.</h2>
            <p>
              Recursive layout. Structural environment propagation. Identity-based state.
              Scene ownership. Explicit lifecycle boundaries.
            </p>
          </div>

          <div class="parity-grid">
            ${renderParityPoints()}
          </div>
        </section>
        <section class="info-block closer" data-reveal>
          <p>SwiftUI ships on other platforms now.</p>
          <p>It just happens to be in a terminal.</p>
          <p class="closer-muted">You're welcome, Apple.</p>
        </section>
      </main>

      <footer class="site-footer" data-reveal>
        <span>TerminalUI</span>
        <div class="site-footer-links">
          <a href="${architectureUrl}" target="_blank" rel="noreferrer">Architecture</a>
          <a href="${runtimeUrl}" target="_blank" rel="noreferrer">Runtime</a>
          <a href="${repositoryUrl}" target="_blank" rel="noreferrer">GitHub</a>
        </div>
      </footer>
    </div>
  `;

  installRevealAnimations(root);

  const status = root.querySelector<HTMLElement>("[data-status]");
  const scenes = root.querySelector<HTMLElement>("[data-scenes]");
  const terminalFrame = root.querySelector<HTMLElement>("[data-terminal-frame]");
  const terminalHost = root.querySelector<HTMLElement>("[data-terminal-host]");
  const resizeHandle = root.querySelector<HTMLButtonElement>("[data-resize-handle]");

  if (!status || !scenes || !terminalFrame || !terminalHost || !resizeHandle) {
    throw new Error("failed to mount WebExample");
  }

  installResizeHandle(terminalFrame, resizeHandle);

  const sceneSizes = new Map<string, string>();
  const sceneRuntimes = new Map<string, WasmSceneRuntimeHandle>();
  let controller: WebTUIAppController | undefined;
  let manifestSource = "";
  const renderStatus = () => {
    if (!controller) {
      return;
    }

    const activeScene = controller.scenes.find((scene) => scene.id === controller?.selectedSceneId);
    const activeLabel = activeScene?.title ?? activeScene?.id ?? controller.selectedSceneId;
    const sizeLabel = sceneSizes.get(controller.selectedSceneId);
    terminalHost.dataset.sceneId = controller.selectedSceneId;
    terminalHost.dataset.size = sizeLabel ?? "";
    status.textContent = sizeLabel
      ? `${activeLabel} · ${sizeLabel}`
      : `${activeLabel} · loaded from ${manifestSource}`;
  };

  ({
    controller,
    manifestSource,
  } = await createController(
    terminalHost,
    (event) => {
      sceneSizes.set(event.sceneId, `${event.columns}x${event.rows}`);
      renderStatus();
    },
    (runtime) => {
      sceneRuntimes.set(runtime.descriptor.id, runtime);
    }
  ));
  installShiftTabPassthrough(terminalHost, () => controller, sceneRuntimes);
  const defaultScene = controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  renderSceneButtons(controller, scenes, () => {
    renderStatus();
  });

  if (controller.scenes.length > 0) {
    renderStatus();
  } else {
    status.textContent = "Terminal host loaded.";
  }
}

function renderPipeline(): string {
  return pipelinePhases
    .map((phase, i) => {
      const sep = i < pipelinePhases.length - 1 ? `<span class="pipeline-sep">\u2192</span>` : "";
      return `<span class="pipeline-phase">${phase}</span>${sep}`;
    })
    .join("");
}

function highlightSwift(code: string): string {
  const keywords = new Set(["import", "struct", "var", "private", "some"]);
  const types = new Set(["App", "Scene", "WindowGroup", "VStack", "Text", "ProgressView", "Button", "Double"]);

  // Single-pass tokenizer — each match is consumed once, no cascading.
  const pattern = /@\w+|"[^"]*?"|\.\w+(?=\()|(?<!\w)\d+(?:\.\d+)?(?!\w)|\b[A-Za-z_]\w*\b/g;

  const escaped = escapeHtml(code);
  return escaped.replace(pattern, (match) => {
    if (match.startsWith("@")) return `<span class="syn-at">${match}</span>`;
    if (match.startsWith('"')) return `<span class="syn-str">${match}</span>`;
    if (match.startsWith(".")) return `<span class="syn-prop">${match}</span>`;
    if (/^\d/.test(match)) return `<span class="syn-num">${match}</span>`;
    if (keywords.has(match)) return `<span class="syn-kw">${match}</span>`;
    if (types.has(match)) return `<span class="syn-type">${match}</span>`;
    return match;
  });
}

function renderPlatformFrames(): string {
  return platformFrames
    .map(
      (frame) => `
        <article class="platform-card" data-reveal>
          <div class="platform-visual ${frame.chrome}">
            <div class="platform-chrome">
              <span></span>
              <span></span>
              <span></span>
            </div>
            <img
              src="${terminalShotUrl}"
              alt="TerminalUI component gallery shown in ${frame.name} chrome"
            />
          </div>
          <div class="platform-copy">
            <h3>${frame.name}</h3>
            <p>${frame.detail}</p>
          </div>
        </article>
      `
    )
    .join("");
}

function renderParityPoints(): string {
  return parityPoints
    .map(
      (point) => `
        <article class="parity-card" data-reveal>
          <h3>${point.title}</h3>
          <p>${point.body}</p>
        </article>
      `
    )
    .join("");
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function installRevealAnimations(root: ParentNode): void {
  const revealTargets = Array.from(root.querySelectorAll<HTMLElement>("[data-reveal]"));
  if (revealTargets.length === 0) {
    return;
  }

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    for (const target of revealTargets) {
      target.dataset.visible = "true";
    }
    return;
  }

  for (const [index, target] of revealTargets.entries()) {
    target.style.transitionDelay = `${Math.min(index, 10) * 45}ms`;
  }

  requestAnimationFrame(() => {
    for (const target of revealTargets) {
      target.dataset.visible = "true";
    }
  });
}

async function createController(
  mount: HTMLElement,
  onSceneResize: (event: WasmSceneResizeEvent) => void,
  onRuntimeCreated: (runtime: WasmSceneRuntimeHandle) => void
): Promise<{ controller: WebTUIAppController; manifestSource: string }> {
  try {
    return {
      controller: await createWebTUIApp({
        mount,
        manifestUrl: terminalAppManifestUrl,
        style: defaultStyle,
        initialSceneId: "main",
        environment: {
          TUIGUI_APP_NAME: "Examples/WebExample",
        },
        sceneRuntimeFactory: createWasmSceneRuntimeFactory(terminalAppWasmUrl, {
          onSceneResize,
          onRuntimeCreated,
        }),
      }),
      manifestSource: "TerminalApp",
    };
  } catch (error) {
    console.warn("Falling back to the local preview manifest:", error);
    return {
      controller: await createWebTUIApp({
        mount,
        manifest: fallbackManifest,
        style: defaultStyle,
        initialSceneId: fallbackManifest.defaultSceneId,
      }),
      manifestSource: "fallback preview",
    };
  }
}

function installShiftTabPassthrough(
  terminalHost: HTMLElement,
  getController: () => WebTUIAppController | undefined,
  sceneRuntimes: ReadonlyMap<string, WasmSceneRuntimeHandle>
): void {
  const eventOptions = { capture: true } as const;

  terminalHost.addEventListener("keydown", (event) => {
    if (
      event.key !== "Tab" ||
      !event.shiftKey ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      event.defaultPrevented
    ) {
      return;
    }

    const path = typeof event.composedPath === "function" ? event.composedPath() : [];
    const eventOriginatedInTerminal =
      path.includes(terminalHost) ||
      (event.target instanceof Node && terminalHost.contains(event.target));
    if (!eventOriginatedInTerminal) {
      return;
    }

    const controller = getController();
    if (!controller) {
      return;
    }

    const runtime = sceneRuntimes.get(controller.selectedSceneId);
    if (!runtime) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    runtime.sendInput(backtabSequence);
  }, eventOptions);
}

function renderSceneButtons(
  controller: WebTUIAppController,
  container: HTMLElement,
  onSelectionChanged: () => void
): void {
  container.replaceChildren();

  if (controller.scenes.length === 0) {
    return;
  }

  const activeLabel = () => {
    const active = controller.scenes.find((s) => s.id === controller.selectedSceneId);
    return active?.title ?? active?.id ?? controller.selectedSceneId;
  };

  const trigger = document.createElement("button");
  trigger.type = "button";
  trigger.className = "scene-select-trigger";
  trigger.setAttribute("aria-haspopup", "listbox");
  trigger.setAttribute("aria-expanded", "false");
  trigger.innerHTML = `<span class="scene-select-label">Scene:</span> <span data-scene-value>${escapeHtml(activeLabel())}</span> <span class="scene-select-chevron"></span>`;

  const menu = document.createElement("div");
  menu.className = "scene-select-menu";
  menu.setAttribute("role", "listbox");
  menu.dataset.open = "false";

  for (const scene of controller.scenes) {
    const option = document.createElement("button");
    option.type = "button";
    option.className = "scene-select-option";
    option.setAttribute("role", "option");
    option.dataset.sceneId = scene.id;
    option.textContent = scene.title ?? scene.id;
    option.addEventListener("click", async () => {
      await controller.switchScene(scene.id);
      updateSceneSelection(controller, container);
      onSelectionChanged();
      closeMenu();
    });
    menu.append(option);
  }

  const closeMenu = () => {
    trigger.setAttribute("aria-expanded", "false");
    menu.dataset.open = "false";
  };

  trigger.addEventListener("click", () => {
    const isOpen = trigger.getAttribute("aria-expanded") === "true";
    trigger.setAttribute("aria-expanded", String(!isOpen));
    menu.dataset.open = String(!isOpen);
  });

  document.addEventListener("click", (event) => {
    if (!container.contains(event.target as Node)) {
      closeMenu();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && menu.dataset.open === "true") {
      closeMenu();
      trigger.focus();
    }
  });

  container.append(trigger, menu);
  updateSceneSelection(controller, container);
}

function updateSceneSelection(
  controller: WebTUIAppController,
  container: HTMLElement
): void {
  const valueEl = container.querySelector<HTMLElement>("[data-scene-value]");
  if (valueEl) {
    const active = controller.scenes.find((s) => s.id === controller.selectedSceneId);
    valueEl.textContent = active?.title ?? active?.id ?? controller.selectedSceneId;
  }

  for (const option of container.querySelectorAll<HTMLButtonElement>(".scene-select-option")) {
    const isActive = option.dataset.sceneId === controller.selectedSceneId;
    option.setAttribute("aria-selected", String(isActive));
  }
}

function installResizeHandle(
  frame: HTMLElement,
  handle: HTMLButtonElement
): void {
  let drag:
    | {
        pointerId: number;
        startX: number;
        startY: number;
        startWidth: number;
        startHeight: number;
      }
    | undefined;

  const stopDrag = (pointerId?: number) => {
    if (!drag || (pointerId !== undefined && drag.pointerId !== pointerId)) {
      return;
    }

    drag = undefined;
    document.body.classList.remove("is-resizing-terminal");
  };

  const resizeToPointer = (event: PointerEvent) => {
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }

    const width = Math.max(
      minimumFrameWidth,
      Math.round(drag.startWidth + event.clientX - drag.startX)
    );
    const height = Math.max(
      minimumFrameHeight,
      Math.round(drag.startHeight + event.clientY - drag.startY)
    );

    frame.style.width = `${width}px`;
    frame.style.height = `${height}px`;
  };

  handle.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) {
      return;
    }

    event.preventDefault();
    const rect = frame.getBoundingClientRect();
    drag = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      startWidth: rect.width,
      startHeight: rect.height,
    };
    document.body.classList.add("is-resizing-terminal");
    handle.setPointerCapture(event.pointerId);
  });

  handle.addEventListener("pointermove", resizeToPointer);
  handle.addEventListener("pointerup", (event) => {
    resizeToPointer(event);
    stopDrag(event.pointerId);
  });
  handle.addEventListener("pointercancel", (event) => {
    stopDrag(event.pointerId);
  });
  window.addEventListener("blur", () => {
    stopDrag();
  });
}

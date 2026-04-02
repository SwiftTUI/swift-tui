import {
  createWebTUIApp,
  type WebTUIAppController,
} from "../../../GUI/WebTUIGUI/src/WebTUIApp.ts";
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

const terminalAppManifestUrl = new URL(terminalAppManifestPath, location.href);
const terminalAppWasmUrl = new URL(terminalAppWasmPath, location.href);
const minimumFrameWidth = 320;
const minimumFrameHeight = 240;
const backtabSequence = new TextEncoder().encode("\u001B[Z");
const repositoryUrl = "https://github.com/GoodHatsLLC/swift-terminal-ui";
const architectureUrl = `${repositoryUrl}/blob/main/docs/ARCHITECTURE.md`;
const runtimeUrl = `${repositoryUrl}/blob/main/docs/RUNTIME.md`;

const syntaxTokens = [
  "View body",
  "@State",
  "@Binding",
  "@FocusState",
  "Layout",
  "WindowGroup",
];

const platformFrames = [
  {
    name: "Terminal",
    detail: "Interactive runtime with alternate-screen ownership, focus routing, and capability-aware output.",
    chrome: "platform-terminal",
  },
  {
    name: "macOS",
    detail: "SwiftUI host chrome wrapped around the same terminal UI through HostedSceneSession.",
    chrome: "platform-macos",
  },
  {
    name: "iOS",
    detail: "The same terminal surface can live inside native app chrome when you want mobile or touch-friendly hosting.",
    chrome: "platform-ios",
  },
  {
    name: "Web",
    detail: "The Bun host builds WebAssembly assets and mounts the app in the browser through WebTUIGUI.",
    chrome: "platform-web",
  },
];

const parityPoints = [
  {
    title: "Same authoring surface",
    body:
      "You write body-based View types with @State, @Binding, @FocusState, environment values, Layout, and Scene declarations.",
  },
  {
    title: "Same layout contract",
    body:
      "Parents propose. Children choose. Modifier order matters. Measurement and placement stay recursive instead of collapsing into a terminal-specific shortcut.",
  },
  {
    title: "Same identity and state model",
    body:
      "State is keyed by identity in the tree plus source location, so view-local state survives rerenders the same way SwiftUI authors expect.",
  },
  {
    title: "Terminal-native runtime where it belongs",
    body:
      "The extra machinery lives in the runtime: input parsing, focus routing, alternate-screen ownership, lifecycle staging, commit planning, and incremental presentation.",
  },
];

const syntaxSample = `import TerminalUI
import TerminalUIScenes

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

await bootstrap();

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
          <span class="brand-note">SwiftUI-shaped terminal apps in Swift</span>
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
            <p class="eyebrow">$ TerminalUI</p>
            <h1>SwiftUI syntax for terminal apps.</h1>
            <p class="hero-lede">
              Terminal apps are fun, useful, and still one of the best ways to ship sharp tools.
              TerminalUI makes them comfortable to author in Swift with a view system, layout
              model, focus environment, and runtime that deliberately echo SwiftUI.
            </p>
            <div class="token-row" aria-label="Core syntax">
              ${renderSyntaxTokens()}
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
                <h2>Center the app. Let the terminal do the talking.</h2>
              </div>
              <p class="hero-stage-note">
                This is the real wasm app running in the browser. Resize it, switch scenes, and type
                into it.
              </p>
            </div>

            <div class="terminal-shell">
              <div class="terminal-topline">
                <div class="terminal-topline-copy">
                  <span class="terminal-label">WebExample</span>
                  <span class="terminal-caption">TerminalUI running through WebTUIGUI</span>
                </div>
                <div class="scene-tabs" data-scenes aria-label="Scenes"></div>
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
            <h2>The DSL looks like SwiftUI because it is supposed to.</h2>
            <p>
              Views have bodies. State lives where you author it. Scenes describe windows.
              The goal is not a terminal-flavored mini language. The goal is to make terminal
              apps feel natural to people who already build SwiftUI.
            </p>
          </div>

          <div class="info-panel" data-reveal>
            <pre class="code-sample"><code>${escapeHtml(syntaxSample)}</code></pre>
          </div>
        </section>

        <section class="info-block info-block-platforms" id="platforms">
          <div class="info-copy" data-reveal>
            <p class="section-label">02 / Platforms</p>
            <h2>Build the same terminal UI for the terminal, native wrappers, and the web.</h2>
            <p>
              The repository already covers the runtime, the SwiftUI host for macOS and iOS, and
              the Bun-based web host. Same UI. Different chrome. Different place to live.
            </p>
          </div>

          <div class="platform-grid">
            ${renderPlatformFrames()}
          </div>
        </section>

        <section class="info-block info-block-parity" id="why-swiftui">
          <div class="info-copy" data-reveal>
            <p class="section-label">03 / SwiftUI parity</p>
            <h2>This is basically SwiftUI in syntax and implementation.</h2>
            <p>
              Not a string builder wearing SwiftUI names. The surface API matches, and the
              underlying model matches too: recursive layout, structural environment propagation,
              identity-based state, scene ownership, and explicit lifecycle boundaries.
            </p>
          </div>

          <div class="parity-grid">
            ${renderParityPoints()}
          </div>
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

function renderSyntaxTokens(): string {
  return syntaxTokens
    .map((token) => `<span class="token-chip">${token}</span>`)
    .join("");
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

  for (const scene of controller.scenes) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "scene-tab";
    button.dataset.sceneId = scene.id;
    button.textContent = scene.title ?? scene.id;
    button.addEventListener("click", async () => {
      await controller.switchScene(scene.id);
      updateSceneSelection(controller, container);
      onSelectionChanged();
    });
    container.append(button);
  }

  updateSceneSelection(controller, container);
}

function updateSceneSelection(
  controller: WebTUIAppController,
  container: HTMLElement
): void {
  for (const button of container.querySelectorAll<HTMLButtonElement>("button")) {
    const isActive = button.dataset.sceneId === controller.selectedSceneId;
    button.disabled = isActive;
    button.setAttribute("aria-pressed", String(isActive));
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

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

await bootstrap();

async function bootstrap(): Promise<void> {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) {
    throw new Error("missing root element");
  }

  root.innerHTML = `
    <div class="site-shell">
      <header class="site-header">
        <a class="brand" href="#top" aria-label="TerminalUI home">
          <span class="brand-mark">TUI</span>
          <span class="brand-copy">
            <strong>TerminalUI</strong>
            <span>SwiftUI-shaped terminal software</span>
          </span>
        </a>
        <nav class="site-nav" aria-label="Page">
          <a href="#live-terminal">Live terminal</a>
          <a href="#technical">Architecture</a>
          <a href="#capabilities">Capabilities</a>
        </nav>
      </header>

      <main>
        <section class="hero" id="top">
          <div class="hero-copy" data-reveal>
            <p class="eyebrow">Terminal software with real UI discipline</p>
            <h1>Build terminal apps like product software, not a pile of escape codes.</h1>
            <p class="hero-lede">
              TerminalUI brings SwiftUI-shaped authoring, a strict rendering pipeline, and
              terminal-native runtime behavior to serious interactive apps. The terminal in
              this hero is live, running inside the browser, and backed by the same scene
              system the framework ships for the web.
            </p>

            <div class="hero-actions">
              <a class="button button-primary" href="#technical">Read the architecture</a>
              <a class="button button-secondary" href="#live-terminal">Inspect the live app</a>
            </div>

            <div class="hero-highlights" aria-label="Project highlights">
              <div class="highlight-chip">SwiftUI-shaped View, State, Binding, Focus, Scene</div>
              <div class="highlight-chip">resolve → measure → place → semantics → draw → raster → commit</div>
              <div class="highlight-chip">Capability-aware output for preview, snapshot, and live terminals</div>
            </div>
          </div>

          <div class="hero-stage" data-hero-stage>
            <div class="hero-stage__grid" aria-hidden="true"></div>
            <div class="hero-stage__halo" aria-hidden="true"></div>

            <div class="terminal-shell" id="live-terminal" data-reveal>
              <div class="terminal-shell__shadow" aria-hidden="true"></div>
              <div class="terminal-shell__surface">
                <div class="terminal-chrome">
                  <div class="terminal-lights" aria-hidden="true">
                    <span></span>
                    <span></span>
                    <span></span>
                  </div>
                  <div class="terminal-chrome__title">WebExample / live terminal runtime</div>
                  <div class="terminal-chrome__meta">Swift Wasm + WebTUIGUI</div>
                </div>

                <div class="terminal-toolbar">
                  <div class="tabs" data-scenes></div>
                  <div class="terminal-toolbar__badge">Interactive scene host</div>
                </div>

                <div class="terminal-frame" data-terminal-frame>
                  <div class="terminal-host" data-terminal-host></div>
                </div>

                <div class="terminal-resize-bar">
                  <div class="status-cluster">
                    <div class="status-label">Active runtime</div>
                    <div data-status class="status-item" aria-live="polite">Booting ExampleApp…</div>
                  </div>
                  <button
                    type="button"
                    class="terminal-resize-handle"
                    data-resize-handle
                    aria-label="Resize terminal"
                  ></button>
                </div>
              </div>
            </div>

            <a class="scroll-prompt" href="#technical">Scroll for the technical breakdown</a>
          </div>
        </section>

        <section class="content-section content-section--intro" id="technical">
          <div class="section-heading" data-reveal>
            <p class="eyebrow">Technical description</p>
            <h2>A layered Swift package with a real frame pipeline behind every screen.</h2>
          </div>

          <div class="overview-grid">
            <article class="overview-copy" data-reveal>
              <p>
                TerminalUI is structured as layered products instead of one monolith.
                <strong>View</strong> handles SwiftUI-shaped authoring. <strong>Core</strong>
                keeps layout, semantics, draw extraction, rasterization, and commit planning pure.
                <strong>TerminalUI</strong> owns runtime coordination, terminal input, signal handling,
                focus routing, lifecycle staging, and incremental presentation.
              </p>
              <p>
                That separation lets the same authored interface move through a predictable
                resolve → measure → place → semantics → draw → raster → commit pipeline,
                then render for previews, tests, or live terminal sessions without collapsing
                everything into terminal-specific shortcuts.
              </p>
            </article>

            <div class="stat-stack">
              <article class="stat-card" data-reveal>
                <span class="stat-card__value">7 phases</span>
                <p>Strict frame pipeline with separate layout, semantics, draw, raster, and commit work.</p>
              </article>
              <article class="stat-card" data-reveal>
                <span class="stat-card__value">1 authoring story</span>
                <p>SwiftUI-shaped views, state, bindings, focus, layouts, environment, and scenes.</p>
              </article>
              <article class="stat-card" data-reveal>
                <span class="stat-card__value">Multiple hosts</span>
                <p>Preview text, snapshot tests, live terminals, and web-hosted scene wrappers all share the same artifacts.</p>
              </article>
            </div>
          </div>
        </section>

        <section class="content-section">
          <div class="section-heading" data-reveal>
            <p class="eyebrow">How the frame moves</p>
            <h2>Every render takes the same path from authored view tree to terminal cells.</h2>
          </div>

          <ol class="pipeline-grid" aria-label="Frame pipeline">
            <li class="pipeline-card" data-reveal>
              <span class="pipeline-card__step">01</span>
              <h3>Resolve</h3>
              <p>Lower authored views into a resolved tree with merged environment and structural expansion.</p>
            </li>
            <li class="pipeline-card" data-reveal>
              <span class="pipeline-card__step">02</span>
              <h3>Measure</h3>
              <p>Probe nodes under proposals so layout stays recursive, cacheable, and SwiftUI-faithful.</p>
            </li>
            <li class="pipeline-card" data-reveal>
              <span class="pipeline-card__step">03</span>
              <h3>Place</h3>
              <p>Commit final geometry for interaction regions, scroll extents, and later composition work.</p>
            </li>
            <li class="pipeline-card" data-reveal>
              <span class="pipeline-card__step">04</span>
              <h3>Semantics</h3>
              <p>Extract focus, action, selection, and scroll routes from the placed tree.</p>
            </li>
            <li class="pipeline-card" data-reveal>
              <span class="pipeline-card__step">05</span>
              <h3>Draw</h3>
              <p>Translate placed nodes into text, shape, rule, styling, and collection draw commands.</p>
            </li>
            <li class="pipeline-card" data-reveal>
              <span class="pipeline-card__step">06</span>
              <h3>Raster</h3>
              <p>Convert draw commands into a styled cell surface that stays separate from presentation decisions.</p>
            </li>
            <li class="pipeline-card" data-reveal>
              <span class="pipeline-card__step">07</span>
              <h3>Commit</h3>
              <p>Diff lifecycle and task work, then package the runtime-facing handlers after the frame is ready.</p>
            </li>
          </ol>
        </section>

        <section class="content-section" id="capabilities">
          <div class="section-heading" data-reveal>
            <p class="eyebrow">What it can do today</p>
            <h2>The current surface covers real application work, not just demos.</h2>
          </div>

          <div class="capability-grid">
            <article class="capability-card" data-reveal>
              <h3>Author with familiar SwiftUI patterns</h3>
              <p>
                Build body-only <code>View</code> types with <code>@State</code>, <code>@Binding</code>,
                <code>@FocusState</code>, custom <code>Layout</code>, environment modifiers,
                <code>WindowGroup</code>, and scene declarations.
              </p>
            </article>
            <article class="capability-card" data-reveal>
              <h3>Ship real interactive controls</h3>
              <p>
                Compose text, buttons, toggles, steppers, sliders, fields, disclosure groups,
                menus, tab views, list structures, tables, navigation splits, and progress or charting views.
              </p>
            </article>
            <article class="capability-card" data-reveal>
              <h3>Keep runtime behavior terminal-native</h3>
              <p>
                Alternate-screen ownership, keyboard and mouse input, signal handling, focus routing,
                lifecycle staging, task start or cancellation, and incremental presentation stay in the runtime layer.
              </p>
            </article>
            <article class="capability-card" data-reveal>
              <h3>Render for the host you have</h3>
              <p>
                Present the same frame artifacts as preview text, ASCII, ANSI16, ANSI256, true color,
                or wrapper-hosted web scenes without rewriting the authored interface.
              </p>
            </article>
            <article class="capability-card" data-reveal>
              <h3>Scale into multiple scenes</h3>
              <p>
                Use <code>TerminalUIScenes</code> for multi-scene orchestration, pty-backed sessions,
                discovery, attachment, and the public launch story for scene-based apps.
              </p>
            </article>
            <article class="capability-card" data-reveal>
              <h3>Build dashboards and operational surfaces</h3>
              <p>
                The separate <code>TerminalUICharts</code> track adds compact charts and metrics
                without distorting the core framework surface.
              </p>
            </article>
          </div>
        </section>

        <section class="content-section content-section--code">
          <div class="code-callout" data-reveal>
            <div class="section-heading">
              <p class="eyebrow">Swift entry point</p>
              <h2>From a scene declaration to a live terminal session.</h2>
            </div>

            <pre class="code-example"><code>import TerminalUI
import TerminalUIScenes

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      BuildSummary()
    }
  }
}</code></pre>
          </div>
        </section>
      </main>
    </div>
  `;

  const status = root.querySelector<HTMLElement>("[data-status]");
  const scenes = root.querySelector<HTMLElement>("[data-scenes]");
  const terminalFrame = root.querySelector<HTMLElement>("[data-terminal-frame]");
  const terminalHost = root.querySelector<HTMLElement>("[data-terminal-host]");
  const resizeHandle = root.querySelector<HTMLButtonElement>("[data-resize-handle]");
  const heroStage = root.querySelector<HTMLElement>("[data-hero-stage]");

  if (!status || !scenes || !terminalFrame || !terminalHost || !resizeHandle || !heroStage) {
    throw new Error("failed to mount WebExample");
  }

  installHeroTilt(heroStage);
  installRevealAnimations(root);
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
      ? `${activeLabel} · ${sizeLabel} · ${manifestSource}`
      : `Loading ${activeLabel} · ${manifestSource}`;
  };

  ({ controller, manifestSource } = await createController(terminalHost, (event) => {
    sceneSizes.set(event.sceneId, `${event.columns}x${event.rows}`);
    renderStatus();
  }, (runtime) => {
    sceneRuntimes.set(runtime.descriptor.id, runtime);
  }));
  installShiftTabPassthrough(terminalHost, () => controller, sceneRuntimes);
  const defaultScene = controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  renderSceneButtons(controller, scenes, () => {
    renderStatus();
  });

  if (controller.scenes.length > 0) {
    renderStatus();
  } else {
    status.textContent = "Loaded terminal host.";
  }
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

function installHeroTilt(stage: HTMLElement): void {
  const supportsMotion =
    !window.matchMedia("(prefers-reduced-motion: reduce)").matches &&
    window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  if (!supportsMotion) {
    return;
  }

  const reset = () => {
    stage.style.setProperty("--hero-tilt-x", "12deg");
    stage.style.setProperty("--hero-tilt-y", "-16deg");
    stage.style.setProperty("--hero-glow-x", "52%");
    stage.style.setProperty("--hero-glow-y", "38%");
  };

  reset();

  stage.addEventListener("pointermove", (event) => {
    const rect = stage.getBoundingClientRect();
    const offsetX = (event.clientX - rect.left) / rect.width - 0.5;
    const offsetY = (event.clientY - rect.top) / rect.height - 0.5;
    const tiltX = 12 - offsetY * 14;
    const tiltY = -16 + offsetX * 18;

    stage.style.setProperty("--hero-tilt-x", `${tiltX.toFixed(2)}deg`);
    stage.style.setProperty("--hero-tilt-y", `${tiltY.toFixed(2)}deg`);
    stage.style.setProperty("--hero-glow-x", `${(event.clientX - rect.left) / rect.width * 100}%`);
    stage.style.setProperty("--hero-glow-y", `${(event.clientY - rect.top) / rect.height * 100}%`);
  });

  stage.addEventListener("pointerleave", reset);
}

function installRevealAnimations(scope: ParentNode): void {
  const elements = Array.from(scope.querySelectorAll<HTMLElement>("[data-reveal]"));
  if (elements.length === 0) {
    return;
  }

  const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (prefersReducedMotion || typeof IntersectionObserver === "undefined") {
    for (const element of elements) {
      element.classList.add("is-visible");
    }
    return;
  }

  document.documentElement.classList.add("has-reveal-animations");

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) {
        continue;
      }

      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    }
  }, {
    threshold: 0.16,
    rootMargin: "0px 0px -8% 0px",
  });

  for (const element of elements) {
    observer.observe(element);
  }
}

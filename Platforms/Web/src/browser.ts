import { createWebHostApp, type WebHostTerminalStyle } from "./WebHostApp.ts";

declare global {
  interface Window {
    __WEBTUI__?: {
      manifestUrl?: string;
      initialSceneId?: string;
      style?: WebHostTerminalStyle;
    };
    __WEBTUI_APP__?: Awaited<ReturnType<typeof createWebHostApp>>;
  }
}

async function bootstrap(): Promise<void> {
  const mount = document.getElementById("webhost-root");
  if (!mount) {
    throw new Error("webhost root element not found");
  }

  const config = window.__WEBTUI__ ?? {};
  const controller = await createWebHostApp({
    mount,
    manifestUrl: config.manifestUrl ?? new URL("./scene-manifest.json", import.meta.url),
    initialSceneId: config.initialSceneId,
    style: config.style,
  });

  window.__WEBTUI_APP__ = controller;
}

void bootstrap();

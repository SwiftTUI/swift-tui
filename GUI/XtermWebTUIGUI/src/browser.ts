import "@xterm/xterm/css/xterm.css";
import { createWebTUIApp, type WebTUITerminalStyle } from "./WebTUIApp.ts";

declare global {
  interface Window {
    __WEBTUI__?: {
      manifestUrl?: string;
      initialSceneId?: string;
      style?: WebTUITerminalStyle;
    };
    __WEBTUI_APP__?: Awaited<ReturnType<typeof createWebTUIApp>>;
  }
}

async function bootstrap(): Promise<void> {
  const mount = document.getElementById("webtuigui-root");
  if (!mount) {
    throw new Error("webtuigui root element not found");
  }

  const config = window.__WEBTUI__ ?? {};
  const controller = await createWebTUIApp({
    mount,
    manifestUrl: config.manifestUrl ?? new URL("./scene-manifest.json", import.meta.url),
    initialSceneId: config.initialSceneId,
    style: config.style,
  });

  window.__WEBTUI_APP__ = controller;
}

void bootstrap();

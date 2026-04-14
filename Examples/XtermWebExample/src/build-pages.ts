import { cp, mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";

const webDist = resolve(import.meta.dir, "../dist");
const terminalAppDist = resolve(import.meta.dir, "../TerminalApp/dist");
const pagesDist = resolve(import.meta.dir, "../pages-dist");
const pagesTerminalAppDist = join(pagesDist, "TerminalApp", "dist");

await rm(pagesDist, { recursive: true, force: true });
await mkdir(pagesTerminalAppDist, { recursive: true });

await cp(webDist, pagesDist, { recursive: true });
await cp(terminalAppDist, pagesTerminalAppDist, { recursive: true });

await Bun.write(join(pagesDist, ".nojekyll"), "");

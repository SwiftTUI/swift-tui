import { serveBuiltWebExample } from "./built-app-server.ts";

const server = serveBuiltWebExample({
  port: Number(process.env.PORT ?? "3000"),
});

console.log(`WebExample running at ${server.url}`);

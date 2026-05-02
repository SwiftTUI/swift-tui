# Website

Stub Astro site that frames the
[`Examples/WebExample`](../Examples/WebExample) WASI demo in an iframe.
Deployed at <https://swifttui.io>.

The deploy workflow (`.github/workflows/cloudflare-pages.yml`) composes a
single Cloudflare Pages artifact:

```
/              <- this Astro site (Website/dist/)
/docs/         <- DocC archive
/webexample/   <- WebExample WASI demo
```

The iframe loads `/webexample/`, which is same-origin, so cross-origin
isolation propagates from the COOP/COEP headers in `public/_headers`.

## Local

```sh
bun install
bun run dev      # http://localhost:4321
bun run build    # outputs dist/
```

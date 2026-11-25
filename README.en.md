# Shence's Day — a DSH plugin

Puts a self-contained HTML text game into [DSH](https://github.com/deepseek-ai/deepseek-harness):
one extra panel in the DSH web sidebar, opened as a web island in DSH Go. The game itself is
unchanged and works offline.

## Install

In the app: search `@twilightrain/dsh-shence` in the plugin market and install it on the target host.

From a terminal on the machine that runs the engine:

```sh
dsh plugin --profile <your profile> add @twilightrain/dsh-shence
```

A local directory works too: `dsh plugin --profile <profile> add /absolute/path/dsh-shence`.

## How it attaches

- Host half (`lib/index.js`) does nothing: no tools, no files, no network.
- Browser half (`lib/client.js`) registers two surfaces in the DSH web client — the `main` panel
  `dsh-shence` and a `sidebar.panellist` row with the same id, so the row switches to the panel.
- The panel is a same-origin iframe whose `srcDoc` is `assets/game.html`, inlined as base64 at
  build time. No extra route is registered, so the plugin behaves the same on every host.

## Data and privacy

- No network: the page contains no `fetch`, `XMLHttpRequest` or external links; a test pins this.
- Saves stay local: only the game's own `localStorage` keys are written.
- "Clear save" lives inside the game. Uninstalling the plugin does not delete those keys.
- The iframe explicitly denies camera, microphone and geolocation.

## Compatibility

DSH `>=0.2.2-rc.1 <0.3.0-0`, Node 20+. On a phone the web island requires the local engine,
the bridge occupancy table and the resource budget; otherwise DSH falls back to "open in web
version" and the game still runs.

## Licence

The plugin code is MIT (`LICENSE`). The game's story text and event data are a derivative
creative work owned by the game's author and are not covered by the MIT grant.

Not an official DeepSeek release.

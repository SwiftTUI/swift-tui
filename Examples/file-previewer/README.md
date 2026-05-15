# File Previewer

Terminal file-browser example built from SwiftTUI views plus embedded terminal
processes.

The app opens on the current working directory, renders a Miller-column browser,
and previews the selected file by launching the appropriate external command in
a `TerminalView`.

## Demonstrates

- `SwiftTUITerminal` embedding through `TerminalProcessSession`.
- A Miller-column layout with deterministic width allocation.
- Preview command routing by file extension.
- Keeping navigation state, directory selection, and the active terminal process
  inside a normal SwiftTUI view tree.

Default preview commands:

| Extension | Command |
| --- | --- |
| `md` | `glow -s dark` |
| `json` | `jq -C .` |
| `yaml`, `yml`, `toml`, `swift` | `bat --color=always` |
| `png`, `jpg`, `jpeg`, `gif` | `chafa --symbols=block` |
| `zip` | `unzip -l` |
| `tar` | `tar -tvf` |
| everything else | `bat --color=always` |

Those tools are optional runtime dependencies of the example, not repo build
requirements.

## Run

```bash
swiftly run swift run --package-path Examples/file-previewer FilePreviewerApp
```

Run it from the directory you want to browse.

## Controls

| Key | Action |
| --- | --- |
| `Up` / `Down` | Move selection in the active column |
| `Right` / `Return` | Enter a directory or preview a file |
| `Left` | Move back to the parent column |

## Test

```bash
swiftly run swift test --package-path Examples/file-previewer
```

The tests cover preview-command lookup and Miller-column width allocation.

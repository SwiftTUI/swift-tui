# Todoist Terminal Demo

A small demo app that connects the local `TerminalUI` framework to Todoist, with
GRDB-backed caching and `swift-structured-queries` powered SQLite reads.

## Run

Run the executable package:

```bash
cd Examples/todoist
swift run todoist-demo
```

On first launch the demo presents a setup screen that:
- asks for a required Todoist API token
- stores it locally under Application Support
- initializes the local GRDB-backed SQLite cache

You can still bypass the setup prompt by exporting `TODOIST_API_TOKEN` before
launching the app.

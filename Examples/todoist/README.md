# Todoist Terminal Demo

A small demo app that connects the local `TerminalUI` framework to Todoist, with
GRDB-backed caching and `swift-structured-queries` powered SQLite reads.

## Run

Set a Todoist API token if you want live sync:

```bash
export TODOIST_API_TOKEN=...
```

Then run the executable package:

```bash
cd Examples/todoist
swift run todoist-demo
```

Without a token, the app still launches and reads whatever is already cached in
the local SQLite database.

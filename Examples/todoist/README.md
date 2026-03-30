# Todoist Terminal Demo

A small demo app that connects the local `TerminalUI` framework to Todoist, with
GRDB-backed caching and `swift-structured-queries` powered SQLite reads.

The example is intentionally pane-oriented: a project browser, task list, and
inspector share the full terminal canvas, and the workspace exercises canonical
confirmation flows and indeterminate sync feedback without falling back to
page-like scrolling. Its shell footer also mirrors the prototype help-strip
pattern through local example composition.

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

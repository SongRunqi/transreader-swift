# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build        # Compile with Swift Package Manager
make run          # Build + bundle + sign + launch app
make run-debug    # Build + run in terminal (logs visible in stdout)
make install      # Copy to /Applications/
make clean        # Remove .build/ and build/ directories
```

The Makefile handles the full pipeline: SPM build → .app bundle creation (Info.plist + entitlements) → ad-hoc codesign. Output lands in `build/TransReader.app`.

No external dependencies — uses only macOS system frameworks (SwiftUI, AppKit, Vision, SQLite3, Carbon).

**Requirements:** Swift 5.10+, macOS 14+, Xcode command-line tools.

## Architecture

TransReader is a **macOS menubar app** for reading assistance — it translates selected text, provides grammar analysis, OCR from screenshots, and dictionary lookups. It's a Swift rewrite of a Python predecessor, sharing the same `~/.transreader/` config format.

### Concurrency Model

The app uses Swift's **actor isolation** extensively:
- `AppState` (@Observable, @MainActor) — central state hub, owns all services
- `Translator`, `SelectionMonitor`, `OCREngine`, `GlobalHotkeys`, `DictionaryService` — all **actors** for thread-safe mutable state
- `TranslationStore`, `VocabStore` — marked `@unchecked Sendable` for legacy C API access (SQLite3, NSPasteboard)

### Data Flow

1. **Input sources**: Selection monitoring (AX API polling), OCR screenshots, clipboard paste, manual input
2. **Processing**: `Translator` streams responses from OpenAI-compatible APIs, incrementally parsing JSON into `Sentence` models with grammar `Analysis`/`Chunk` trees
3. **Output**: SwiftUI views display streaming translations; results persist to SQLite (`~/.transreader/translations.db`)

### Key Callbacks Pattern

`TransReaderApp` (the @main entry) wires hotkey actions to `AppState` methods via closures set at launch. Hotkeys trigger: capture+OCR translate, toggle window, toggle pin, enhance translate, paste translate, toggle monitor.

### Streaming Translation Protocol

The translator consumes OpenAI-compatible SSE streams (`data: {"choices":[{"delta":{"content":"..."}}]}`). It accumulates a JSON buffer, extracts complete sentence objects progressively, and throttles UI updates to 100ms intervals.

### User Data

All user data lives in `~/.transreader/`: `config.json` (settings), `vocab.canvas` (word list JSON), `translations.db` (SQLite history), `app.log`.

## Conventions

- **Logging**: Use the global `appLog()` function with subsystem prefixes like `[Monitor]`, `[Translate]`, `[AX]`, `[Hotkeys]`
- **Config compatibility**: `ConfigStore` must stay backward-compatible with the Python version's `config.json` format; use resilient decoding with sensible defaults for missing fields
- **StrictConcurrency**: Enabled as an experimental feature in Package.swift — all new code must be concurrency-safe

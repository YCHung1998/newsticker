# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

**Source of truth (2026-10-24):** `docs/superpowers/specs/2026-10-24-fastbull-ticker-design.md` plus the OpenSpec changes in `openspec/changes/` (5 changes, applied in order: `message-contract` → `connect-engine-fastbull` → `panel-feasibility-spikes` → `show-engine-core` → `app-shell`). Where this file or the older docs (`SPEC.md`, `handoff_document.md`, `agent_guidelines.md`, `TASKS-feed-and-modes.md`) disagree, the design doc wins. In particular: v1 has **no SQLite**, the window has **no `.hudWindow`**, and Rust↔Swift talk over a stdout JSON-lines protocol defined in `protocol/`. The "Architecture" and "Hard constraints" sections below predate that design and are partly superseded; read the design doc first. Do not `apply` an OpenSpec change before its proposal is confirmed by the user.

## Git workflow

- `main` always passes `openspec validate --all --strict` and every test suite that exists at that point. Never commit failing work to `main`; never force-push or rewrite history.
- One branch per OpenSpec change: `change/<change-name>` (e.g. `change/connect-engine-fastbull`). Merge to `main` with `--no-ff` after the change's tests pass and the user has seen the evidence.
- Commit per finished task group, message `<change-name>: <what>`. The user authorized (2026-10-24) committing, branching and `--no-ff` merging to `main` without asking each time, provided the tests/validation above pass and the evidence is reported afterwards. Pushing to a remote is still not authorized (no remote exists).
- Parallel work must use separate worktrees (`git worktree add ../newsticker-<change> change/<change>`), one agent per worktree. Two agents must never edit the same working tree at once. This repo's own rule so far: changes are applied sequentially.
- Generated artifacts (`ticker-connect/target/`, `.build/`, `build/`, `*.app`) are ignored. `spikes/RESULTS.md` and spike scripts are versioned; raw logs and CSVs are not.

新增資料來源：先讀 `docs/ADDING_A_SOURCE.md`（範本在 `docs/templates/`，登錄表在 `ticker-connect/src/sources.rs`）。

## What this is

FastBullTicker: a macOS floating news ticker that streams financial headlines from `https://www.fastbull.com/tw/express-news`. A Swift/SwiftUI frontend reads data produced by a Rust backend through a shared SQLite file.

## Architecture (needs both halves to understand)

- **Rust core (`fastbull_core/`, planned)**: Tokio + `reqwest` + `scraper` poll and parse FastBull, then write to SQLite via `rusqlite` (`db.rs`, `fetcher.rs`). It owns all network and DB writes.
- **Swift app (`FastBullTicker/`, planned)**: an `NSPanel` HUD window with a horizontally scrolling `TickerView`. `DatabaseBridge.swift` reads the same SQLite file in `Application Support`. This shared-DB bridge is the only planned IPC.
- **SQLite is the single source of truth.** One table, `news(id, timestamp, title UNIQUE, created_at)`. Insert with `INSERT OR IGNORE`, since `title` is the dedupe key.
- **Retention**: `DELETE FROM news WHERE created_at < datetime('now', '-3 days')` must run on every DB init and on periodic polls.

## Hard constraints (from `agent_guidelines.md`)

- Strictly native: no Electron, Tauri, Nativefier or `WKWebView`. UI is SwiftUI + AppKit only. Memory target is under 30 MB.
- Use `NSPanel`, not `NSWindow`. Style mask `[.borderless, .nonactivatingPanel, .hudWindow]`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground = true`, background `.ultraThinMaterial`/`NSVisualEffectView`.
- The pin toggle switches window level between `.floating` (default) and `.normal` at runtime.
- No synchronous network or heavy SQLite work on the Swift main thread. Polling lives in the Rust core or a `Task.detached`.

## Commands (from `agent_guidelines.md`)

```bash
cd fastbull_core && cargo build --release
cargo test test_cleanup_old_data            # retention-cleanup test (single test)
xcodebuild -scheme FastBullTicker -configuration Release
```

## Roadmap order

1. Rust core: scraper, SQLite creation, 3-day cleanup.
2. Swift `NSPanel` window with pin toggle.
3. DB bridge plus SwiftUI ticker with smooth scrolling.

## UI reference

The user supplied a screenshot of the intended look: a slanted red label badge on the left ("即時財經快訊 - FastBull") followed by a black bar with headlines scrolling horizontally. It is not stored in this repo, and the docs do not specify it beyond "smooth horizontal ticker".

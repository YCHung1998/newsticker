# AGENT.md — Guidance for Autonomous & Coding Agents

## 1. Project Overview
This repository contains the source code for **FastBullTicker**, a high-performance native macOS desktop ticker utility for real-time financial news streaming from FastBull.

### Tech Stack
* **Frontend**: Swift / SwiftUI / AppKit (`NSPanel`, `NSVisualEffectView`)
* **Backend**: Rust (`tokio`, `reqwest`, `rusqlite`, `scraper`)
* **Storage**: SQLite (`fastbull_news.db`)

---

## 2. Critical Constraints & Principles

1. **Strictly Native (No Web Enclosures)**:
   * DO NOT introduce Electron, Tauri Webview, Nativefier, or `WKWebView` for the ticker UI.
   * UI components MUST be built using native SwiftUI and AppKit controls.

2. **Window Behavior Constraints**:
   * All window controls must utilize `NSPanel` rather than standard `NSWindow`.
   * Window must support `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
   * Window background must use `.ultraThinMaterial` or `NSVisualEffectView`.
   * Pinned state MUST be dynamically switchable between `.floating` and `.normal`.

3. **Data Lifecycle & Retention Rules**:
   * SQLite is the single source of truth for persistent caching.
   * Duplicate news titles must be ignored (`INSERT OR IGNORE`).
   * A 3-day data retention policy MUST be enforced via SQL queries on every database initialization and periodic poll.

4. **Performance & Threading**:
   * Never perform synchronous network requests or heavy SQLite operations on the Main UI thread in Swift.
   * Background polling is owned by the Rust core or Swift background task (`Task.detached`).

---

## 3. Directory Layout Guidelines

```text
├── FastBullTicker.xcodeproj/
├── FastBullTicker/          # Swift/SwiftUI Frontend Source
│   ├── Views/
│   │   ├── FloatingPanel.swift
│   │   └── TickerView.swift
│   └── Database/
│       └── DatabaseBridge.swift
├── fastbull_core/           # Rust Backend Library
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── db.rs
│       └── fetcher.rs
├── HANDOFF.md
└── AGENT.md
```

---

## 4. Common Tasks & Commands

* **Build Rust Core**:
  ```bash
  cd fastbull_core && cargo build --release
  ```
* **Run Database Clean Routine Verification**:
  ```bash
  cargo test test_cleanup_old_data
  ```
* **Build macOS App**:
  ```bash
  xcodebuild -scheme FastBullTicker -configuration Release
  ```
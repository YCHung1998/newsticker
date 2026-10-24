# FastBullTicker — Project Handoff Document

## 1. Executive Summary
**FastBullTicker** is a dedicated macOS desktop floating ticker utility designed for financial news streaming from FastBull (`https://www.fastbull.com/tw/express-news`). 
The project replaces browser-based or web-wrapped container approaches (such as Nativefier or Safari PWAs) with a pure native hybrid architecture consisting of a **Swift/SwiftUI frontend** and a **Rust backend**.

---

## 2. Architecture & Design Principles

### Architectural Blueprint
```
┌────────────────────────────────────────────────────────┐
│             Swift Frontend (AppKit / SwiftUI)          │
│  • NSPanel HUD window with .ultraThinMaterial         │
│  • Smooth horizontal ticker UI with state toggles      │
│  • Level control: .floating vs .normal (pinned state) │
└───────────────────────────┬────────────────────────────┘
                            │ (Local IPC / Shared SQLite DB)
┌───────────────────────────▼────────────────────────────┐
│             Rust Backend Engine (Core Worker)          │
│  • Tokio async fetcher querying FastBull Express News  │
│  • SQLite persistence layer (`rusqlite`)               │
│  • Automatic 3-day data retention cleanup policy       │
└───────────────────────────┘
```

### Key Architectural Choices
1. **No Web View / Engine**: Avoids heavy Chromium/WebKit runtimes, maintaining minimal memory footprint (< 30 MB).
2. **Swift / AppKit Integration**: Uses `NSPanel` for floating behavior, cross-space presence (`.canJoinAllSpaces`), window dragging, and native translucent vibrancy (`.ultraThinMaterial`).
3. **Rust Data Core**: Handles asynchronous background network polling, parsing, and SQLite caching without blocking the UI thread.
4. **Data Retention**: SQLite layer maintains a 3-day cleanup routine (`created_at < datetime('now', '-3 days')`) on startup and periodically.

---

## 3. Core Component Specifications

### 3.1 Backend Data Model (SQLite)
```sql
CREATE TABLE IF NOT EXISTS news (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    title TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### 3.2 Cleanup Logic
```sql
DELETE FROM news WHERE created_at < datetime('now', '-3 days');
```

### 3.3 Window Configuration (`NSPanel`)
* **Style Mask**: `[.borderless, .nonactivatingPanel, .hudWindow]`
* **Level Default**: `NSWindow.Level.floating` (Togglable to `.normal`)
* **Collection Behavior**: `[.canJoinAllSpaces, .fullScreenAuxiliary]`
* **Dragging**: `isMovableByWindowBackground = true`

---

## 4. Implementation Roadmap

1. **Phase 1: Rust Core Setup**
   - Initialize Cargo crate (`fastbull_core`).
   - Implement FastBull scraper/fetcher with `reqwest` & `scraper`.
   - Setup SQLite connection with automatic table creation & 3-day cleanup logic.

2. **Phase 2: Swift Native Window**
   - Create Xcode macOS app project.
   - Subclass `NSPanel` for floating, translucent UI.
   - Implement pin state toggle button (always-on-top vs normal).

3. **Phase 3: Data Bridge & Ticker UI**
   - Connect Swift interface to shared SQLite database file in `Application Support`.
   - Build SwiftUI ticker view with smooth text transition/scrolling.

---

## 5. File Artifacts Included
- `HANDOFF.md`: Project specification and architectural transition overview.
- `AGENT.md`: System instructions and rules for AI coding agents continuing work on this codebase.
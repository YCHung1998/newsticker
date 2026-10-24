//! 與 I/O 解耦的引擎狀態機：輸入一次輪詢結果，輸出要發的訊息。
//! seen-set、「是否已發 snapshot」是唯一內部狀態；錯誤輪詢絕不改動它們。
use crate::model::{ConnectError, Item, Message, State};
use std::collections::{HashSet, VecDeque};

#[derive(Debug, Clone, Copy)]
pub struct EngineConfig {
    /// 單次輪詢「新」訊息超過此數量改發 snapshot（假設值 10；恰為此數仍發 items）。
    pub flood_threshold: usize,
    /// seen-set 容量上限（假設值約 500），超過淘汰最舊加入者。
    pub seen_capacity: usize,
}

impl Default for EngineConfig {
    fn default() -> Self {
        EngineConfig { flood_threshold: 10, seen_capacity: 500 }
    }
}

pub struct PollOutcome {
    pub ok: bool,
    pub messages: Vec<Message>,
    /// 本次失敗的描述（ok 為 false 時有值）。
    pub error: Option<String>,
}

pub struct Engine {
    source: String,
    cfg: EngineConfig,
    seen: HashSet<String>,
    order: VecDeque<String>,
    snapshot_sent: bool,
}

impl Engine {
    pub fn new(source: &str, cfg: EngineConfig) -> Self {
        Engine { source: source.to_string(), cfg, seen: HashSet::new(), order: VecDeque::new(), snapshot_sent: false }
    }

    pub fn seen_len(&self) -> usize {
        self.seen.len()
    }
    pub fn has_seen(&self, id: &str) -> bool {
        self.seen.contains(id)
    }
    pub fn snapshot_sent(&self) -> bool {
        self.snapshot_sent
    }

    fn remember(&mut self, id: &str) {
        if self.seen.insert(id.to_string()) {
            self.order.push_back(id.to_string());
            while self.order.len() > self.cfg.seen_capacity {
                if let Some(old) = self.order.pop_front() {
                    self.seen.remove(&old);
                }
            }
        }
    }

    /// `result` 為 `convert` 的結果（新到舊的頁面順序）。
    pub fn on_poll(&mut self, result: Result<Vec<Item>, ConnectError>) -> PollOutcome {
        let page = match result {
            Ok(items) if items.is_empty() => Err(ConnectError::Empty),
            other => other,
        };
        let page = match page {
            Ok(p) => p,
            Err(e) => {
                let msg = e.to_string();
                return PollOutcome {
                    ok: false,
                    messages: vec![Message::status(&self.source, State::Error, msg.clone())],
                    error: Some(msg),
                };
            }
        };
        // 同頁重複 id 只保留第一個。
        let mut page_ids = HashSet::new();
        let page: Vec<Item> = page.into_iter().filter(|i| page_ids.insert(i.id.clone())).collect();

        let mut messages = Vec::new();
        if !self.snapshot_sent {
            messages.push(Message::snapshot(sorted_desc(&page)));
            self.remember_all_old_to_new(&page);
            self.snapshot_sent = true;
        } else {
            let fresh: Vec<Item> = page.iter().filter(|i| !self.seen.contains(&i.id)).cloned().collect();
            if fresh.is_empty() {
                // 沒有新訊息：不發 items（空 items 非法）。
            } else if fresh.len() > self.cfg.flood_threshold {
                messages.push(Message::snapshot(sorted_desc(&page)));
                self.remember_all_old_to_new(&page);
            } else {
                messages.push(Message::items(sorted_asc(&fresh)));
                self.remember_all_old_to_new(&fresh);
            }
        }
        PollOutcome { ok: true, messages, error: None }
    }

    fn remember_all_old_to_new(&mut self, page_new_to_old: &[Item]) {
        for i in page_new_to_old.iter().rev() {
            self.remember(&i.id);
        }
    }
}

/// snapshot：新到舊（`published_at_ms` 非遞增）；相同值保持頁面順序（穩定排序）。
fn sorted_desc(page: &[Item]) -> Vec<Item> {
    let mut v = page.to_vec();
    v.sort_by(|a, b| b.published_at_ms.cmp(&a.published_at_ms));
    v
}

/// items：舊到新（非遞減）；相同值時為「頁面順序的反向」（假設的 tie-break）。
fn sorted_asc(page: &[Item]) -> Vec<Item> {
    let mut v: Vec<Item> = page.iter().rev().cloned().collect();
    v.sort_by(|a, b| a.published_at_ms.cmp(&b.published_at_ms));
    v
}

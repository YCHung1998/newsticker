//! 協定型別（對應 protocol/schema）。欄位與限制以 protocol/ 的 schema 為準。
use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Item {
    pub source: String,
    pub id: String,
    pub published_at_ms: u64,
    pub text: String,
    /// 選填：原文連結。缺少代表無連結；絕不輸出 `null`。規則見 protocol/schema/item.schema.json。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    /// 選填：標題（顯示時粗體）。缺少代表無標題；絕不輸出 `null` 或空字串。規則見 schema。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// 選填：來源標示為重要。連接器只在為重要時輸出 `Some(true)`；缺少 = 非重要。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub important: Option<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Ok,
    Error,
}

/// 協定訊息；`type` 為內部標籤。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum Message {
    Snapshot { v: u32, items: Vec<Item> },
    Items { v: u32, items: Vec<Item> },
    Status { v: u32, source: String, state: State, message: String },
}

impl Message {
    pub fn snapshot(items: Vec<Item>) -> Self {
        Message::Snapshot { v: PROTOCOL_VERSION, items }
    }
    pub fn items(items: Vec<Item>) -> Self {
        Message::Items { v: PROTOCOL_VERSION, items }
    }
    pub fn status(source: &str, state: State, message: impl Into<String>) -> Self {
        Message::Status { v: PROTOCOL_VERSION, source: source.to_string(), state, message: message.into() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectError {
    /// 連線、DNS、逾時等。
    Fetch(String),
    /// HTTP 非 200。
    HttpStatus(u16),
    /// 解析失敗。
    Parse(String),
    /// 解析出 0 則（一律視為錯誤，不是「沒有新訊息」）。
    Empty,
}

impl std::fmt::Display for ConnectError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConnectError::Fetch(m) => write!(f, "fetch failed: {m}"),
            ConnectError::HttpStatus(c) => write!(f, "http status {c}"),
            ConnectError::Parse(m) => write!(f, "parse failed: {m}"),
            ConnectError::Empty => write!(f, "parsed 0 items"),
        }
    }
}
impl std::error::Error for ConnectError {}

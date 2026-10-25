//! jin10 連接器（金十數據即時快訊）。型別 C：公開 JSON API（GET，不需登入）。
//! 形狀：{"status":200,"data":[{"id":"20261025201806546800","time":"2026-10-25 20:18:06","extras":{"ad":false},
//!        "data":{"content":"【標題】內文…","source_link":"https://…"}}, ...]}（新到舊）
//! - id：`id` 字串（20 位數字，來源原生）。
//! - 時間：`time` 為民用時間字串，無時區標記；依網站前端 config.js 以北京時間處理 => UTC+8（推定，見 TZ_OFFSET_SECS）。
//! - 文字：`data.content`（含 `<b>`、`<a>`、`<img>` 等 HTML 片段）；去標籤、解常見實體、收斂空白。
//! - 跳過：`extras.ad == true`（站內廣告）、內容為空（PLUS 鎖定快訊 `lock:true` 內容為空字串、純圖片）。
//! - url：`data.source_link`（第三方原文連結，可空）；不合格就降級為 None。
use crate::connector::{Connector, RawPayload};
use crate::http::HttpFetcher;
use crate::model::{ConnectError, Item};
use crate::timeutil::parse_datetime;
use std::time::Duration;

/// 來源 id：小寫字母開頭，小寫英數與底線，2–32 字元；必須與 src/sources.rs 的登錄表一致。
pub const SOURCE_ID: &str = "jin10";
/// 正式抓取位址（網站前端 bundle 內 `//flash-api.jin10.com` + `/get_flash_list`，channel=-8200 為「全部」）。
pub const DEFAULT_URL: &str = "https://flash-api.jin10.com/get_flash_list?channel=-8200&vip=1";
/// 預設輪詢間隔，不得小於 10 秒（有測試守著）。
pub const DEFAULT_INTERVAL: Duration = Duration::from_secs(10);
pub const USER_AGENT: &str = "ticker-connect/0.1 (NewsTicker personal desktop ticker)";
/// 網站前端對此 API 固定帶的公開常數標頭（非登入憑證、非逐次 token；寫在其公開 JS bundle 內）。
pub const EXTRA_HEADERS: &[(&str, &str)] = &[("x-app-id", "bVBF4FyRTn5NJF5n"), ("x-version", "1.0.0")];
/// 北京時間 UTC+8（依據：網站 config.js 以 UTC+8 計算「北京時間」；API 時間字串未標時區，為推定）。
const TZ_OFFSET_SECS: i32 = 8 * 3600;
const MAX_URL_BYTES: usize = 2048;

pub struct Jin10Connector {
    fetcher: HttpFetcher,
    interval: Duration,
}

impl Jin10Connector {
    pub fn new(url: &str, interval: Duration) -> Result<Self, ConnectError> {
        Ok(Self { fetcher: HttpFetcher::new(url, USER_AGENT, EXTRA_HEADERS)?, interval })
    }
    pub fn url(&self) -> &str {
        self.fetcher.url()
    }
}

fn is_valid_url(u: &str) -> bool {
    let b = u.as_bytes();
    if b.is_empty() || b.len() > MAX_URL_BYTES || !b.iter().all(|c| (0x21..=0x7E).contains(c)) {
        return false;
    }
    let Some(rest) = u.strip_prefix("https://").or_else(|| u.strip_prefix("http://")) else {
        return false;
    };
    matches!(rest.bytes().next(), Some(c) if c.is_ascii_alphanumeric() || c == b'[')
}

/// 去 HTML 標籤、解常見實體、連續空白（含換行）收斂為單一空格。
fn clean_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut tag = String::new();
    let mut in_tag = false;
    for ch in s.chars() {
        match ch {
            '<' if !in_tag => {
                in_tag = true;
                tag.clear();
            }
            '>' if in_tag => {
                in_tag = false;
                let name: String = tag.trim_start_matches('/').chars().take_while(|c| c.is_ascii_alphanumeric()).collect::<String>().to_ascii_lowercase();
                if matches!(name.as_str(), "br" | "p" | "div" | "li") {
                    out.push(' '); // 區塊級標籤視為分隔；行內標籤（b、a…）不插入空白
                }
            }
            _ if in_tag => tag.push(ch),
            _ => out.push(ch),
        }
    }
    let out = out.replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&amp;", "&");
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// 純解析：回傳 (items 依來源順序＝新到舊, 被跳過元素的原因)。壞元素跳過並記原因；整頁壞掉由 `convert` 轉成錯誤。
pub fn parse_payload(raw: &str, source: &str) -> (Vec<Item>, Vec<String>) {
    let mut items = Vec::new();
    let mut skipped = Vec::new();
    let Ok(root) = serde_json::from_str::<serde_json::Value>(raw) else {
        return (items, vec!["payload is not JSON".to_string()]);
    };
    let Some(list) = root["data"].as_array() else {
        return (items, vec!["no `data` array".to_string()]);
    };
    for (i, el) in list.iter().enumerate() {
        let id = el["id"].as_str().map(str::trim).unwrap_or("");
        if id.is_empty() {
            skipped.push(format!("#{i}: empty id"));
            continue;
        }
        if el["extras"]["ad"].as_bool() == Some(true) {
            skipped.push(format!("{id}: advertisement"));
            continue;
        }
        let Some(ms) = el["time"].as_str().and_then(|t| parse_datetime(t, TZ_OFFSET_SECS)) else {
            skipped.push(format!("{id}: unparsable time"));
            continue;
        };
        let text = clean_text(el["data"]["content"].as_str().unwrap_or(""));
        if text.is_empty() {
            skipped.push(format!("{id}: empty text (locked or image-only)"));
            continue;
        }
        let link = el["data"]["source_link"].as_str().map(str::trim).unwrap_or("");
        let url = if link.is_empty() {
            None
        } else if is_valid_url(link) {
            Some(link.to_string())
        } else {
            skipped.push(format!("{id}: invalid source_link dropped (item kept)"));
            None
        };
        items.push(Item { source: source.to_string(), id: id.to_string(), published_at_ms: ms, text, url });
    }
    (items, skipped)
}

impl Connector for Jin10Connector {
    fn source_id(&self) -> &str {
        SOURCE_ID
    }

    fn interval(&self) -> Duration {
        self.interval
    }

    async fn fetch(&self) -> Result<RawPayload, ConnectError> {
        self.fetcher.get_text().await
    }

    fn convert(&self, raw: RawPayload) -> Result<Vec<Item>, ConnectError> {
        let (items, skipped) = parse_payload(&raw, SOURCE_ID);
        for s in &skipped {
            eprintln!("[ticker-connect] {SOURCE_ID}: skipped element ({s})");
        }
        if items.is_empty() {
            // 解析 0 則一律是錯誤，不是「沒有新訊息」。
            return Err(ConnectError::Parse("no item parsed from payload".to_string()));
        }
        Ok(items)
    }
}

//! FastBull 連接器：抓取 `https://www.fastbull.com/tw/express-news` 並解析快訊。
use crate::connector::{Connector, RawPayload};
use crate::model::{ConnectError, Item};
use scraper::{Html, Selector};
use std::time::Duration;

/// 正式 URL 只能作為預設設定常數出現；測試一律改用本機假伺服器位址。
pub const DEFAULT_URL: &str = "https://www.fastbull.com/tw/express-news";
/// 連結的 origin 是連接器常數，不從 `fetch` 的目標 URL 推導（測試改用本機假伺服器時才不會產生本機連結）。
pub const LINK_ORIGIN: &str = "https://www.fastbull.com";
/// 協定 `url` 上限（位元組）。
pub const MAX_URL_BYTES: usize = 2048;
/// `url` 降級原因在 `skipped` 中的前綴（item 照常輸出，只是沒有 `url`）。
pub const URL_NOTE_PREFIX: &str = "url dropped: ";
pub const SOURCE_ID: &str = "fastbull";
pub const DEFAULT_INTERVAL: Duration = Duration::from_secs(10);
/// 總逾時（假設 8 秒，須小於輪詢間隔）。
pub const TOTAL_TIMEOUT: Duration = Duration::from_secs(8);
pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
pub const USER_AGENT: &str = "ticker-connect/0.1 (FastBullTicker personal desktop ticker)";

pub struct FastBullConnector {
    url: String,
    interval: Duration,
    client: reqwest::Client,
}

impl FastBullConnector {
    pub fn new(url: &str, interval: Duration) -> Result<Self, ConnectError> {
        Self::with_timeouts(url, interval, CONNECT_TIMEOUT, TOTAL_TIMEOUT)
    }

    pub fn with_timeouts(url: &str, interval: Duration, connect: Duration, total: Duration) -> Result<Self, ConnectError> {
        let client = reqwest::Client::builder()
            .user_agent(USER_AGENT)
            .connect_timeout(connect)
            .timeout(total)
            // 假設：不跟隨重新導向，3xx 一律視為錯誤。
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|e| ConnectError::Fetch(e.to_string()))?;
        Ok(FastBullConnector { url: url.to_string(), interval, client })
    }

    pub fn default_config() -> Result<Self, ConnectError> {
        Self::new(DEFAULT_URL, DEFAULT_INTERVAL)
    }

    pub fn url(&self) -> &str {
        &self.url
    }
}

/// 快訊清單的範圍。快照實測：整份文件有 70 個 `div.news-list[data-id]`——`#side_fast_news` 內 20 個
/// （規格要求的 20 則），`#main-content` 內另有 50 個（前 20 個與側欄相同）。為符合規格的「20 則」，
/// 只取側欄；這是對規格字面（`div.news-list[data-id]`）的收斂，記於 design.md／README 待使用者確認。
pub const LIST_SCOPE: &str = "#side_fast_news";

/// 與 protocol/schema/item.schema.json 的 `url` 規則一致：可見 ASCII、http(s) 小寫 scheme、主機首字元為英數或 `[`、1..=2048 位元組。
pub fn is_valid_url(u: &str) -> bool {
    let b = u.as_bytes();
    if b.is_empty() || b.len() > MAX_URL_BYTES || !b.iter().all(|c| (0x21..=0x7E).contains(c)) {
        return false;
    }
    let rest = match u.strip_prefix("https://").or_else(|| u.strip_prefix("http://")) {
        Some(r) => r,
        None => return false,
    };
    matches!(rest.bytes().next(), Some(c) if c.is_ascii_alphanumeric() || c == b'[')
}

/// 由 `data-href`（站內路徑）組出絕對連結；不合法回傳 Err(原因)。
pub fn build_link(href: &str) -> Result<String, String> {
    let h = href.trim();
    if !h.starts_with('/') || h.starts_with("//") {
        return Err(format!("data-href {h:?} is not a single-slash path"));
    }
    let url = format!("{LINK_ORIGIN}{h}");
    if is_valid_url(&url) {
        Ok(url)
    } else {
        Err(format!("data-href {h:?} yields an invalid url"))
    }
}

/// 純解析：回傳 (items 頁面順序, 被跳過元素的原因)。
pub fn parse_html(html: &str, source: &str) -> (Vec<Item>, Vec<String>) {
    let doc = Html::parse_document(html);
    let news = Selector::parse(&format!("{LIST_SCOPE} div.news-list[data-id]")).expect("selector");
    let title = Selector::parse("span.title_name").expect("selector");
    let link = Selector::parse("[data-href]").expect("selector");
    let mut items = Vec::new();
    let mut skipped = Vec::new();
    for el in doc.select(&news) {
        let id = el.value().attr("data-id").unwrap_or("").trim();
        if id.is_empty() {
            skipped.push("empty data-id".to_string());
            continue;
        }
        let ms = match el.value().attr("data-date").map(str::trim).and_then(|s| s.parse::<u64>().ok()) {
            Some(ms) => ms,
            None => {
                skipped.push(format!("{id}: data-date is not an integer"));
                continue;
            }
        };
        // 只在此 div.news-list 範圍內找（ElementRef::select 僅搜尋其後代）。
        let text = match el.select(&title).next() {
            Some(t) => t.text().collect::<String>().trim().to_string(),
            None => {
                skipped.push(format!("{id}: no span.title_name"));
                continue;
            }
        };
        if text.is_empty() {
            skipped.push(format!("{id}: empty text"));
            continue;
        }
        // 連結只是附加功能：壞值降級為無 url（item 照常輸出），否則引擎的 schema 過濾會整則丟棄。
        let url = el.select(&link).next().and_then(|a| {
            let href = a.value().attr("data-href").unwrap_or("");
            match build_link(href) {
                Ok(u) => Some(u),
                Err(why) => {
                    skipped.push(format!("{URL_NOTE_PREFIX}{id}: {why}"));
                    None
                }
            }
        });
        items.push(Item { source: source.to_string(), id: id.to_string(), published_at_ms: ms, text, url });
    }
    (items, skipped)
}

impl Connector for FastBullConnector {
    fn source_id(&self) -> &str {
        SOURCE_ID
    }

    fn interval(&self) -> Duration {
        self.interval
    }

    async fn fetch(&self) -> Result<RawPayload, ConnectError> {
        let resp = self.client.get(&self.url).send().await.map_err(|e| ConnectError::Fetch(error_chain(&e)))?;
        let code = resp.status().as_u16();
        if code != 200 {
            return Err(ConnectError::HttpStatus(code));
        }
        resp.text().await.map_err(|e| ConnectError::Fetch(error_chain(&e)))
    }

    fn convert(&self, raw: RawPayload) -> Result<Vec<Item>, ConnectError> {
        let (items, skipped) = parse_html(&raw, SOURCE_ID);
        for s in &skipped {
            if s.starts_with(URL_NOTE_PREFIX) {
                eprintln!("[ticker-connect] fastbull: item kept without link ({s})");
            } else {
                eprintln!("[ticker-connect] fastbull: skipped element ({s})");
            }
        }
        if items.is_empty() {
            return Err(ConnectError::Parse("no #side_fast_news div.news-list[data-id] item found".to_string()));
        }
        Ok(items)
    }
}

fn error_chain(e: &dyn std::error::Error) -> String {
    let mut s = e.to_string();
    let mut cur = e.source();
    while let Some(c) = cur {
        s.push_str(": ");
        s.push_str(&c.to_string());
        cur = c.source();
    }
    s
}

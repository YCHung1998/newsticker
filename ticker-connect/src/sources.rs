//! 來源登錄表：新增來源 = 新增 `src/<name>.rs`，並在本檔做兩處修改（見下方 [1]、[2]）；其餘檔案不用動。
//! `Connector` 是 `async fn in trait`（非 dyn-safe），所以用 `match` + 泛型 visitor 分派，不用 `Box<dyn Connector>`。
use crate::connector::Connector;
use crate::fastbull::{self, FastBullConnector};
use crate::jin10::{self, Jin10Connector};
use crate::model::ConnectError;
use std::time::Duration;

pub struct SourceEntry {
    /// 與連接器 `source_id()` 相同；規則見 `is_valid_id`。
    pub id: &'static str,
    /// 正式抓取位址（預設值）。守衛測試由它推導「測試不得出現的網域」。
    pub default_url: &'static str,
}

/// [1] 登錄表：每個來源一行。
pub const REGISTRY: &[SourceEntry] = &[
    SourceEntry { id: fastbull::SOURCE_ID, default_url: fastbull::DEFAULT_URL },
    SourceEntry { id: jin10::SOURCE_ID, default_url: jin10::DEFAULT_URL },
];

/// 命令列覆寫（`--url`／`--interval-ms`）。`None` = 用該來源的預設值。
#[derive(Debug, Clone, Default)]
pub struct SourceOptions {
    pub url: Option<String>,
    pub interval: Option<Duration>,
}

/// 拿到已建好的連接器後要做的事（`main` 的實作是跑排程；測試的實作只是探查）。
pub trait WithConnector {
    type Out;
    fn call<C: Connector>(self, connector: C) -> Self::Out;
}

#[derive(Debug, PartialEq, Eq)]
pub enum DispatchError {
    /// 未登錄的來源 id。
    Unknown(String),
    /// 連接器建構失敗（例如 HTTP 用戶端建不起來）。
    Build(ConnectError),
}

/// 來源 id 規則：小寫字母開頭，其後小寫英數或底線，總長 2–32。
pub fn is_valid_id(id: &str) -> bool {
    let b = id.as_bytes();
    (2..=32).contains(&b.len()) && b[0].is_ascii_lowercase() && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_')
}

pub fn find(id: &str) -> Option<&'static SourceEntry> {
    REGISTRY.iter().find(|e| e.id == id)
}

pub fn ids() -> Vec<&'static str> {
    REGISTRY.iter().map(|e| e.id).collect()
}

/// [2] 分派：每個來源一個 match 分支，建構連接器後交給 visitor。
pub fn dispatch<V: WithConnector>(id: &str, opts: &SourceOptions, visitor: V) -> Result<V::Out, DispatchError> {
    let entry = find(id).ok_or_else(|| DispatchError::Unknown(id.to_string()))?;
    let url = opts.url.as_deref().unwrap_or(entry.default_url);
    match entry.id {
        fastbull::SOURCE_ID => {
            let interval = opts.interval.unwrap_or(fastbull::DEFAULT_INTERVAL);
            Ok(visitor.call(FastBullConnector::new(url, interval).map_err(DispatchError::Build)?))
        }
        jin10::SOURCE_ID => Ok(visitor.call(Jin10Connector::new(url, opts.interval.unwrap_or(jin10::DEFAULT_INTERVAL)).map_err(DispatchError::Build)?)),
        // 新來源：照上面的格式加一個分支，例如
        // my_source::SOURCE_ID => Ok(visitor.call(MySourceConnector::new(url, opts.interval.unwrap_or(my_source::DEFAULT_INTERVAL)).map_err(DispatchError::Build)?)),
        _ => Err(DispatchError::Unknown(id.to_string())),
    }
}

//! 供新來源共用的 HTTP GET 抓取：固定逾時、非空 User-Agent、不跟隨重新導向（3xx 視為錯誤）、可附加標頭。
//! 來源模組在 `Connector::fetch` 裡呼叫 `get_text()` 即可；FastBull 有自己的實作，未遷移。
use crate::model::ConnectError;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use std::time::Duration;

/// 連線逾時 5 秒、總逾時 8 秒（須小於輪詢間隔下限 10 秒）【假設，沿用 FastBull】。
pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
pub const TOTAL_TIMEOUT: Duration = Duration::from_secs(8);

pub struct HttpFetcher {
    url: String,
    client: reqwest::Client,
}

impl HttpFetcher {
    pub fn new(url: &str, user_agent: &str, headers: &[(&str, &str)]) -> Result<Self, ConnectError> {
        Self::with_timeouts(url, user_agent, headers, CONNECT_TIMEOUT, TOTAL_TIMEOUT)
    }

    pub fn with_timeouts(url: &str, user_agent: &str, headers: &[(&str, &str)], connect: Duration, total: Duration) -> Result<Self, ConnectError> {
        let mut map = HeaderMap::new();
        for (k, v) in headers {
            let name = HeaderName::from_bytes(k.as_bytes()).map_err(|e| ConnectError::Fetch(format!("bad header name {k:?}: {e}")))?;
            let value = HeaderValue::from_str(v).map_err(|e| ConnectError::Fetch(format!("bad header value for {k}: {e}")))?;
            map.insert(name, value);
        }
        let client = reqwest::Client::builder()
            .user_agent(user_agent)
            .default_headers(map)
            .connect_timeout(connect)
            .timeout(total)
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|e| ConnectError::Fetch(error_chain(&e)))?;
        Ok(HttpFetcher { url: url.to_string(), client })
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    /// GET；非 200 -> `HttpStatus(code)`；傳輸錯誤 -> `Fetch`。內容以回應宣告的字元集解碼（缺省 UTF-8，壞位元組以替代字元取代）。
    pub async fn get_text(&self) -> Result<String, ConnectError> {
        let resp = self.client.get(&self.url).send().await.map_err(|e| ConnectError::Fetch(error_chain(&e)))?;
        let code = resp.status().as_u16();
        if code != 200 {
            return Err(ConnectError::HttpStatus(code));
        }
        resp.text().await.map_err(|e| ConnectError::Fetch(error_chain(&e)))
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

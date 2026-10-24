//! Connector trait：來源專屬（fetch／convert），引擎共用邏輯在 engine／scheduler。
use crate::model::{ConnectError, Item};
use std::time::Duration;

pub type RawPayload = String;

#[allow(async_fn_in_trait)]
pub trait Connector {
    fn source_id(&self) -> &str;
    fn interval(&self) -> Duration;
    async fn fetch(&self) -> Result<RawPayload, ConnectError>;
    /// 純函式：相同輸入得相同輸出。回傳順序與來源頁面一致（新到舊）。
    fn convert(&self, raw: RawPayload) -> Result<Vec<Item>, ConnectError>;
}

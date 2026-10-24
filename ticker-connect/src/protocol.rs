//! 契約驗證：直接編入 protocol/schema 的 4 份 JSON Schema（2020-12），不複製副本。
//! 判定順序與 protocol/refcheck.py 的 check_line 一致：
//! oversize -> not_json -> version -> schema -> order。
use crate::model::Item;
use jsonschema::{Draft, Registry, Validator};
use serde_json::Value;

pub const MAX_LINE_BYTES: usize = 1_048_576;

const ITEM: &str = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../protocol/schema/item.schema.json"));
const SNAPSHOT: &str = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../protocol/schema/snapshot.schema.json"));
const ITEMS: &str = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../protocol/schema/items.schema.json"));
const STATUS: &str = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../protocol/schema/status.schema.json"));

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reason {
    NotJson,
    Schema,
    Version,
    Oversize,
    Order,
}

impl Reason {
    pub fn as_str(self) -> &'static str {
        match self {
            Reason::NotJson => "not_json",
            Reason::Schema => "schema",
            Reason::Version => "version",
            Reason::Oversize => "oversize",
            Reason::Order => "order",
        }
    }
}

pub struct Protocol {
    item: Validator,
    snapshot: Validator,
    items: Validator,
    status: Validator,
}

impl Protocol {
    pub fn new() -> Self {
        let docs: Vec<(Value,)> = [ITEM, SNAPSHOT, ITEMS, STATUS]
            .iter()
            .map(|s| (serde_json::from_str::<Value>(s).expect("embedded schema is valid JSON"),))
            .collect();
        let mut registry = Registry::new();
        for (v,) in &docs {
            let id = v["$id"].as_str().expect("schema has $id").to_string();
            registry = registry.add(id, v.clone()).expect("register schema");
        }
        let registry = registry.prepare().expect("prepare registry");
        let build = |v: &Value| {
            jsonschema::options()
                .with_draft(Draft::Draft202012)
                .with_registry(&registry)
                .build(v)
                .expect("build validator")
        };
        Protocol {
            item: build(&docs[0].0),
            snapshot: build(&docs[1].0),
            items: build(&docs[2].0),
            status: build(&docs[3].0),
        }
    }

    /// 驗證單一 item（item.schema.json）。回傳第一個錯誤描述。
    pub fn check_item(&self, item: &Item) -> Result<(), String> {
        let v = serde_json::to_value(item).map_err(|e| e.to_string())?;
        match self.item.iter_errors(&v).next() {
            None => Ok(()),
            Some(e) => Err(e.to_string()),
        }
    }

    /// `raw` 為不含結尾換行的一行位元組。
    pub fn check_line(&self, raw: &[u8]) -> Result<(), Reason> {
        if raw.len() > MAX_LINE_BYTES {
            return Err(Reason::Oversize);
        }
        let msg: Value = std::str::from_utf8(raw)
            .ok()
            .and_then(|s| serde_json::from_str(s).ok())
            .ok_or(Reason::NotJson)?;
        if let Some(v) = msg.get("v") {
            if (v.is_i64() || v.is_u64()) && v.as_i64() != Some(1) {
                return Err(Reason::Version);
            }
        }
        let ty = msg.get("type").and_then(Value::as_str);
        let validator = match ty {
            Some("snapshot") => &self.snapshot,
            Some("items") => &self.items,
            Some("status") => &self.status,
            _ => return Err(Reason::Schema),
        };
        if validator.iter_errors(&msg).next().is_some() {
            return Err(Reason::Schema);
        }
        if matches!(ty, Some("snapshot") | Some("items")) && !order_ok(&msg, ty == Some("snapshot")) {
            return Err(Reason::Order);
        }
        Ok(())
    }
}

impl Default for Protocol {
    fn default() -> Self {
        Self::new()
    }
}

fn order_ok(msg: &Value, descending: bool) -> bool {
    let ms: Vec<u64> = msg["items"]
        .as_array()
        .map(|a| a.iter().filter_map(|i| i["published_at_ms"].as_u64()).collect())
        .unwrap_or_default();
    ms.windows(2).all(|w| if descending { w[0] >= w[1] } else { w[0] <= w[1] })
}

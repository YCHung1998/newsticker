//! 來源登錄表：一致性與分派（不連網；`--url` 一律指向本機假伺服器）。
mod common;
use common::*;
use std::time::Duration;
use ticker_connect::connector::Connector;
use ticker_connect::sources::{dispatch, is_valid_id, DispatchError, SourceOptions, WithConnector, REGISTRY};

/// 回報連接器自報的 id、間隔，並（可選）同步 fetch 一次以證明 URL 覆寫生效。
struct Probe {
    do_fetch: bool,
}
impl WithConnector for Probe {
    type Out = (String, Duration, Option<String>);
    fn call<C: Connector>(self, c: C) -> Self::Out {
        let fetched = if self.do_fetch {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
            Some(match rt.block_on(c.fetch()) {
                Ok(b) => b,
                Err(e) => format!("ERR {e}"),
            })
        } else {
            None
        };
        (c.source_id().to_string(), c.interval(), fetched)
    }
}

#[test]
fn registry_has_fastbull_and_ids_are_valid_and_unique() {
    assert!(REGISTRY.iter().any(|e| e.id == "fastbull"));
    let mut seen = std::collections::HashSet::new();
    for e in REGISTRY {
        assert!(is_valid_id(e.id), "invalid id {:?}", e.id);
        assert!(seen.insert(e.id), "duplicate id {:?}", e.id);
        assert!(e.default_url.starts_with("https://"), "{}: default_url must be https", e.id);
    }
}

#[test]
fn registry_is_valid_id_rules() {
    for ok in ["fastbull", "jin10", "a1", "my_source", "a_b_c_1"] {
        assert!(is_valid_id(ok), "{ok}");
    }
    let long = "a".repeat(33);
    for bad in ["", "a", "1abc", "Fastbull", "my-source", "with space", "名稱", "ab\n", long.as_str(), "_ab"] {
        assert!(!is_valid_id(bad), "{bad:?}");
    }
    assert!(is_valid_id(&"a".repeat(32)));
}

#[test]
fn registry_every_entry_dispatches_and_connector_agrees_with_registry() {
    for e in REGISTRY {
        let (id, interval, _) = dispatch(e.id, &SourceOptions::default(), Probe { do_fetch: false }).unwrap_or_else(|_| panic!("{} not dispatchable", e.id));
        assert_eq!(id, e.id, "connector.source_id() must equal the registry id");
        assert!(interval >= Duration::from_secs(10), "{}: default interval {:?} is below the 10s floor", e.id, interval);
    }
}

#[test]
fn registry_unknown_id_is_error() {
    let r = dispatch("nope", &SourceOptions::default(), Probe { do_fetch: false });
    assert!(matches!(r, Err(DispatchError::Unknown(ref s)) if s == "nope"));
}

#[test]
fn registry_url_and_interval_overrides_are_applied() {
    let s = FakeServer::start(Mode::Body("<html></html>".into()));
    let opts = SourceOptions { url: Some(s.url.clone()), interval: Some(Duration::from_millis(1234)) };
    let (id, interval, fetched) = dispatch("fastbull", &opts, Probe { do_fetch: true }).unwrap();
    assert_eq!(id, "fastbull");
    assert_eq!(interval, Duration::from_millis(1234));
    assert_eq!(fetched.as_deref(), Some("<html></html>"));
    assert_eq!(s.requests.lock().unwrap().len(), 1, "the fake server must have received the request");
}

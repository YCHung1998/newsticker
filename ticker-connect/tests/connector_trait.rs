mod common;
use common::*;
use std::time::Duration;
use ticker_connect::connector::Connector;
use ticker_connect::emitter::Emitter;
use ticker_connect::engine::{Engine, EngineConfig};
use ticker_connect::scheduler::{run, SchedulerConfig};

#[tokio::test(start_paused = true)]
async fn connector_trait_fake_connector_drives_engine_without_network() {
    let c = FakeConnector::new(Duration::from_secs(10), vec![Step::Page(vec![item("b", 2), item("a", 1)])]);
    let buf = SharedBuf::default();
    let mut em = Emitter::new(buf.clone(), "fake");
    let engine = Engine::new("fake", EngineConfig::default());
    run(&c, engine, &mut em, SchedulerConfig::default(), tokio::time::sleep(Duration::from_secs(5))).await.unwrap();
    let lines = buf.lines();
    assert_eq!(lines.len(), 1);
    assert_eq!(lines[0]["type"], "snapshot");
    assert_eq!(lines[0]["items"][0]["id"], "b");
}

#[test]
fn connector_trait_convert_is_pure() {
    let c = FakeConnector::new(Duration::from_secs(10), vec![]);
    let raw = serde_json::to_string(&vec![item("a", 1), item("b", 2)]).unwrap();
    assert_eq!(c.convert(raw.clone()), c.convert(raw));
}

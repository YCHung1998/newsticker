//! 真 binary 的 `--list-sources`／`--source`（只對本機假伺服器）。
mod common;
use common::*;
use std::process::{Command, Stdio};
use std::time::Duration;

fn run(args: &[&str]) -> (i32, String, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ticker-connect")).args(args).stdin(Stdio::null()).output().unwrap();
    (out.status.code().unwrap_or(-1), String::from_utf8_lossy(&out.stdout).into(), String::from_utf8_lossy(&out.stderr).into())
}

#[test]
fn sources_cli_list_sources_prints_ids_one_per_line_exit_0() {
    let (code, out, _) = run(&["--list-sources"]);
    assert_eq!(code, 0);
    let ids: Vec<&str> = out.lines().collect();
    let want: Vec<&str> = ticker_connect::sources::REGISTRY.iter().map(|e| e.id).collect();
    assert_eq!(ids, want);
    assert!(ids.contains(&"fastbull"));
    assert!(out.ends_with('\n'));
}

#[test]
fn sources_cli_unknown_source_exits_2_lists_available_and_keeps_stdout_empty() {
    let (code, out, err) = run(&["--source", "nope"]);
    assert_eq!(code, 2);
    assert_eq!(out, "");
    assert!(err.contains("nope"), "{err}");
    assert!(err.contains("fastbull"), "{err}");
}

#[test]
fn sources_cli_source_without_value_exits_2() {
    let (code, out, _) = run(&["--source"]);
    assert_eq!(code, 2);
    assert_eq!(out, "");
}

#[test]
fn sources_cli_explicit_fastbull_equals_default_behaviour() {
    let server = FakeServer::start(Mode::Body(fixture_html()));
    let first_snapshot = |extra: &[&str]| {
        let mut h = spawn_helper_with(extra, &server.url, 100, 300);
        h.wait_for("snapshot", Duration::from_secs(10), |v| v["type"] == "snapshot")
    };
    let a = first_snapshot(&[]);
    let b = first_snapshot(&["--source", "fastbull"]);
    assert_eq!(a, b);
    assert_eq!(a["items"].as_array().unwrap().len(), 20);
    assert_eq!(a["items"][0]["source"], "fastbull");
}

//! 守衛：測試與測試輔助程式不得含對正式網站的請求路徑。
mod common;

fn prod_host() -> String {
    ["fastbull", ".com"].concat()
}

#[test]
fn guard_test_sources_never_mention_the_production_host() {
    let host = prod_host();
    for dir in ["tests", "tests/common"] {
        for e in std::fs::read_dir(format!("{}/{dir}", common::ROOT)).unwrap() {
            let p = e.unwrap().path();
            if p.extension().map_or(false, |x| x == "rs") {
                let src = std::fs::read_to_string(&p).unwrap();
                assert!(!src.contains(&host), "{} mentions the production host", p.display());
            }
        }
    }
}

#[test]
#[should_panic(expected = "127.0.0.1")]
fn guard_assert_local_rejects_non_local_urls() {
    common::assert_local(&format!("https://www.{}/tw/express-news", prod_host()));
}

#[test]
fn guard_production_url_exists_only_as_default_config_constant() {
    assert!(ticker_connect::fastbull::DEFAULT_URL.contains(&prod_host()));
}

#[test]
fn guard_registered_sources_domains_never_appear_in_test_sources() {
    // 由登錄表自動推導：新增來源後不需手動改守衛。
    for e in ticker_connect::sources::REGISTRY {
        let domain = common::base_domain(e.default_url);
        assert!(domain.contains('.'), "{}: cannot derive a domain from {}", e.id, e.default_url);
        for dir in ["tests", "tests/common"] {
            let hits = common::files_mentioning(std::path::Path::new(&format!("{}/{dir}", common::ROOT)), &domain);
            assert!(hits.is_empty(), "source {}: test files mention {domain}: {hits:?}", e.id);
        }
    }
}

#[test]
fn guard_base_domain_takes_last_two_labels_and_drops_port_and_path() {
    assert_eq!(common::base_domain("https://www.example.org/a/b"), "example.org");
    assert_eq!(common::base_domain("https://flash-api.news.example.org:8443/x?y=1"), "example.org");
    assert_eq!(common::base_domain("http://example.org"), "example.org");
}

#[test]
fn guard_files_mentioning_detects_a_planted_literal() {
    let dir = std::path::PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("guard_planted");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("clean.rs"), "let x = 1;").unwrap();
    std::fs::write(dir.join("dirty.rs"), "let u = \"https://api.example.org/x\";").unwrap();
    std::fs::write(dir.join("dirty.txt"), "example.org but not a .rs file").unwrap();
    let hits = common::files_mentioning(&dir, "example.org");
    assert_eq!(hits.len(), 1, "{hits:?}");
    assert!(hits[0].ends_with("dirty.rs"));
}

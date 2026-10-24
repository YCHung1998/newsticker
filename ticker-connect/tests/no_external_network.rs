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

//! timeutil：民用時間 + 固定位移 -> UTC 毫秒。
use ticker_connect::timeutil::{civil_to_unix_ms, parse_datetime};

const H: i32 = 3600;

#[test]
fn timeutil_epoch_is_zero() {
    assert_eq!(civil_to_unix_ms(1970, 1, 1, 0, 0, 0, 0, 0), Some(0));
}

#[test]
fn timeutil_known_value_utc_plus_8() {
    // 2026-10-25T04:30:45Z = 1792902645 秒（以 `date -u -r 1792902645` 交叉驗證）
    assert_eq!(civil_to_unix_ms(2026, 10, 25, 12, 30, 45, 0, 8 * H), Some(1_792_902_645_000));
    assert_eq!(civil_to_unix_ms(2026, 10, 25, 4, 30, 45, 0, 0), Some(1_792_902_645_000));
}

#[test]
fn timeutil_negative_offset_moves_the_other_way() {
    assert_eq!(civil_to_unix_ms(2026, 10, 25, 4, 30, 45, 0, 0), civil_to_unix_ms(2026, 10, 24, 23, 30, 45, 0, -5 * H));
}

#[test]
fn timeutil_millis_are_added() {
    assert_eq!(civil_to_unix_ms(1970, 1, 1, 0, 0, 1, 250, 0), Some(1250));
}

#[test]
fn timeutil_leap_years() {
    assert!(civil_to_unix_ms(2024, 2, 29, 0, 0, 0, 0, 0).is_some());
    assert!(civil_to_unix_ms(2026, 2, 29, 0, 0, 0, 0, 0).is_none());
    assert!(civil_to_unix_ms(1900, 2, 29, 0, 0, 0, 0, 0).is_none(), "1900 is not a leap year");
    assert!(civil_to_unix_ms(2000, 2, 29, 0, 0, 0, 0, 0).is_some(), "2000 is a leap year");
    // 2024-03-01 比 2024-02-28 晚恰好 2 天
    let a = civil_to_unix_ms(2024, 2, 28, 0, 0, 0, 0, 0).unwrap();
    let b = civil_to_unix_ms(2024, 3, 1, 0, 0, 0, 0, 0).unwrap();
    assert_eq!(b - a, 2 * 86_400_000);
}

#[test]
fn timeutil_rejects_out_of_range_fields() {
    assert!(civil_to_unix_ms(2026, 13, 1, 0, 0, 0, 0, 0).is_none());
    assert!(civil_to_unix_ms(2026, 0, 1, 0, 0, 0, 0, 0).is_none());
    assert!(civil_to_unix_ms(2026, 4, 31, 0, 0, 0, 0, 0).is_none());
    assert!(civil_to_unix_ms(2026, 1, 1, 24, 0, 0, 0, 0).is_none());
    assert!(civil_to_unix_ms(2026, 1, 1, 0, 60, 0, 0, 0).is_none());
    assert!(civil_to_unix_ms(2026, 1, 1, 0, 0, 60, 0, 0).is_none());
    assert!(civil_to_unix_ms(2026, 1, 1, 0, 0, 0, 1000, 0).is_none());
}

#[test]
fn timeutil_before_1970_is_none() {
    assert!(civil_to_unix_ms(1969, 12, 31, 23, 59, 59, 0, 0).is_none());
}

#[test]
fn timeutil_parse_datetime_accepts_space_or_t_and_fraction() {
    let want = Some(1_792_902_645_000);
    assert_eq!(parse_datetime("2026-10-25 12:30:45", 8 * H), want);
    assert_eq!(parse_datetime("2026-10-25T12:30:45", 8 * H), want);
    assert_eq!(parse_datetime("  2026-10-25 12:30:45  ", 8 * H), want);
    assert_eq!(parse_datetime("2026-10-25 12:30:45.5", 8 * H), Some(1_792_902_645_500));
    assert_eq!(parse_datetime("2026-10-25 12:30:45.123", 8 * H), Some(1_792_902_645_123));
}

#[test]
fn timeutil_parse_datetime_rejects_garbage() {
    for bad in ["", "2026-10-25", "12:30:45", "2026/10/25 12:30:45", "2026-10-25 12:30", "2026-10-25 12:30:45Z", "2026-02-30 00:00:00", "abcd-ef-gh ij:kl:mn", "2026-10-25 12:30:45.", "2026-10-25 12:30:45.1234"] {
        assert_eq!(parse_datetime(bad, 0), None, "{bad:?}");
    }
}

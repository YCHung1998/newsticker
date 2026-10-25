//! 時間工具：來源給的是「某時區的民用時間字串」時，轉成協定要的 UTC 毫秒。
//! 只處理固定位移（例如 UTC+8 = 8*3600），不含夏令時間規則；位移由來源模組以常數寫死並註明依據。
//! 純函式、無 I/O、無系統時鐘。

fn is_leap(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn days_in_month(y: i32, m: u32) -> u32 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap(y) => 29,
        2 => 28,
        _ => 0,
    }
}

/// 民用日期 -> 自 1970-01-01 起的天數（Howard Hinnant 的 days_from_civil）。
fn days_from_civil(y: i32, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y as i64 - 1 } else { y as i64 };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m as i64 + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// `offset_secs` 是該民用時間相對 UTC 的位移（UTC+8 -> 28800）。越界欄位、不存在的日期、早於 1970 都回傳 `None`。
#[allow(clippy::too_many_arguments)]
pub fn civil_to_unix_ms(year: i32, month: u32, day: u32, hour: u32, minute: u32, second: u32, millis: u32, offset_secs: i32) -> Option<u64> {
    if !(1..=12).contains(&month) || day == 0 || day > days_in_month(year, month) || hour > 23 || minute > 59 || second > 59 || millis > 999 {
        return None;
    }
    let secs = days_from_civil(year, month, day) * 86_400 + hour as i64 * 3600 + minute as i64 * 60 + second as i64 - offset_secs as i64;
    if secs < 0 {
        return None;
    }
    Some(secs as u64 * 1000 + millis as u64)
}

fn num(s: &str, len: usize) -> Option<u32> {
    if s.len() == len && s.bytes().all(|b| b.is_ascii_digit()) { s.parse().ok() } else { None }
}

/// 解析 `YYYY-MM-DD HH:MM:SS`（分隔符可為空白或 `T`，可選 `.f`／`.ff`／`.fff` 小數秒），前後空白會修剪。
/// 不接受時區後綴（如 `Z`、`+08:00`）：那類字串請來源模組自己處理。
pub fn parse_datetime(s: &str, offset_secs: i32) -> Option<u64> {
    let s = s.trim();
    let (date, time) = s.split_once([' ', 'T'])?;
    let mut d = date.split('-');
    let (y, mo, da) = (d.next()?, d.next()?, d.next()?);
    if d.next().is_some() {
        return None;
    }
    let (hms, frac) = match time.split_once('.') {
        Some((a, f)) => (a, Some(f)),
        None => (time, None),
    };
    let mut t = hms.split(':');
    let (h, mi, se) = (t.next()?, t.next()?, t.next()?);
    if t.next().is_some() {
        return None;
    }
    let millis = match frac {
        None => 0,
        Some(f) if (1..=3).contains(&f.len()) && f.bytes().all(|b| b.is_ascii_digit()) => format!("{f:0<3}").parse().ok()?,
        Some(_) => return None,
    };
    civil_to_unix_ms(num(y, 4)? as i32, num(mo, 2)?, num(da, 2)?, num(h, 2)?, num(mi, 2)?, num(se, 2)?, millis, offset_secs)
}

//! 單一寫入者：序列化、輸出前驗證、逐行 flush。發送端自己過濾（使用者 2026-10-24 決定）：
//! 不合格 item 丟棄並另發 status(error)；過濾後沒有合法 item 就不發 items／snapshot。
use crate::model::{Item, Message, State};
use crate::protocol::{Protocol, MAX_LINE_BYTES};
use std::io::{self, Write};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct EmitReport {
    pub wrote_status: bool,
    pub wrote_data: bool,
}

pub struct Emitter<W: Write> {
    out: W,
    protocol: Protocol,
    source: String,
}

const MAX_WARNING_CHARS: usize = 600;

fn clip(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        let mut t: String = s.chars().take(max).collect();
        t.push('…');
        t
    }
}

impl<W: Write> Emitter<W> {
    pub fn new(out: W, source: &str) -> Self {
        Emitter { out, protocol: Protocol::new(), source: source.to_string() }
    }

    pub fn protocol(&self) -> &Protocol {
        &self.protocol
    }

    pub fn into_inner(self) -> W {
        self.out
    }

    fn write_line(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.out.write_all(bytes)?;
        self.out.write_all(b"\n")?;
        self.out.flush()
    }

    /// 驗證後寫出一則已建好的訊息；失敗回傳原因字串（不寫出）。
    fn try_write(&mut self, msg: &Message) -> io::Result<Result<(), String>> {
        let bytes = serde_json::to_vec(msg).map_err(io::Error::other)?;
        match self.protocol.check_line(&bytes) {
            Ok(()) => {
                self.write_line(&bytes)?;
                Ok(Ok(()))
            }
            Err(reason) => Ok(Err(format!("{} ({} bytes, limit {})", reason.as_str(), bytes.len(), MAX_LINE_BYTES))),
        }
    }

    fn write_status(&mut self, state: State, message: &str) -> io::Result<bool> {
        let msg = Message::status(&self.source, state, clip(message, MAX_WARNING_CHARS));
        match self.try_write(&msg)? {
            Ok(()) => Ok(true),
            Err(why) => {
                eprintln!("[ticker-connect] status dropped by validation: {why}");
                Ok(false)
            }
        }
    }

    pub fn emit(&mut self, msg: Message) -> io::Result<EmitReport> {
        let mut report = EmitReport::default();
        match msg {
            Message::Status { state, message, .. } => {
                report.wrote_status = self.write_status(state, &message)?;
            }
            Message::Snapshot { items, .. } => self.emit_data(true, items, &mut report)?,
            Message::Items { items, .. } => self.emit_data(false, items, &mut report)?,
        }
        Ok(report)
    }

    fn emit_data(&mut self, snapshot: bool, items: Vec<Item>, report: &mut EmitReport) -> io::Result<()> {
        let kind = if snapshot { "snapshot" } else { "items" };
        let mut valid = Vec::with_capacity(items.len());
        let mut dropped: Vec<String> = Vec::new();
        for it in items {
            match self.protocol.check_item(&it) {
                Ok(()) => valid.push(it),
                Err(why) => dropped.push(format!("id={:?}: {}", clip(&it.id, 60), clip(&why, 120))),
            }
        }
        let mut warnings: Vec<String> = Vec::new();
        if !dropped.is_empty() {
            warnings.push(format!("dropped {} invalid item(s) from {kind}: {}", dropped.len(), dropped.join("; ")));
        }
        if valid.is_empty() {
            if !dropped.is_empty() {
                warnings.push(format!("no valid item left; {kind} not sent"));
            }
        } else {
            let msg = if snapshot { Message::snapshot(valid) } else { Message::items(valid) };
            match self.try_write(&msg)? {
                Ok(()) => report.wrote_data = true,
                Err(why) => warnings.push(format!("{kind} not sent: {why}")),
            }
        }
        if !warnings.is_empty() {
            for w in &warnings {
                eprintln!("[ticker-connect] {w}");
            }
            if self.write_status(State::Error, &warnings.join(" | "))? {
                report.wrote_status = true;
            }
        }
        Ok(())
    }
}

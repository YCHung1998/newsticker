use std::io::{Read, Write};
use std::time::Duration;
use ticker_connect::connector::Connector;
use ticker_connect::emitter::Emitter;
use ticker_connect::engine::{Engine, EngineConfig};
use ticker_connect::scheduler::{run, SchedulerConfig};
use ticker_connect::sources::{self, DispatchError, SourceOptions, WithConnector};

/// 預設來源；未指定 `--source` 時的行為與加入來源登錄表之前完全相同。
const DEFAULT_SOURCE: &str = "fastbull";

const USAGE: &str = "ticker-connect [--source ID] [--list-sources] [--url URL] [--interval-ms N] [--heartbeat-ms N]\n\
stdout: protocol JSON-lines only; logs: stderr. Exits when stdin reaches EOF.\n\
--source selects the data source (default: fastbull); --list-sources prints the registered ids and exits.\n\
--url / --interval-ms / --heartbeat-ms exist for local testing and apply to every source; defaults are the production values.";

/// 把連接器接上引擎與排程，跑到行程結束（stdin EOF 由另一個執行緒直接結束行程）。
struct RunVisitor {
    heartbeat: Duration,
    url: String,
}

impl WithConnector for RunVisitor {
    type Out = std::io::Result<()>;
    fn call<C: Connector>(self, connector: C) -> Self::Out {
        let source = connector.source_id().to_string();
        eprintln!("[ticker-connect] source {source}: polling {} every {:?}", self.url, connector.interval());
        let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().expect("runtime");
        let mut emitter = Emitter::new(std::io::stdout(), &source);
        let engine = Engine::new(&source, EngineConfig::default());
        rt.block_on(run(&connector, engine, &mut emitter, SchedulerConfig { heartbeat: self.heartbeat }, std::future::pending()))
    }
}

fn main() {
    let mut source = DEFAULT_SOURCE.to_string();
    let mut opts = SourceOptions::default();
    let mut heartbeat = SchedulerConfig::default().heartbeat;
    let mut list_only = false;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut val = |name: &str| -> String {
            args.next().unwrap_or_else(|| {
                eprintln!("missing value for {name}\n{USAGE}");
                std::process::exit(2)
            })
        };
        match a.as_str() {
            "--source" => source = val("--source"),
            "--list-sources" => list_only = true,
            "--url" => opts.url = Some(val("--url")),
            "--interval-ms" => opts.interval = Some(Duration::from_millis(parse_u64(&val("--interval-ms")))),
            "--heartbeat-ms" => heartbeat = Duration::from_millis(parse_u64(&val("--heartbeat-ms"))),
            "-h" | "--help" => {
                println!("{USAGE}");
                return;
            }
            other => {
                eprintln!("unknown argument {other}\n{USAGE}");
                std::process::exit(2);
            }
        }
    }

    if list_only {
        for id in sources::ids() {
            println!("{id}");
        }
        return;
    }
    let Some(entry) = sources::find(&source) else {
        eprintln!("[ticker-connect] unknown source {source:?}; available: {}", sources::ids().join(", "));
        std::process::exit(2);
    };

    // 獨立 OS 執行緒監看 stdin；EOF 直接結束行程，不經過 async 執行環境，不會被進行中的網路請求卡住。
    std::thread::spawn(|| {
        let mut buf = [0u8; 256];
        let mut stdin = std::io::stdin().lock();
        loop {
            match stdin.read(&mut buf) {
                Ok(0) | Err(_) => {
                    eprintln!("[ticker-connect] stdin closed, exiting");
                    std::process::exit(0);
                }
                Ok(_) => {}
            }
        }
    });

    let url = opts.url.clone().unwrap_or_else(|| entry.default_url.to_string());
    match sources::dispatch(&source, &opts, RunVisitor { heartbeat, url }) {
        Ok(Ok(())) => {}
        Ok(Err(e)) => {
            // 例如 stdout 管線已斷。
            let _ = writeln!(std::io::stderr(), "[ticker-connect] output error: {e}");
            std::process::exit(1);
        }
        Err(DispatchError::Unknown(id)) => {
            eprintln!("[ticker-connect] unknown source {id:?}; available: {}", sources::ids().join(", "));
            std::process::exit(2);
        }
        Err(DispatchError::Build(e)) => {
            eprintln!("[ticker-connect] cannot build connector: {e}");
            std::process::exit(1);
        }
    }
}

fn parse_u64(s: &str) -> u64 {
    s.parse().unwrap_or_else(|_| {
        eprintln!("not a number: {s}\n{USAGE}");
        std::process::exit(2)
    })
}

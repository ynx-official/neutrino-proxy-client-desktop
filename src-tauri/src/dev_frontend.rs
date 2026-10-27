//! Cargo's development entry point owns only the Vite process it starts.
use std::{
    io::{BufRead, BufReader, Read, Write},
    net::{IpAddr, SocketAddr, TcpStream},
    path::Path,
    process::{Child, Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

const READY: &str = "NEUTRINO_DEV_READY";

pub struct DevFrontend {
    child: Child,
}

impl Drop for DevFrontend {
    fn drop(&mut self) {
        // Closing this pipe also happens on crashes / Ctrl+C, when Drop cannot run.
        self.child.stdin.take();
        let until = Instant::now() + Duration::from_secs(3);
        while Instant::now() < until {
            if matches!(self.child.try_wait(), Ok(Some(_))) {
                return;
            }
            thread::sleep(Duration::from_millis(20));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[derive(Debug, PartialEq)]
enum Probe {
    Missing,
    Ready,
    Other,
}

fn probe(address: SocketAddr) -> Result<Probe, String> {
    let mut stream = match TcpStream::connect_timeout(&address, Duration::from_millis(350)) {
        Ok(stream) => stream,
        Err(error)
            if matches!(
                error.kind(),
                std::io::ErrorKind::ConnectionRefused | std::io::ErrorKind::TimedOut
            ) =>
        {
            // Windows may time out before reporting a closed loopback port.
            return Ok(if std::net::TcpListener::bind(address).is_ok() {
                Probe::Missing
            } else {
                Probe::Other
            });
        }
        Err(error) => return Err(format!("无法检查开发服务端口 {address}：{error}")),
    };
    let read = || -> std::io::Result<String> {
        stream.set_read_timeout(Some(Duration::from_secs(1)))?;
        stream.set_write_timeout(Some(Duration::from_secs(1)))?;
        stream.write_all(
            format!("GET / HTTP/1.1\r\nHost: {address}\r\nConnection: close\r\n\r\n").as_bytes(),
        )?;
        let mut response = String::new();
        (&mut stream).take(16384).read_to_string(&mut response)?;
        Ok(response)
    }();
    Ok(
        if read.is_ok_and(|response| {
            let headers = response
                .split("\r\n\r\n")
                .next()
                .unwrap_or("")
                .to_ascii_lowercase();
            (headers.starts_with("http/1.1 200 ") || headers.starts_with("http/1.0 200 "))
                && headers
                    .lines()
                    .any(|line| line.trim() == "x-neutrino-dev-server: 1")
        }) {
            Probe::Ready
        } else {
            Probe::Other
        },
    )
}

pub fn ensure(url: &tauri::Url, root: &Path) -> Result<Option<DevFrontend>, String> {
    // Custom remote/HTTPS dev URLs remain managed by the developer or Tauri CLI.
    let host = url.host_str().unwrap_or("").trim_matches(['[', ']']);
    let ip = if host == "localhost" {
        "127.0.0.1".parse::<IpAddr>().ok()
    } else {
        host.parse().ok()
    };
    let Some(ip) = ip.filter(|ip| ip.is_loopback() && url.scheme() == "http") else {
        return Ok(None);
    };
    let address = SocketAddr::new(ip, url.port_or_known_default().unwrap_or(1420));
    match probe(address)? {
        Probe::Ready => return Ok(None),
        Probe::Other => {
            return Err(format!(
                "开发端口 {address} 已被其他服务占用，请释放该端口后重试"
            ))
        }
        Probe::Missing => {}
    }
    let script = root.join("scripts/dev-server.mjs");
    if !root.join("node_modules/vite/package.json").is_file() {
        return Err("前端依赖尚未安装，请在 neutrino-proxy-client-desktop 目录执行 npm ci".into());
    }
    eprintln!("正在启动本机前端开发服务…");
    let child = Command::new("node")
        .arg(script)
        .arg(ip.to_string())
        .arg(address.port().to_string())
        .current_dir(root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|error| format!("无法启动前端，请确认 Node.js 已安装且可用：{error}"))?;
    let mut frontend = DevFrontend { child };
    let stdout = frontend.child.stdout.take().unwrap();
    let (send, ready) = mpsc::channel();
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if line.trim() == READY {
                let _ = send.send(());
            } else {
                println!("{line}");
            }
        }
    });
    ready
        .recv_timeout(Duration::from_secs(30))
        .map_err(|error| match error {
            mpsc::RecvTimeoutError::Timeout => {
                "前端未能在 30 秒内启动，请检查上方 Vite 日志".to_owned()
            }
            mpsc::RecvTimeoutError::Disconnected => "前端启动失败，请检查上方 Vite 日志".to_owned(),
        })?;
    if probe(address)? != Probe::Ready {
        return Err("前端服务已退出或未返回本项目页面，请检查上方 Vite 日志".into());
    }
    eprintln!("前端已就绪：http://{address}");
    Ok(Some(frontend))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{Read, Write},
        net::{TcpListener, TcpStream},
        time::Duration,
    };

    fn endpoint() -> tauri::Url {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        tauri::Url::parse(&format!(
            "http://127.0.0.1:{}",
            listener.local_addr().unwrap().port()
        ))
        .unwrap()
    }

    #[test]
    fn direct_cargo_start_serves_the_frontend_reuses_it_and_cleans_up_owned_server() {
        let url = endpoint();
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let owned = ensure(&url, root).unwrap();
        assert!(owned.is_some(), "cargo run must start the missing frontend");
        let mut stream = TcpStream::connect(("127.0.0.1", url.port().unwrap())).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        stream
            .write_all(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            .unwrap();
        let mut html = String::new();
        stream.read_to_string(&mut html).unwrap();
        assert!(html.contains("/src/main.js"));
        assert!(html.contains("/@vite/client"));
        let reused = ensure(&url, root).unwrap();
        assert!(
            reused.is_none(),
            "an existing project frontend must not be owned twice"
        );
        drop(reused);
        assert!(TcpStream::connect(("127.0.0.1", url.port().unwrap())).is_ok());
        drop(owned);
        assert!(TcpStream::connect(("127.0.0.1", url.port().unwrap())).is_err());
    }

    #[test]
    fn another_service_on_the_port_is_not_reused_or_stopped() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = tauri::Url::parse(&format!("http://{}", listener.local_addr().unwrap())).unwrap();
        listener.set_nonblocking(true).unwrap();
        let service = std::thread::spawn(move || {
            let until = std::time::Instant::now() + Duration::from_secs(2);
            while std::time::Instant::now() < until {
                if let Ok((mut stream, _)) = listener.accept() {
                    let _ = stream.write_all(
                        b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nother application",
                    );
                }
                std::thread::sleep(Duration::from_millis(10));
            }
        });
        let result = ensure(&url, Path::new("."));
        assert!(
            result.is_err(),
            "a different service must produce a useful startup error"
        );
        assert!(TcpStream::connect(("127.0.0.1", url.port().unwrap())).is_ok());
        service.join().unwrap();
    }

    #[test]
    fn closing_the_parent_pipe_stops_vite_without_rust_drop() {
        let url = endpoint();
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let mut owned = ensure(&url, root).unwrap().unwrap();
        owned.child.stdin.take();
        let until = Instant::now() + Duration::from_secs(4);
        while Instant::now() < until && owned.child.try_wait().unwrap().is_none() {
            thread::sleep(Duration::from_millis(20));
        }
        assert!(
            owned.child.try_wait().unwrap().is_some(),
            "EOF must clean up Vite even if the parent is terminated"
        );
        assert_eq!(
            probe(SocketAddr::new(
                "127.0.0.1".parse().unwrap(),
                url.port().unwrap()
            ))
            .unwrap(),
            Probe::Missing
        );
    }

    #[test]
    fn missing_dependencies_fail_before_spawning_a_process() {
        let error = ensure(
            &endpoint(),
            Path::new("target/nonexistent-frontend-fixture"),
        )
        .err()
        .unwrap();
        assert!(error.contains("npm ci"));
    }
}

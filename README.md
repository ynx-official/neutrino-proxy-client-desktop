<p align="center"><img src="assets/logo.png" width="88" alt="Neutrino Logo"></p>

# Neutrino Proxy Desktop

[![CI](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/ci.yml)
[![Release](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/release.yml/badge.svg)](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Neutrino Proxy 的 Windows / macOS 桌面客户端。采用 Rust + Tokio 网络内核、Tauri 2 桌面宿主、Vue 3 + JavaScript 界面，提供连接配置、状态、日志和系统托盘，适合在后台保持隧道连接。安装后无需 Java、Node.js 或 Rust 工具链；Windows 使用系统 WebView2。

本仓库独立维护桌面客户端；服务端、命令行客户端和端口映射使用 [Neutrino Proxy](https://github.com/ynx-official/neutrino-proxy)。桌面客户端独立构建、测试和发布，版本与服务端分开管理。

## 功能

- 服务器、端口、License、SSL 配置，连接、断开及自动重连。
- TCP / UDP 转发、写缓冲水位线、读写空闲检测、心跳和连接状态。
- 导入 Java 客户端 YAML，预览实际读取字段并确认保存；支持同目录旧 clientId 迁移。
- 内置信任库及自定义 JKS / PEM / DER，TLS 与 Java 行为对齐，保留信任和握手签名验证；边界见[兼容性说明](docs/03-architecture/client-app-java-compatibility.md)。
- License、证书口令保存在系统安全存储，普通配置与凭证分离。
- 连接、日志、设置三页；关闭主窗口释放界面，Rust 内核与原生托盘继续工作，可恢复窗口或退出。
- 开机自启、启动后自动连接，默认关闭、自动保存；配置完整时启动尝试一次，初始失败停止，成功后保留断线重连。
- 有条数上限的日志，支持搜索、筛选、暂停视图和导出。

## 下载与使用

正式版本从 [Releases](https://github.com/ynx-official/neutrino-proxy-client-desktop/releases) 下载；尚未发布正式版本时，可从 [Actions](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions) 成功运行的 Artifacts 下载验证包。

Windows 安装包：成功的 CI 运行 → **Artifacts → `windows-x64-installer`**。解压 artifact ZIP，运行其中的 `*-windows-x64-setup.exe`。完整分发包位于 `desktop-windows-x64`、`desktop-macos-x64`、`desktop-macos-arm64`。

| 平台 | 文件 | 使用方法 |
| --- | --- | --- |
| Windows x64 安装版 | `*-windows-x64-setup.exe` | 双击安装，安装器按需安装 WebView2 |
| Windows x64 便携版 | `*-windows-x64-portable.zip` | 完整解压后运行 `neutrino-proxy-client-desktop.exe`，需有 WebView2 |
| Intel Mac | `*-macos-x64.dmg` | 打开镜像，将 Neutrino Proxy 拖到 Applications |
| Apple Silicon Mac | `*-macos-arm64.dmg` | 下载对应 ARM64 镜像并安装 |

Windows 未配置开发者签名，macOS 使用 ad-hoc 签名、未公证。下载后用 `SHA256SUMS` 核对文件；平台实际验收范围见[开发记录](docs/06-delivery/client-app-development-status.md)。

1. 进入「设置 → 连接配置」，填写域名 / IP、隧道端口、License，SSL 与服务端一致；地址不包含协议或路径。
2. 按需导入旧配置、选择信任证书，然后「保存并连接」。仅保存的修改在下次连接生效。
3. 在既有管理后台配置端口映射，通过日志页排查连接问题。
4. 「设置 → 应用设置」可开启开机自启及启动后自动连接；修改自动保存，自动连接在下次进程启动时生效。
5. 关闭窗口后仍在托盘运行，使用「退出应用」完整关闭；升级前先退出旧进程。

新配置默认关闭 SSL、端口 `9002`、重连间隔 10 秒，SSL 与端口应按实际服务端设置选择；已有配置及导入中明确指定的 SSL 开关按原值读取。应用标识为 `fun.neutrino.proxy.desktop`，配置与凭证分开存储。移动便携程序后，应关闭再开启开机自启，以更新系统注册路径。

## 本地开发

依赖以 `package-lock.json` 和 `Cargo.lock` 为准，需要 Node.js 22.12+、npm、Rust stable（1.90+）及平台工具。

- Windows：C++ Build Tools、Windows SDK、WebView2。
- macOS：Xcode Command Line Tools，只能在 macOS 构建对应平台应用。
- Python 3.11+：用于发布脚本与打包测试，不是应用运行依赖。

```sh
git clone https://github.com/ynx-official/neutrino-proxy-client-desktop.git
cd neutrino-proxy-client-desktop
npm ci
cargo run
```

`cargo run` 按需启动 Vite 并打开桌面程序，可复用已有本项目服务；结束开发进程后仅清理本次拥有的服务。也可使用 `npm run desktop:dev`。

```sh
npm test
npm run test:e2e
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
python -m unittest discover -s scripts/release -p 'test_*.py' -v
npm run desktop:build
```

Windows 可执行文件位于 `target/release/neutrino-proxy-client-desktop.exe`。生成安装包和 DMG 的命令见[发布说明](docs/06-delivery/releasing.md)。构建与测试不要求旁边存在 Java 工程；Java 仅用于可选的协议向量再生成。

## 自动打包与发布

- 分支提交、PR、手动 CI：格式、Clippy、前端 / Rust / 发布脚本测试、Windows 浏览器流程及三个平台的 Release 安装包。
- 推送 `vX.Y.Z`：同步 npm、Tauri、Rust 和锁文件版本，构建 Windows 安装 EXE / 便携 ZIP、Intel / Apple Silicon DMG；核对四份分发包、三个平台的来源提交及 SHA-256 后自动公开 Release。
- 带预发布标识的 tag（如 `v0.2.0-rc.1`）发布为 prerelease，不更新 Latest。
- 平台失败、缺包、来源不一致、哈希不匹配时不公开 Release；已发布版本不覆盖。
- 手动 Release 可选已有 tag，默认只构建；发布和按次跳过测试需明确选择。构建、格式、Clippy、产物及哈希校验始终执行。

验证并决定发布新版本后，由维护者执行，例如：

```sh
git tag -a v1.0.1 -m "Neutrino Desktop v1.0.1"
git push origin v1.0.1
```

工作流使用 GitHub 提供的 `GITHUB_TOKEN`，不配置开发者签名证书。桌面与服务端独立版本，两个仓库的 tag 不互相触发。详见[发布说明](docs/06-delivery/releasing.md)。

## 目录与文档

```text
crates/client-core/    Rust + Tokio 协议、TLS、TCP/UDP、连接生命周期
src-tauri/             Tauri 宿主、原生托盘、系统凭证和应用设置
src/                   Vue 页面、组件、路由、样式
tests/                 浏览器流程与本地对端
scripts/               开发服务器、独立打包与发布校验
assets/                项目 Logo
.github/workflows/     CI、复用构建、独立 tag 发布
docs/                  需求、设计、架构、验证、发布说明
Cargo.toml             Rust workspace
package.json           前端与桌面构建命令
```

更多说明见[文档索引](docs/README.md)。各项验证以文档注明的实际执行范围为准，长期运行、原生交互和 macOS 验收需分别确认。

## 许可证与来源

采用 [MIT License](LICENSE)，保留本项目和 Neutrino Proxy 上游版权声明。品牌、内置公开信任库和 Java 协议依据来自 Neutrino Proxy；协议向量和本地测试证书仅用于兼容验证。完整来源与 TLS 策略见[兼容性说明](docs/03-architecture/client-app-java-compatibility.md)。

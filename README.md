<p align="center"><img src="assets/logo.png" width="88" alt="Neutrino Logo"></p>

# Neutrino Proxy Desktop

[![CI](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/ci.yml)
[![Release](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/release.yml/badge.svg)](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Neutrino Proxy](https://github.com/ynx-official/neutrino-proxy) 的 Windows / macOS 桌面客户端。通过图形界面管理连接、查看状态与日志，关闭窗口后也能在系统托盘中继续运行。安装后无需单独配置 Java、Node.js 或 Rust 环境。

使用前需要准备可用的 Neutrino Proxy 服务端，以及服务端提供的连接地址、端口和 License。端口映射在服务端管理后台配置。

## 主要功能

- 支持 TCP / UDP 转发，可手动连接、断开，并在断线后自动重连。
- 导入已有 Java 客户端 YAML 配置，预览并确认后保存。
- 关闭窗口后保持后台运行，通过托盘查看状态、恢复窗口或退出。
- 按需开启开机自启和启动后自动连接。
- 搜索、筛选、暂停查看或导出日志，方便排查连接问题。
- License 和证书口令保存在系统安全存储中。

## 下载与安装

前往 [Releases 下载最新版本](https://github.com/ynx-official/neutrino-proxy-client-desktop/releases/latest)，根据自己的系统选择文件：

| 系统 | 下载文件 | 安装方式 |
| --- | --- | --- |
| Windows x64 安装版 | `*-windows-x64-setup.exe` | 双击安装，安装器会按需安装 WebView2 |
| Windows x64 便携版 | `*-windows-x64-portable.zip` | 完整解压后运行 `neutrino-proxy-client-desktop.exe`，系统需已安装 WebView2 |
| Intel Mac | `*-macos-x64.dmg` | 打开 DMG，将 Neutrino Proxy 拖入 Applications |
| Apple Silicon Mac（M 系列芯片） | `*-macos-arm64.dmg` | 下载 ARM64 版本，打开 DMG 后拖入 Applications |

Windows 版本未签名，macOS 版本未公证。下载后可使用同一版本附件中的 `SHA256SUMS` 核对文件。

## 第一次连接

先准备以下连接信息，具体值以服务端配置为准：

| 配置项 | 如何填写 |
| --- | --- |
| 服务器地址 | 服务端域名或 IP，不包含 `http://`、`https://` 或路径 |
| 端口 | 服务端提供的客户端连接端口，不是要映射的本地服务端口 |
| License | 服务端分配的 License |
| SSL | 新配置默认关闭；服务端要求加密连接时开启，端口也需与之匹配 |

1. 打开应用，进入「设置 → 连接配置」。
2. 填写连接信息；启用 SSL 后，可按需使用内置证书或选择自定义信任证书。
3. 点击「保存并连接」，在连接页查看状态，显示「已连接」后即可按服务端配置使用映射服务。

如果已有 YAML 配置，点击「导入配置」，检查预览后确认保存，再点击「保存并连接」。缺少的连接信息仍需补齐。

连接后修改配置时，可选择「仅保存，下次生效」保留当前连接，或选择「保存并重连」立即应用。

## 常用操作

**后台运行与退出**：关闭主窗口后，连接会继续保持。通过系统托盘可查看状态、打开主窗口或日志；需要完全结束运行时，选择「退出应用」。

**开机自启与自动连接**：在「设置 → 应用设置」中按需开启：

- **开机自启**：登录系统后自动启动应用。
- **启动后自动连接**：应用启动时，在已保存配置完整的情况下尝试连接。

这两项默认关闭，修改后自动保存。Windows 便携版移动到新目录后，应关闭再开启一次开机自启，以更新启动路径。

**查看连接问题**：进入「日志」页，可搜索、按级别筛选、暂停查看或导出日志。

## 遇到问题

**连接失败怎么办？**

先检查服务器地址、连接端口、License 和 SSL 开关是否与服务端配置一致，再到「日志」页查看具体报错。地址中不要带协议或路径。

**显示已连接，但访问不到服务？**

到服务端管理后台检查端口映射，并确认被映射的本地服务已经启动。

**更新后打开的还是旧版本？**

先从托盘选择「退出应用」，再启动新版本。仅关闭主窗口会保留旧进程。

更多配置和操作说明见[本地运行与配置](docs/05-operations/client-app-local-development.md)，其他资料见[文档索引](docs/README.md)。

<details>
<summary>开发与构建</summary>

技术栈为 Rust + Tauri 2 + Vue 3。开发需要 Node.js 22.12+、Rust stable 和对应平台的构建工具。

```sh
git clone https://github.com/ynx-official/neutrino-proxy-client-desktop.git
cd neutrino-proxy-client-desktop
npm ci
cargo run
```

测试和环境准备见[本地开发文档](docs/05-operations/client-app-local-development.md)，安装包构建与版本发布见[发布说明](docs/06-delivery/releasing.md)。

</details>

## 许可证与来源

采用 [MIT License](LICENSE)，保留本项目及 Neutrino Proxy 上游版权声明。品牌、公开信任库和协议依据来自 Neutrino Proxy，详见[兼容性说明](docs/03-architecture/client-app-java-compatibility.md)。

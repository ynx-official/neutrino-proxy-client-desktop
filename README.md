<p align="center"><img src="assets/logo.png" width="88" alt="Neutrino Logo"></p>

# Neutrino Proxy Desktop

[![CI](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/ci.yml)
[![Release](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/release.yml/badge.svg)](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Neutrino Proxy 的 Windows / macOS 桌面客户端。使用 Flutter + Dart，内置纯 Dart 网络内核，提供连接配置、状态、日志和系统托盘，适合在后台保持隧道连接。安装后的应用不需要 Java、Rust、Node.js 或 Flutter SDK。

本仓库独立维护桌面客户端；服务端和端口映射继续使用 [Neutrino Proxy](https://github.com/ynx-official/neutrino-proxy)。协议行为参考其 Java 客户端及 core，兼容范围见[协议与架构](docs/03-architecture/protocol-and-architecture.md)。

## 功能

- 配置服务器、端口、License 和 TLS，手动连接、断开及自动重连。
- TCP / UDP 转发，心跳、空闲检测和连接状态展示。
- 导入 Java 客户端 YAML/JSON 配置，先预览差异，再应用；原文件保持不变。
- 支持内置信任证书、自定义 JKS / PEM / DER；校验证书链、主机名与有效期。
- License 与证书口令保存到系统安全存储，普通配置与凭证分离。
- 连接、日志、设置三页；关闭主窗口后留在托盘，从托盘恢复或退出。
- 日志有条数上限，并对凭证及敏感内容进行脱敏。

## 下载与使用

从 [Releases](https://github.com/ynx-official/neutrino-proxy-client-desktop/releases) 选择版本。首次推送有效版本 tag 且工作流成功后才会出现安装包；普通提交的验证包位于 [Actions](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions) 对应运行的 Artifacts。

| 平台 | 文件 | 使用方法 |
| --- | --- | --- |
| Windows 10/11 x64 | `*-windows-x64.zip` | 完整解压，运行 `Neutrino/neutrino_proxy_client_desktop.exe`，保留同目录 DLL 与 `data/` |
| macOS 12+，Intel / Apple Silicon | `*-macos-universal.dmg` | 打开磁盘映像，将 `Neutrino.app` 拖到 Applications |
| macOS 便携分发 | `*-macos-universal.zip` | 解压得到 `Neutrino.app` |

Windows 包未配置商业代码签名；macOS 使用无需证书的 ad-hoc 签名，未做 Apple 公证。系统可能提示无法验证开发者；确认下载来源与 `SHA256SUMS` 后，按系统提示或 macOS“系统设置 → 隐私与安全性”中的允许选项打开。首次 macOS 原生交互与完整服务端互通的验收状态见[验证记录](docs/04-quality/verification.md)。

1. 在设置中填写服务端域名/IP、对应隧道端口和 License，TLS 开关应与服务端一致。域名/IP 不含 `https://` 或路径。
2. 按需导入旧配置或选择信任证书，然后保存。
3. 返回连接页点击连接。保存的新配置在下一次连接时生效，不会改变正在运行的连接。
4. 在既有管理后台配置端口映射。通过日志页排查连接问题，通过托盘的“退出”完整关闭客户端。

默认启用 TLS、端口为 `9002`、重连间隔为 10 秒；实际值以你的服务端为准。非默认 Netty 帧布局会阻止导入；Java 线程池参数不能直接对应 Dart isolate。

## 本地开发

使用 Flutter **3.47.5**（附带 Dart **3.13.4**），依赖版本以 `pubspec.lock` 为准。

- Windows：Visual Studio 2022 / Build Tools 及“使用 C++ 的桌面开发”、Windows SDK；先用 `flutter doctor -v` 检查。
- macOS：Xcode、命令行工具和插件要求的 CocoaPods；只能在 macOS 构建 macOS 应用。
- Python 3.11+：仅供发布辅助脚本和其测试使用，不是应用运行依赖。

```sh
git clone https://github.com/ynx-official/neutrino-proxy-client-desktop.git
cd neutrino-proxy-client-desktop
flutter pub get --enforce-lockfile
flutter run -d windows
# macOS: flutter run -d macos
```

若使用项目本地 SDK，可将 `flutter` 替换成 `.tools/flutter/bin/flutter.bat`；`.tools/` 不入库。Windows 未启用符号链接支持时，可以在获取依赖后执行 `pwsh -File scripts/prepare-windows-links.ps1` 创建项目内插件目录联接。

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
python scripts/generate-test-certificates.py
flutter test --no-pub --reporter expanded
python -m unittest discover -s scripts/tests -v
flutter build windows --release --no-pub
# macOS: flutter build macos --release --no-pub
```

构建结果位于 `build/windows/x64/runner/Release/` 或 `build/macos/Build/Products/Release/Neutrino.app`。Windows 运行包必须包含整个 Release 目录，不能只复制 EXE；对外分发前运行 `pwsh -File scripts/copy-windows-runtime.ps1` 补齐 Visual C++ 运行库，CI 会自动完成。

## 自动打包与发布

- `main` 提交、Pull Request 和手动 CI：两端格式检查、静态分析、测试、Release 构建与打包，上传 Actions 验证产物。
- 推送 `vX.Y.Z` tag：注入版本号，构建 Windows x64 和 macOS 通用版，验证三份分发包、来源提交和 SHA-256，再自动公开 GitHub Release。
- `vX.Y.Z-alpha.N`、`vX.Y.Z-beta.N`、`vX.Y.Z-rc.N`：相同检查，发布为预发行版，不更新 Latest。
- 非法 `v*` tag 会失败；任一平台失败、缺包或哈希不匹配都不会公开 Release。

例如，完成验证并决定发布 `0.1.0` 时，由维护者执行：

```sh
git tag -a v0.1.0 -m "Neutrino Desktop v0.1.0"
git push origin v0.1.0
```

工作流只使用 GitHub 自动提供的 `GITHUB_TOKEN`，无需配置签名证书或个人 Token。具体版本规则、权限、失败恢复与发布流程见[发布说明](docs/06-delivery/releasing.md)。

## 目录与文档

```text
lib/core/          纯 Dart 协议、证书解析与 TCP/UDP 引擎
lib/application/   isolate 通信、配置持久化和状态管理
lib/platform/      窗口、托盘和系统凭证存储
lib/ui/            连接、日志和设置页面
windows/ macos/    原生桌面宿主
test/             协议、真实本地 socket、存储和界面测试
scripts/          打包、发布校验及测试
.github/workflows/ CI 与 tag 发布工作流
docs/             需求、架构、验证和发布说明
```

更多说明见[文档索引](docs/README.md)。当前自动化测试使用本机模拟服务端，不能替代完整真实服务端、长时间运行及各平台原生交互验收；已知限制以验证记录为准。

## 许可证与来源

采用 [MIT License](LICENSE)。保留本仓库与 Neutrino Proxy 上游的版权声明。项目标识及内置公开信任库来自 Neutrino Proxy；`test/fixtures/tls/` 中的证书与私钥仅用于本机测试，不是应用凭证，且不打入分发包。测试前使用上面的脚本刷新测试证书，需要 OpenSSL 3（Git for Windows 已附带；macOS 使用 Homebrew `openssl@3`）；CI 自动生成，避免证书到期导致误报，详情见 [TLS 测试证书](docs/04-quality/tls-fixtures.md)。

Neutrino Proxy 的 Flutter / Dart 桌面客户端，提供连接配置、TLS、TCP/UDP 转发、重连、状态、日志和托盘入口。端口映射继续使用既有管理后台。

## 下载

- Windows x64：推荐双击 `windows-x64-setup.exe` 安装，支持安装目录、快捷方式和卸载；便携版仍可解压 `windows-x64.zip` 使用。
- macOS Intel / Apple Silicon：使用 `macos-universal.dmg`，将 Neutrino 拖入 Applications；也提供完整 `.app` ZIP。
- `SHA256SUMS` 和 `release-manifest.json` 用于核对下载完整性、版本和来源提交。

## 说明

Windows 未配置商业代码签名；macOS 为 ad-hoc 签名，未做 Apple 公证。系统可能要求在安全设置中确认开发者来源。应用运行不需要 Java、Rust 或 Flutter SDK。

自动构建与本地模拟对端测试不代表完整真实服务端或长期运行验收。各平台实测状态与已知限制见仓库 `docs/04-quality/verification.md`。

<!-- 文档状态：Review；最后更新：2026-10-16；关联：releasing.md。 -->

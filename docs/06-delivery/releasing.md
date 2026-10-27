# 独立桌面客户端构建与发布

状态：Review
最后更新：2026-10-27

关联文档：[README](../../README.md)、[拆分记录](project-extraction.md)、[本地运行](../05-operations/client-app-local-development.md)、[验证记录](client-app-development-status.md)

## 仓库边界

桌面客户端在本仓库根目录构建，使用自身 package-lock.json、Cargo.lock 和 v* tag。主仓库只构建服务端 / 命令行客户端；两边不跨仓库触发、不同步版本，不需要相邻 Java 源码。

## 工作流

- `ci.yml`：分支提交、PR、手动触发，调用 `build.yml`。
- `build.yml`：复用的三平台构建；Windows 2022 / x64、Intel macOS / x64、Apple Silicon macOS / arm64 分别执行 Node 22、Rust stable、锁定依赖、格式 / Clippy、Python 发布测试、Vue 和 Rust 测试。Windows 额外跑 Edge 页面流程。
- `release.yml`：tag 或手动选择已有 tag；先校验版本并解析实际提交，三个构建均检出该 SHA，再汇总四个分发文件。只有 publish 作业有 contents:write。

普通 CI 从 package.json 读取版本；tag 发布在 CI 临时检出中同步 package.json、package-lock.json（含根包）、Tauri 配置、两个 Cargo 包及 Cargo.lock。既不回写版本提交，也不创建 tag。

## 分发产物

示例版本 0.1.1；必须齐备以下四份文件，另附 `release-manifest.json` 与 `SHA256SUMS`：

| 文件 | 内容 |
|---|---|
| `neutrino-proxy-client-desktop-0.1.1-windows-x64-setup.exe` | Tauri NSIS 安装包，按需安装 WebView2 |
| `neutrino-proxy-client-desktop-0.1.1-windows-x64-portable.zip` | 可执行文件与 LICENSE，系统需有 WebView2 |
| `neutrino-proxy-client-desktop-0.1.1-macos-x64.dmg` | Intel Mac 安装镜像 |
| `neutrino-proxy-client-desktop-0.1.1-macos-arm64.dmg` | Apple Silicon Mac 安装镜像 |

Windows 不配置开发者签名；macOS 使用 `-` 身份 ad-hoc 签名、未公证。应用代码签名和隧道 SSL 是独立机制。

CI 的直接下载入口是 `windows-x64-installer`；三平台完整中间文件分别在 `desktop-windows-x64`、`desktop-macos-x64`、`desktop-macos-arm64`，保留 14 天。Release 汇总包为 `release-complete`，公开附件不依赖临时 artifact。

## 发布保护

1. tag 必须为合法 vMAJOR.MINOR.PATCH，可带预发布标识；拒绝路径、shell 片段、数字前导零及超出 Windows 安装器范围的版本。
2. 每个平台记录版本、源提交、平台及工具版本。汇总时要求三个平台记录准确齐备且版本 / 提交一致，四个非空分发包文件名准确，不接受额外文件。
3. 生成 manifest 和 SHA256SUMS，上传前再次检查文件清单、哈希、构建版本和提交；远程 tag 必须仍指向该提交。
4. 先上传到内部草稿，逐个核对 GitHub 返回的大小及 digest，再自动公开。上传失败不能公开半套产物；只恢复同提交、本工具创建的草稿。已公开 Release 不修改，修订使用新 tag。
5. 正式 tag 设置 Latest；预发布 tag 设置 prerelease 且不更新 Latest。使用内置 GITHUB_TOKEN，不需要 PAT 或签名证书。

默认跑全部测试。手动 Release 的 publish 默认为 false；skip_tests 默认为 false，只对本次显式选择生效，manifest 记录实际跳过状态。格式、Clippy、构建、来源和哈希验证始终执行。

## 本地检查和打包

在仓库根目录执行：

```powershell
python -m unittest discover -s scripts/release -p 'test_*.py' -v
npm.cmd run tauri -- icon src-tauri/icons/app-icon.png --output target/release-icons
npm.cmd run desktop:bundle -- --target x86_64-pc-windows-msvc --bundles nsis -- --locked
python scripts/release/release.py desktop --tag v0.1.0 --platform windows-x64 --target x86_64-pc-windows-msvc
```

上面的本地示例不注入版本，以当前 package.json 的 0.1.0 构建；需要其他版本时，仅在隔离检出中先执行 prepare。不要用包装文件名掩盖二进制版本。macOS 在对应机器生成图标后使用相同 bundle 命令，target 分别为 x86_64-apple-darwin、aarch64-apple-darwin，bundles 为 dmg。

本轮是否实际运行 CI、安装及 macOS 验证，以[拆分记录](project-extraction.md)为准；配置工作流不等于远端作业已经执行。

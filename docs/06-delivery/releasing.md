# 桌面客户端自动发布

状态：Review  
最后更新：2026-10-16  
关联文档：[README](../../README.md)、[验证记录](../04-quality/verification.md)、[发布说明模板](release-notes-template.md)

## 范围与授权

2026-10-16 用户要求将独立 Flutter 客户端提交到 `ynx-official/neutrino-proxy-client-desktop`，建立远程连接，完善 README 和 `v*` tag 自动打包工作流。本次配置发布能力，不创建版本 tag。后续由维护者明确决定版本并推送 tag，工作流自动完成发布。

本仓库只打包桌面应用，不打包 Java 服务端或命令行客户端。应用无商业签名证书或 Apple 公证，macOS 沿用工程现有 ad-hoc 签名。打包设计与平台原生验证状态分别记录，不用工作流配置代替成功运行证据。

## 工作流

| 文件 | 触发 | 职责 |
| --- | --- | --- |
| `.github/workflows/ci.yml` | main、PR、workflow_dispatch | 调用同一构建链，产物保存 14 天，不创建 Release |
| `.github/workflows/build.yml` | workflow_call | 固定 Flutter 3.47.5，锁定依赖，格式/analyze/test，Windows/macOS 构建与校验 |
| `.github/workflows/release.yml` | 推送 `v*` tag | 等待两端通过，验证所有产物，生成校验清单，创建草稿并上传后自动公开 |

Windows 使用 `windows-2022`；macOS 使用 `macos-15`，显式关闭仅 arm64 构建，并检查每个 Mach-O 文件包含 `x86_64` 和 `arm64`。macOS 运行 `codesign --verify --deep --strict`、ZIP 校验和 `hdiutil verify`。CI 构建不需要同级 Java 仓库存在。

构建作业仅有 `contents: read`；发布作业单独获得 `contents: write`，使用当次运行的 `GITHUB_TOKEN`。不需要额外 Secrets，不在 PR 中使用写权限令牌，不自动创建 tag。

## 版本规则

- 正式版：`vX.Y.Z`。
- 预发行版：`vX.Y.Z-alpha.N`、`vX.Y.Z-beta.N`、`vX.Y.Z-rc.N`。
- 各数字不能有多余前导零；X/Y/Z 在 0–65535 范围内，符合 Windows 版本资源约束。
- 原生 `--build-name` 使用 X.Y.Z；`--build-number` 使用调用工作流的 `github.run_number`（1–65535）。同一次运行重试保持不变，超限明确失败。
- 预发行后缀保留在 tag、Release 标题、文件名和清单中；原生版本字段仍为数字版本。
- CI 无 tag 时从 `pubspec.yaml` 读取基础版本。tag 构建使用 tag 作为版本来源，不回写源码或推送版本提交。

## 必需产物

1. `neutrino-proxy-client-desktop-<tag>-windows-x64.zip`：完整运行目录，保留 EXE、全部运行 DLL、资源和 AOT 数据，从 Visual Studio Redist 目录补齐 x64 Visual C++ 运行库，排除调试符号。
2. `neutrino-proxy-client-desktop-<tag>-macos-universal.zip`：完整 `.app`，保留 macOS 资源、权限和链接。
3. `neutrino-proxy-client-desktop-<tag>-macos-universal.dmg`：应用及 Applications 链接。
4. `SHA256SUMS`：三份分发包的 SHA-256。
5. `release-manifest.json`：tag、原生版本、构建号、完整 Git SHA、文件名、大小与 SHA-256。

两端分别生成构建记录；汇总重新计算文件大小和哈希，并核对 tag、构建号和 Git SHA。缺少产物、混入其他 ZIP/DMG 或内容被改变都会失败。发布不上传测试私钥、开发 SDK、缓存或用户配置。

## 操作与失败恢复

1. 查看目标提交的 CI，检查两端均成功；确认本次更新内容和验证边界。
2. 需要特定版本说明时，先更新发布说明模板，再提交代码。
3. 在待发布提交创建并推送 tag。完整命令见根 README。
4. 查看 Release workflow。首次创建时先为草稿，上传五份产物且核对数量后自动公开；预发行版不更新 Latest。
5. 下载后运行 `sha256sum -c SHA256SUMS`，macOS 可用 `shasum -a 256 -c SHA256SUMS`；Windows 可用 `Get-FileHash <文件路径> -Algorithm SHA256` 对照清单。

构建阶段失败：先查看失败日志。临时网络问题可重跑失败作业；代码问题应修复后发布新 tag，避免移动已发布 tag。完整重跑与失败作业重跑都使用原运行构建号。

发布中断：已上传的草稿不会自动公开，也不会被后续运行覆盖。维护者先核对草稿 tag 与提交；若决定重跑发布，删除该未公开草稿后重跑 publish 作业。此删除由维护者明确操作，不能自动删除已公开版本。若公开步骤其实已成功而网络响应丢失，先检查 Release 状态，避免重复操作。

## 参考依据

- [Flutter Windows 分发与版本参数](https://docs.flutter.dev/deployment/windows)
- [Flutter macOS 分发](https://docs.flutter.dev/deployment/macos)
- [Flutter Action 固定版本](https://github.com/subosito/flutter-action)
- [GitHub 托管运行器](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

通用二进制与签名参数同时依据本机 Flutter 3.47.5 的 `flutter_tools` 源码核对，最终可用性以 GitHub macOS 构建结果和原生运行验收为准。

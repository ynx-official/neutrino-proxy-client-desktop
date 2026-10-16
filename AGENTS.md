# 项目协作约定

- 2026-10-16 用户选择 B：Flutter + Dart，网络内核使用纯 Dart；不得引入 Rust/Tauri/Java 运行时。
- 目录独立于原仓库。网络行为唯一依据是 `../neutrino-proxy/neutrino-proxy-client` 与 `neutrino-proxy-core` 的官方 Java 源码；`neutrino-proxy-client-app` 仅参考布局、视觉及桌面交互。
- 目标为 Windows/macOS 本机连接工具：连接配置、License、TLS、TCP/UDP 转发、重连、状态、日志、托盘与窗口恢复。端口映射继续在现有管理后台管理。
- 正式说明放在 `docs/`，维护 `docs/README.md`；区分已确认需求、实现选择与实际验证结果。
- 不自动提交、推送、创建标签或发布；不读取或修改原客户端的用户凭证/配置。
- 新功能先写行为测试；协议使用从 Java 编码规则独立构造的向量与真实本地 socket 对端验证。macOS 未运行不能声称通过。

## UI design system

- Skill: `awesome-design-md`
- Source: `VoltAgent/awesome-design-md`
- Style ID: `airtable`
- Style reference: `C:/Users/Administrator/.codex/skills/awesome-design-md/references/design-md/airtable/DESIGN.md`
- 用户要求参考既有 App：顶部连接/日志/设置导航，白色画布，细分隔线，无外层卡片或大色块。默认窗口 860×620，内容最大宽度 736；使用项目原 Logo。
- 2026-10-16 用户要求直接复用既有 App 的透明图标：托盘使用 `neutrino-proxy-client-app/src-tauri/icons/tray.png`，Windows 仅转换为保留 alpha 的多尺寸 ICO。同日进一步要求任务栏与窗口左上角统一为透明版本：Windows 应用图标的小尺寸与托盘逐像素一致，大尺寸从同一原 Logo 等比生成，不添加白色底座。macOS 应用资源仍沿用原 App 平台资源。
- 视觉依据：`../neutrino-proxy/docs/02-design/client-app-ui.md` 及该文档引用的已批准样图；优先于通用 Airtable 营销页面样式。
- 2026-10-16 用户要求托盘右上角增加状态点：仅 `connected` 显示绿色，其他状态显示灰色。状态点由原生宿主更新，保留透明 Logo 和透明背景，不改变任务栏/窗口应用图标。

## Implementation

- 2026-10-16 用户明确批准“Flutter + Dart 继续重构方案，做完再对比”。实现采用原生薄宿主 + 独立纯 Dart AOT worker + 按需 Flutter UI；详见 `docs/03-architecture/background-process-design.md` 和 `docs/06-delivery/background-process-plan.md`。Android 不在本次交付范围。
- Flutter stable 与其配套 Dart；Riverpod 投影 IPC 状态。协议、配置、证书解析和引擎保持不依赖 Flutter；worker 用自己的 pubspec/lockfile 构建，UI detach/退出不得 disconnect 网络。普通最小化仍保留 UI，关闭窗口才释放。
- Windows 原生宿主管理托盘、进程和 DPAPI；macOS Swift 宿主源码已补齐但未在本机执行。后台内存计入全部应用进程，不以工作集裁剪制造下降。
- 自动化窗口开关测试会打扰用户，执行前明确告知；默认使用 `--cycles 0` 做无界面采样。测试配置必须隔离，不读取或修改实际用户凭证。
- 所有凭证使用系统安全存储，日志不得包含 License、密码或业务载荷。
- 配置保存不改变当前连接，重新连接时使用最新配置；认证失败停止会话但保留桌面界面供修正。
- `.tools/` 是本地 SDK 缓存，不纳入版本控制。不自动更改全局 PATH。

## Repository and release

- 远程：`https://github.com/ynx-official/neutrino-proxy-client-desktop.git`，默认分支 `main`。2026-10-16 用户明确授权首次提交、推送本目录并建立远程连接。
- `v*` tag 自动打包 Windows x64 ZIP、macOS 通用 ZIP/DMG；检查完整产物后自动发布 Release，预发行 tag 标记为 prerelease。详见 `docs/06-delivery/releasing.md`。
- 本次工作流配置不包含创建 tag；后续提交、推送和创建 tag 仍需用户明确授权。
- 2026-10-16 用户追加授权“正式发版，跳过测试”：发布本次 Flutter 客户端改造为 `v0.1.0`，允许提交、推送并创建 tag；仅本次发布跳过测试，保留构建与产物完整性检查，后续版本默认恢复测试。
- 发布只用内置 `GITHUB_TOKEN`，不配置商业签名或公证；macOS 使用工程现有 ad-hoc 签名。缓存、SDK、构建目录和用户凭证不得提交。

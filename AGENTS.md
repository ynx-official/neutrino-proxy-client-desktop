# 项目协作约定

## 范围与技术路线

- 本仓库作为独立桌面客户端项目维护，源码、依赖和构建工作流均位于仓库根目录。
- 技术路线：Rust + Tokio 内核、Tauri 2 宿主、Vue 3 + JavaScript、Vite、npm。Cargo workspace 和 package.json 位于根目录，构建不依赖邻接的 Java 仓库。
- Windows/macOS 本机连接工具：连接配置、License、SSL、TCP/UDP、重连、状态、日志、原生托盘及窗口恢复；服务端、Java CLI、端口映射管理仍在 Neutrino Proxy 仓库。
- 保持 Tauri 标识 `fun.neutrino.proxy.desktop` 和原 Rust App 的配置/凭证语义，不因仓库或可执行文件重命名迁移用户秘密。
- Java 兼容边界见 `docs/03-architecture/client-app-java-compatibility.md`；保留用户授权的 TLS 不校验主机名、仍验证信任与握手签名行为。
- 应用设置默认关闭、自动保存。完整配置在进程启动时尝试连接一次，初始失败停止，成功后保留既有断线重连；托盘恢复不重复触发。
- 连接配置的 SSL 默认关闭；新配置或缺失该字段时使用关闭，已保存及导入的显式开关值保持不变，用户可手动开启。

## UI design system

- Skill: `awesome-design-md`
- Source: `VoltAgent/awesome-design-md`
- Style ID: `airtable`
- Style reference: `C:/Users/Administrator/.codex/skills/awesome-design-md/references/design-md/airtable/DESIGN.md`
- Approved variant: 顶部导航、白色画布、细分隔线、无外层卡片与大色块；默认/最小窗口 860×620，项目简约适配优先。
- 基线：`docs/02-design/assets/client-app-minimal-approved.png`；应用设置：`docs/02-design/assets/client-app-application-settings-approved.png`；托盘：`docs/02-design/assets/client-app-native-tray-approved.png`。
- 托盘必须使用系统原生菜单，不创建托盘 WebView；状态行、小图标、禁用服务器摘要、互斥连接动作及两个分隔线沿用已确认预览。
- 品牌源：`assets/logo/logo.png`；应用图标母版：`src-tauri/icons/app-icon.png`。当前视觉详见 `docs/02-design/client-app-ui.md`。

## 文档与验证

- 正式文档统一放 `docs/`，维护 `docs/README.md`，注明状态、更新时间和验证边界；不得包含真实 License、Token、密码、生产地址或私钥。
- 复用 npm、Cargo 与 `scripts/release/` 的测试和构建命令；新功能/缺陷先补行为测试。网络使用本地对端、虚构凭证，不操作用户实际连接或凭证。
- Windows、macOS、原生交互和系统登录启动分别验收，未执行不能声称通过。协议向量已入库，Java 仅用于可选的向量再生成。

## 仓库与发布

- 远程：`https://github.com/ynx-official/neutrino-proxy-client-desktop.git`；保留本项目及上游版权声明。
- CI 在根目录构建 Windows x64 安装 EXE/便携 ZIP、Intel macOS DMG、Apple Silicon DMG；与服务端独立版本、独立 tag，不跨仓库触发。
- `v*` tag 在全部产物、来源提交和哈希验证后自动公开 Release；带预发布标识的 tag 为 prerelease。Windows 无商业签名，macOS ad-hoc、不公证。
- 默认执行测试；手动 Release 的 skip_tests 只限当次明确选择，格式、Clippy、构建和产物校验不跳过。规则见 `docs/06-delivery/releasing.md`。
- 不自动提交、推送、创建 PR/tag、切换或删除分支、发布或清理工作区；保留任务外修改。
